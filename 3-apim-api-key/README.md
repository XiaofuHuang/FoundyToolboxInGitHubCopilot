# Foundry Toolbox with an APIM API key and managed identity

[English](README.md) | [简体中文](README.zh-CN.md)

This is a separate deployment from `1-apim-toolbox`. Clients present an
**APIM subscription key**, while APIM accesses Foundry using its own
system-assigned managed identity. There is no user token passthrough, OAuth
discovery, OBO exchange, or interactive Microsoft sign-in for MCP clients.

```text
VS Code or another MCP client
  -> APIM: Ocp-Apim-Subscription-Key
  -> Foundry Toolbox: bearer token for APIM's managed identity
  -> Microsoft Learn MCP: public tool, no downstream authentication
```

## Identity and access

APIM requires a subscription key for the `foundry-toolbox` API. The template
creates an active subscription named `toolbox-client`, scoped to this API;
Azure generates its primary and secondary keys. Neither key is a Bicep output.

After the key is validated, the API policy removes it and any caller-supplied
`Authorization` header. `authentication-managed-identity` requests a token for
`https://ai.azure.com` and sets the backend bearer header. APIM caches this
managed identity token until expiry. Requests are routed to a fixed published
Toolbox endpoint; client query parameters are not forwarded.

The inbound policy explicitly forwards JSON-RPC requests and returns the
Toolbox response, rather than letting APIM's generated MCP catalog supply
the tool list. Like the OAuth sample, this request/response implementation
buffers backend responses; it is not a general long-lived SSE relay.

The managed identity receives **Foundry User** at the **project scope**, not
the subscription scope. Clients do not need their own Foundry roles. All
key holders use the same backend identity and its permissions: Foundry does
not receive the individual client's Entra identity.

This sample contains **Microsoft Learn only**. A per-user GitHub OAuth
connection cannot preserve user identity through this flow. Shared credentials
or a downstream service identity would be a separate connection design.

## Prerequisites and cost

- Azure CLI and Azure Developer CLI (`azd`).
- The `azure.ai.projects` and `azure.ai.toolboxes` azd extensions.
- Azure permissions to create resources and role assignments, such as Owner
  or Contributor plus Role Based Access Control Administrator.
- A current VS Code release supporting HTTP MCP and password input variables.

No custom Entra client application, federated credential, tenant-wide consent,
or GitHub OAuth App is required for this gateway.

> [!IMPORTANT]
> This creates another **APIM BasicV2** instance with ongoing Azure charges.
> Use a new environment name, resource group, and APIM name. No automatic
> cleanup is configured. The OAuth sample's deployment is not modified.

## 1. Configure a new environment

Run from `3-apim-api-key`. Install missing Foundry extensions if needed:

```powershell
azd extension install azure.ai.projects
azd extension install azure.ai.toolboxes
```

Sign into the intended tenant and subscription:

```powershell
az login --tenant '<tenant-id>'
az account set --subscription '<subscription-id>'
azd auth login --check-status
```

If azd uses built-in authentication, use `azd auth login --tenant-id
'<tenant-id>'`. If it delegates authentication to Azure CLI, `az login` is
sufficient.

```powershell
azd env new '<new-environment-name>' `
  --subscription '<subscription-id>' `
  --location eastus2

azd env set AZURE_RESOURCE_GROUP '<new-resource-group>'
azd env set APIM_NAME '<new-globally-unique-apim-name>'
azd env set APIM_PUBLISHER_EMAIL '<your-email-address>'
azd env set APIM_PUBLISHER_NAME '<your-organization-name>'
```

## 2. Provision and deploy

```powershell
azd provision --no-prompt
azd deploy --no-prompt
```

Provisioning creates a new Foundry account/project, APIM managed identity,
project-scoped role assignment, MCP API, policy, and API-scoped subscription.
Deployment creates the `tools` Toolbox with Microsoft Learn.

Publish the version that clients should use:

```powershell
$projectEndpoint = azd env get-value FOUNDRY_PROJECT_ENDPOINT
$versions = azd ai toolbox versions list tools `
  --project-endpoint $projectEndpoint --output json | ConvertFrom-Json
$version = $versions.versions |
  Sort-Object { [int]$_.version } -Descending |
  Select-Object -First 1 -ExpandProperty version
if (-not $version) { throw 'No Toolbox version was returned.' }
azd ai toolbox publish tools $version `
  --project-endpoint $projectEndpoint --no-prompt

azd env get-value APIM_TOOLBOX_MCP_URL
```

New managed identities and RBAC assignments can take time to propagate. A
temporary backend authorization error is not a reason to disable key
validation or substitute the deploying user's token.

## 3. Connect VS Code

In Azure Portal, open the new APIM instance, select **Subscriptions**, then
open **Foundry Toolbox MCP client**. Reveal a key only when ready to copy it
into VS Code's password input. This is an APIM key, not a Foundry API key.

Copy [the sample configuration](samples/vscode/mcp.json.example) into
`.vscode\mcp.json` in the workspace you actually open, merging existing
`inputs` and `servers` instead of overwriting them. Replace
`<APIM_TOOLBOX_MCP_URL>` with the deployment output.

The essential authentication configuration is:

```json
{
  "inputs": [
    {
      "id": "foundryToolboxApimKey",
      "type": "promptString",
      "description": "APIM subscription key for the Foundry Toolbox",
      "password": true
    }
  ],
  "servers": {
    "foundry-toolbox-api-key": {
      "type": "http",
      "url": "<APIM_TOOLBOX_MCP_URL>",
      "headers": {
        "Ocp-Apim-Subscription-Key": "${input:foundryToolboxApimKey}"
      }
    }
  }
}
```

Start `foundry-toolbox-api-key` using **MCP: List Servers** and enter the key
in the masked prompt. No `oauth.clientId` or end-user Azure sign-in is needed.
Enable the Microsoft Learn tools in Copilot's tool picker.

VS Code saves input values securely. After key rotation, clear the saved
`foundryToolboxApimKey` input and restart the server to enter the replacement.

## Key handling and operational boundaries

- Never commit keys or put them in `azure.yaml`, azd environment values, chat,
  command history, or logs. Supply them in the header, not the URL query string.
- A leaked key grants the API's shared service access. Create separate
  API-scoped subscriptions for different consumers so access can be revoked
  independently, and rotate keys in APIM.
- Anyone able to edit the gateway's policies can affect use of its managed
  identity. Restrict management-plane access and keep its Foundry role scoped
  to the dedicated project.
- Missing or invalid keys are rejected by APIM. Foundry authorization failures
  require investigating the managed identity and its RBAC, not the client's
  personal Foundry permissions.
- This is a public endpoint. Add appropriate network controls, quotas, rate
  limits, and monitoring before sharing beyond the intended consumers.

## Cleanup

From this folder, confirm the selected azd environment and subscription, then
run `azd down` only when this deployment is no longer needed. This removes
its Azure resources, including the APIM instance and its system-assigned
identity. There is no separate Entra client application to remove.

Closing VS Code or stopping its MCP server does not stop APIM billing.

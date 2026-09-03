# APIM-fronted Foundry toolbox

This sample exposes a Microsoft Foundry toolbox through Azure API Management
(APIM). It contains no agent or model deployment.

## Request flow

```text
MCP client
  -> OAuth token for the APIM MCP endpoint
  -> APIM validates the user
  -> APIM exchanges the token for a Foundry user token through OBO
  -> APIM relays the MCP request to Toolbox
```

Toolbox receives the user's Entra identity and applies that user's Foundry RBAC.

One mixed-mode Entra application supplies the public client ID, represents the
APIM MCP resource, and performs OBO through APIM's federated managed identity.
No client secret is created.

## Resources

| Path | Purpose |
|---|---|
| `azure.yaml` | Creates the Foundry project/toolbox and orders infrastructure deployment. |
| `infra/apim.bicep` | Creates APIM and the mixed-mode Entra application. |
| `infra/modules/gateway.bicep` | Creates the APIM MCP API and OAuth metadata endpoints. |
| `infra/policies/` | Validates the APIM token, performs OBO, and relays MCP requests. |
| `copilot-plugin/` | Contains the Copilot CLI plugin and MCP configuration example. |
| `scripts/cleanup-entra.ps1` | Removes the tenant-level Entra app before `azd down`. |

## Deploy

Each caller needs **Foundry User** on the project. The deployer needs permission
to create an Entra application, service principal, federated credential, and
delegated permission grants.

```powershell
az login
azd auth login

azd env new '<environment-name>' `
  --subscription '<subscription-id>' `
  --location eastus2

azd env set AZURE_RESOURCE_GROUP '<resource-group>'
azd env set APIM_NAME '<globally-unique-apim-name>'
azd env set APIM_PUBLISHER_EMAIL 'you@example.com'
azd env set APIM_PUBLISHER_NAME 'Your organization'

azd up --no-prompt
```

Read the client configuration:

```powershell
azd env get-value APIM_TOOLBOX_MCP_URL
azd env get-value MCP_COPILOT_CLIENT_ID
```

## OAuth metadata

APIM publishes:

- `authorization_endpoint`: Entra browser login;
- `token_endpoint`: Entra token and refresh endpoint;
- `grant_types_supported`: `authorization_code` and `refresh_token`;
- protected-resource scope: APIM `user_impersonate`;
- authorization-server scopes: `user_impersonate` and `offline_access`.

OAuth refresh uses the token endpoint with `grant_type=refresh_token`.

## Visual Studio Code

Create a local `.vscode/mcp.json`:

```json
{
  "servers": {
    "foundry-toolbox": {
      "type": "http",
      "url": "<APIM_TOOLBOX_MCP_URL>",
      "oauth": {
        "clientId": "<MCP_COPILOT_CLIENT_ID>"
      }
    }
  }
}
```

Start `foundry-toolbox` from the MCP panel and complete authentication.

## GitHub Copilot CLI

Copy `copilot-plugin/.mcp.json.example` to `copilot-plugin/.mcp.json`, replace
the placeholders, then run:

```powershell
$env:COPILOT_ENTRA_DISABLE_ONEAUTH = '1'
copilot --plugin-dir .\copilot-plugin
```

Authenticate with `/mcp auth foundry-toolbox`.

## GitHub Copilot app limitation

Copilot app project sessions currently don't load user-installed plugin MCP
definitions or repository `.mcp.json` definitions. Authentication and tool
discovery therefore don't start in the app.

## Gateway behavior

The APIM policy:

1. Validates the APIM `user_impersonate` token.
2. Returns `405` for the optional Streamable HTTP GET backchannel.
3. Exchanges the user token for `https://ai.azure.com/.default` through OBO.
4. Relays MCP POST requests to Toolbox with `api-version=v1`.

## Security tradeoff

Because the same app is both public client and confidential OBO client, its
public flow can also request the delegated Foundry scope directly. Use separate
public-client and resource app registrations when APIM must be an enforced
governance boundary.

## Cleanup

```powershell
.\scripts\cleanup-entra.ps1
azd down
```

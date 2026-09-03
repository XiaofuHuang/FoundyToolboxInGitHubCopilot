# Connect GitHub Copilot to a Microsoft Foundry toolbox

[English](README.md) | [简体中文](README.zh-CN.md)

This sample deploys a Microsoft Foundry project and toolbox, then exposes the
toolbox through an OAuth-protected Azure API Management (APIM) endpoint. It
configures both Microsoft Learn and GitHub MCP servers as toolbox tools.

```text
GitHub Copilot CLI or VS Code
  -> APIM (user sign-in and token validation)
  -> Microsoft Foundry toolbox (user identity and Foundry RBAC)
  -> Microsoft Learn MCP or GitHub MCP
```

> [!IMPORTANT]
> The deployment creates an APIM Basic v2 instance, which incurs Azure charges.

## Prerequisites

Install:

- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- [Azure Developer CLI (`azd`)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- [GitHub Copilot CLI](https://docs.github.com/copilot/how-tos/set-up/install-copilot-cli)
  if you want to use the toolbox from a terminal

You also need:

- An Azure subscription
- Permission to create resource groups and resources in that subscription
- Microsoft Entra permission to create an application, service principal,
  federated credential, and tenant-wide delegated permission grants
- The **Foundry User** role on the deployed project for every toolbox user
- Permission to create a GitHub OAuth App
- A GitHub account for each user who authorizes the GitHub connection

If you cannot grant the Entra permissions, ask a tenant administrator to run
the deployment.

## 1. Install the Foundry extensions

Run these commands from the `1-apim-toolbox` directory:

```powershell
azd extension install azure.ai.projects
azd extension install azure.ai.connections
azd extension install azure.ai.toolboxes
```

## 2. Sign in and configure the environment

Replace every value in angle brackets:

```powershell
az login
azd auth login

azd env new '<environment-name>' `
  --subscription '<subscription-id>' `
  --location eastus2

azd env set AZURE_RESOURCE_GROUP '<resource-group-name>'
azd env set APIM_NAME '<globally-unique-apim-name>'
azd env set APIM_PUBLISHER_EMAIL '<your-email-address>'
azd env set APIM_PUBLISHER_NAME '<your-organization-name>'
```

`APIM_NAME` must be globally unique because it becomes part of the public
gateway hostname.

## 3. Provision Azure resources

```powershell
azd provision --no-prompt
```

Provisioning creates:

- The OAuth-protected APIM gateway for the Foundry toolbox

## 4. Deploy the toolbox

Create a [GitHub OAuth App](https://github.com/settings/applications/new). GitHub
requires an authorization callback URL when the app is created, so initially use
`https://example.com/callback`. Copy the client ID and generate a client secret.

Create the custom OAuth2 connection. The masked prompt keeps the client secret
out of the README, `azure.yaml`, the azd environment, and shell history:

```powershell
$projectEndpoint = azd env get-value FOUNDRY_PROJECT_ENDPOINT
$githubClientId = Read-Host 'GitHub OAuth App client ID'
$githubClientSecretSecure = Read-Host 'GitHub OAuth App client secret' -AsSecureString
$githubClientSecretPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR(
  $githubClientSecretSecure
)
$githubClientSecret = [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
  $githubClientSecretPointer
)

try {
  azd ai connection create github-oauth `
    --kind remote-tool `
    --target https://api.githubcopilot.com/mcp `
    --auth-type oauth2 `
    --client-id $githubClientId `
    --client-secret $githubClientSecret `
    --authorization-url https://github.com/login/oauth/authorize `
    --token-url https://github.com/login/oauth/access_token `
    --refresh-url https://github.com/login/oauth/access_token `
    --scopes 'repo read:org read:user user:email read:packages write:packages read:project project gist notifications workflow codespace' `
    --project-endpoint $projectEndpoint
}
finally {
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($githubClientSecretPointer)
  $githubClientSecret = $null
  $githubClientSecretSecure = $null
}
```

Foundry generates a unique callback URL for each connection. Print it with:

```powershell
$subscriptionId = azd env get-value AZURE_SUBSCRIPTION_ID
$resourceGroup = azd env get-value AZURE_FOUNDRY_RESOURCE_GROUP
$accountName = azd env get-value AZURE_AI_ACCOUNT_NAME
$projectName = azd env get-value AZURE_AI_PROJECT_NAME

$githubRedirectUrl = az rest `
  --method get `
  --url "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.CognitiveServices/accounts/$accountName/projects/$projectName/connections/github-oauth?api-version=2025-06-01" `
  --query properties.redirectUrl `
  --output tsv

$githubRedirectUrl
```

Return to the GitHub OAuth App settings and replace the temporary callback URL
with this exact value. The connection cannot complete user authorization until
the callback URL matches.

```powershell
azd deploy --no-prompt

$toolboxVersion = (
  azd ai toolbox versions list tools `
    --project-endpoint $projectEndpoint `
    --output json |
    ConvertFrom-Json
).versions |
  Sort-Object { [int]$_.version } -Descending |
  Select-Object -First 1 -ExpandProperty version

azd ai toolbox publish tools $toolboxVersion `
  --project-endpoint $projectEndpoint `
  --no-prompt
```

`azd deploy` creates an immutable toolbox version but does not make a later
version the default. Publishing is required so the consumer endpoint and APIM
serve the new `github-oauth` connection.

After deployment, print and copy the values needed by either client:

```powershell
azd env get-value APIM_TOOLBOX_MCP_URL
azd env get-value MCP_COPILOT_CLIENT_ID
```

## 5. Connect a client

### Visual Studio Code

Copy `samples\vscode\mcp.json.example` to `.vscode/mcp.json` in your workspace.
Replace both placeholders with the values printed after deployment:

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

Open the MCP panel, start `foundry-toolbox`, and complete the browser sign-in.

### GitHub Copilot CLI

The repository includes `samples\copilot-plugin\plugin.json` and
`samples\copilot-plugin\.mcp.json`. Edit `.mcp.json` and replace both
placeholders with the values printed after deployment:

```json
{
  "mcpServers": {
    "foundry-toolbox": {
      "type": "http",
      "url": "<APIM_TOOLBOX_MCP_URL>",
      "oauthClientId": "<MCP_COPILOT_CLIENT_ID>",
      "auth": {
        "redirectPort": 33418
      },
      "tools": [
        "*"
      ]
    }
  }
}
```

Start Copilot CLI with the plugin:

```powershell
$env:COPILOT_ENTRA_DISABLE_ONEAUTH = '1'
copilot --plugin-dir .\samples\copilot-plugin
```

In Copilot CLI, authenticate the server:

```text
/mcp auth foundry-toolbox
```

Complete the browser sign-in. The `foundry-toolbox` tools will then be
available, and Copilot will request approval before each tool call.

### Authorize GitHub once

Before GitHub is authorized, Foundry returns `CONSENT_REQUIRED` during tool
discovery. APIM translates that response into MCP URL elicitation:

1. Start `foundry-toolbox`.
2. Open the GitHub consent prompt:
   - In VS Code, approve the `consent.azure-apim.net` host in the
     **Authorization Required** card.
   - In Copilot CLI, open the URL shown under
     **foundry-toolbox wants you to visit**.
3. Authorize GitHub.
4. Restart `foundry-toolbox` to load the Microsoft Learn and GitHub tools.

Foundry uses your OAuth App to store and refresh each user's GitHub token. APIM
remains the only MCP server configured in either client; GitHub MCP is not
deployed in APIM.

## Troubleshooting

| Problem | Resolution |
|---|---|
| `azd provision` fails while creating Microsoft Graph resources | Run the deployment with an account that can create Entra applications and grant delegated permissions. |
| APIM creation reports that the name is unavailable | Set a different globally unique value with `azd env set APIM_NAME '<new-name>'`, then run `azd provision` again. |
| Sign-in succeeds but a toolbox call returns `403` | Assign the signed-in user the **Foundry User** role on the deployed Foundry project. |
| GitHub authorization is required | Open the URL from the VS Code authorization card or Copilot CLI consent prompt, authorize GitHub, and restart the MCP server. |
| GitHub reports a callback or redirect URL mismatch | Read `properties.redirectUrl` from the `github-oauth` connection and set it as the GitHub OAuth App's exact authorization callback URL. |
| GitHub rejects the OAuth client or secret | Verify the client ID, generate a new client secret, and recreate `github-oauth` with `--force`. |
| GitHub returns `HTTP_401` without a consent URL | Delete and recreate the custom GitHub OAuth connection. A revoked connector token cannot be converted into a new consent URL. |
| Copilot CLI does not discover the server | Start it from the `1-apim-toolbox` directory with `copilot --plugin-dir .\samples\copilot-plugin` and confirm that `samples\copilot-plugin\.mcp.json` exists. |

## Cleanup

Remove the tenant-level Entra objects before deleting the Azure resources:

```powershell
.\scripts\cleanup-entra.ps1
azd down
```

Delete the GitHub OAuth App manually if it is no longer needed.

## Security consideration

For simplicity, this sample uses one Entra application as both the public
client and the confidential on-behalf-of client. The public flow can therefore
request the delegated Foundry scope directly. Use separate public-client and
resource applications when APIM must be an enforced governance boundary.

The GitHub OAuth App requests broad access so all GitHub MCP capabilities except
repository deletion can be used. For production, reduce the scope list to only
the capabilities your users need. Never store the GitHub client secret in
`azure.yaml` or commit it to source control.

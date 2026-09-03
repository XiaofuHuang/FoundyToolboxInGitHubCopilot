# Connect GitHub Copilot to a Microsoft Foundry toolbox

This sample deploys a Microsoft Foundry project and toolbox, then exposes the
toolbox through an OAuth-protected Azure API Management (APIM) endpoint. It
configures the Microsoft Learn MCP server as the toolbox tool.

It does **not** deploy an agent or a model.

```text
GitHub Copilot CLI or VS Code
  -> APIM (user sign-in and token validation)
  -> Microsoft Foundry toolbox (user identity and Foundry RBAC)
  -> Microsoft Learn MCP
```

> [!IMPORTANT]
> The deployment creates an APIM Basic v2 instance, which incurs Azure charges.

## Prerequisites

Install:

- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- [Azure Developer CLI (`azd`)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- [GitHub Copilot CLI](https://docs.github.com/copilot/how-tos/set-up/install-copilot-cli)
  if you want to use the toolbox from a terminal
- PowerShell 7 or later to run the commands below

You also need:

- An Azure subscription
- Permission to create resource groups and resources in that subscription
- Microsoft Entra permission to create an application, service principal,
  federated credential, and tenant-wide delegated permission grants
- The **Foundry User** role on the deployed project for every toolbox user

If you cannot grant the Entra permissions, ask a tenant administrator to run
the deployment.

## 1. Install the Foundry extensions

Run these commands from the `4-apim-toolbox` directory:

```powershell
azd extension install azure.ai.projects
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

## 3. Deploy

```powershell
azd up --no-prompt
```

After deployment, print and copy the values needed by either client:

```powershell
azd env get-value APIM_TOOLBOX_MCP_URL
azd env get-value MCP_COPILOT_CLIENT_ID
```

## 4. Connect a client

### Visual Studio Code

Create `.vscode/mcp.json` from this template, then replace both placeholders
with the values printed after deployment:

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

Copy `copilot-plugin/.mcp.json.example` to `copilot-plugin/.mcp.json`. The
repository already includes the required `copilot-plugin/plugin.json`.

Edit `copilot-plugin/.mcp.json` and replace both placeholders with the values
printed after deployment:

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
copilot --plugin-dir .\copilot-plugin
```

In Copilot CLI, authenticate the server:

```text
/mcp auth foundry-toolbox
```

Complete the browser sign-in. The `foundry-toolbox` tools will then be
available, and Copilot will request approval before each tool call.

> [!NOTE]
> GitHub Copilot app project sessions currently do not load user-installed
> plugin MCP definitions or repository `.mcp.json` files. Use Copilot CLI or
> Visual Studio Code for this sample.

## Troubleshooting

| Problem | Resolution |
|---|---|
| `azd up` fails while creating Microsoft Graph resources | Run the deployment with an account that can create Entra applications and grant delegated permissions. |
| APIM creation reports that the name is unavailable | Set a different globally unique value with `azd env set APIM_NAME '<new-name>'`, then run `azd up` again. |
| Sign-in succeeds but a toolbox call returns `403` | Assign the signed-in user the **Foundry User** role on the deployed Foundry project. |
| Copilot CLI does not discover the server | Start it from the `4-apim-toolbox` directory with `copilot --plugin-dir .\copilot-plugin` and confirm that `copilot-plugin\.mcp.json` exists. |

## Cleanup

Remove the tenant-level Entra objects before deleting the Azure resources:

```powershell
.\scripts\cleanup-entra.ps1
azd down
```

## Security consideration

For simplicity, this sample uses one Entra application as both the public
client and the confidential on-behalf-of client. The public flow can therefore
request the delegated Foundry scope directly. Use separate public-client and
resource applications when APIM must be an enforced governance boundary.

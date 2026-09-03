# Simple guide: connect to a Microsoft Foundry Toolbox

This guide uses the shortest working commands for:

1. Azure CLI
2. REST with a bearer token
3. VS Code with a manually pasted token
4. VS Code through the APIM OAuth gateway
5. VS Code with a small authentication extension

The examples use PowerShell 7 on Windows.

The repository includes all three VS Code configurations from methods 3-5 in
`.vscode\mcp.json.example`. Copy it to `.vscode\mcp.json`, replace the
placeholders, and then start a server. The local `mcp.json` is ignored by Git.

## Before you start

You need:

- A published Toolbox MCP endpoint for methods 1-3 and 5.
- Azure CLI signed in to the correct tenant.
- The **Foundry User** role on the Foundry project.

Method 4 can create the Foundry project and toolbox for you. See the additional
prerequisites in [`4-apim-toolbox/README.md`](4-apim-toolbox/README.md).

The current role name is **Foundry User**. It was previously named
**Azure AI User**.

Do not confuse the role with the OAuth scope:

- OAuth token scope: `https://ai.azure.com/.default`
- Azure RBAC role: **Foundry User**

No `Foundry-Features` header is required.

Set your endpoint:

```powershell
$toolboxUrl = 'https://<account>.services.ai.azure.com/api/projects/<project>/toolboxes/<toolbox>/mcp?api-version=v1'
```

## 1. Simplest Azure CLI test

Sign in:

```powershell
az login --tenant '<tenant-id>'
```

Call `tools/list`:

```powershell
$body = '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'

az rest `
  --method post `
  --resource https://ai.azure.com `
  --url $toolboxUrl `
  --headers 'Content-Type=application/json' 'MCP-Protocol-Version=2025-11-25' `
  --body $body
```

`az rest` gets the Entra token for you. A successful response contains
`result.tools`.

## 2. Simplest REST test

Get a token from your Azure CLI login:

```powershell
$token = az account get-access-token `
  --scope https://ai.azure.com/.default `
  --query accessToken `
  --output tsv
```

Call the Toolbox with `curl.exe`:

```powershell
$body = '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'

curl.exe -sS -X POST $toolboxUrl `
  -H "Authorization: Bearer $token" `
  -H 'Content-Type: application/json' `
  -H 'MCP-Protocol-Version=2025-11-25' `
  --data $body
```

The token normally expires in about one hour. Do not print, save, commit, or
share it.

## 3. VS Code with a manually pasted token

Get a token and copy it:

```powershell
$token = az account get-access-token `
  --scope https://ai.azure.com/.default `
  --query accessToken `
  --output tsv

Set-Clipboard $token
```

The `toolbox-manual-token` entry in `.vscode\mcp.json` uses this configuration:

```jsonc
{
  "inputs": [
    {
      "id": "toolboxToken",
      "type": "promptString",
      "description": "Foundry Toolbox access token",
      "password": true
    }
  ],
  "servers": {
    "toolbox-manual-token": {
      "type": "http",
      "url": "https://<account>.services.ai.azure.com/api/projects/<project>/toolboxes/<toolbox>/mcp?api-version=v1",
      "headers": {
        "Authorization": "Bearer ${input:toolboxToken}"
      }
    }
  }
}
```

In VS Code:

1. Run **MCP: List Servers**.
2. Start `toolbox-manual-token`.
3. Paste only the token, without the `Bearer` prefix.

When the token expires, get a new token and restart the server.

## 4. VS Code through APIM

Use this method when you want browser sign-in, automatic token refresh, and an
APIM gateway in front of the Foundry toolbox.

The deployable sample is in [`4-apim-toolbox/`](4-apim-toolbox/). It provisions:

- A Microsoft Foundry project and toolbox containing Microsoft Learn and GitHub
- An APIM Basic v2 gateway
- OAuth metadata and token validation policies
- A Microsoft Entra application for browser authentication and on-behalf-of
  token exchange

Follow [`4-apim-toolbox/README.md`](4-apim-toolbox/README.md) to deploy the sample
and obtain these values:

```powershell
azd env get-value APIM_TOOLBOX_MCP_URL
azd env get-value MCP_COPILOT_CLIENT_ID
```

In the `foundry-toolbox` entry in `.vscode\mcp.json`, replace both placeholders:

```jsonc
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

Then:

1. Run **MCP: List Servers**.
2. Start `foundry-toolbox`.
3. Complete the browser sign-in.

Both Microsoft Learn and GitHub tools are discovered through this single APIM
server. The first GitHub use returns a one-time `CONSENT_REQUIRED` message in
the MCP output. Open its consent URL, authorize GitHub, and restart
`foundry-toolbox`.

## 5. VS Code with an authentication extension

The extension source is in [`5-vscode-extension/`](5-vscode-extension/).

This method depends on the **Azure Resources** VS Code extension. It reuses the
account from **Azure: Sign In** and returns a Foundry access token to
`mcp.json`. No separate Entra app registration is needed.

Install Azure Resources, run **Azure: Sign In**, and optionally set the tenant
when your account uses multiple tenants:

```jsonc
{
  "foundryToolboxAuth.tenantId": "<tenant-id>"
}
```

### Package and install the extension

```powershell
cd .\5-vscode-extension
npm ci
npm run package
code --install-extension .\foundry-toolbox-auth-0.0.2.vsix --force
```

Reload VS Code, then run **Foundry Toolbox: Sign In**.

### Connect the Toolbox

The `toolbox-extension-auth` entry in `.vscode\mcp.json` uses this configuration:

```jsonc
{
  "inputs": [
    {
      "id": "toolboxExtensionToken",
      "type": "command",
      "command": "foundryToolboxAuth.getAccessToken"
    }
  ],
  "servers": {
    "toolbox-extension-auth": {
      "type": "http",
      "url": "https://<account>.services.ai.azure.com/api/projects/<project>/toolboxes/<toolbox>/mcp?api-version=v1",
      "headers": {
        "Authorization": "Bearer ${input:toolboxExtensionToken}"
      }
    }
  }
}
```

Run **MCP: List Servers** and start `toolbox-extension-auth`. VS Code reuses
its Microsoft authentication session; no Azure CLI token or manual token paste
is needed. If the access token expires while the server is running, restart
this MCP server so the command obtains a refreshed token.

## Common errors

| Error | Fix |
|---|---|
| `401` | Sign in again and request the `https://ai.azure.com/.default` scope. |
| `403` | Assign **Foundry User** on the Foundry project. |
| Token expired | Get a new token and restart the manual-token server. |
| `State does not match` | Restart the MCP server and complete browser sign-in again. |
| APIM metadata is `404` | Repeat the provision and deploy steps in `4-apim-toolbox/README.md`. |
| GitHub returns `CONSENT_REQUIRED` | Open the consent URL from the MCP output, authorize GitHub, and restart `foundry-toolbox`. |

## Current Microsoft documentation

- [Create and manage a toolbox](https://learn.microsoft.com/azure/foundry/agents/how-to/tools/toolbox)
- [Foundry authentication and authorization](https://learn.microsoft.com/azure/foundry/concepts/authentication-authorization-foundry)
- [Foundry role-based access control](https://learn.microsoft.com/azure/foundry/concepts/rbac-foundry)

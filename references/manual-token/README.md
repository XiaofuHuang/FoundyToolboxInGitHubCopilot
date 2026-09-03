# Connect clients with a manually acquired token

[English](README.md) | [简体中文](README.zh-CN.md)

This reference connects VS Code or GitHub Copilot CLI directly to a published
Microsoft Foundry Toolbox by manually obtaining a Microsoft Entra access token.
Use it for temporary testing when automatic sign-in is not required.

The token normally expires in about one hour. These configurations do not
refresh it automatically.

## Prerequisites

You need:

- Azure CLI signed in to the correct tenant
- A published Toolbox MCP endpoint
- The **Foundry User** role on the Foundry project

## Get a token

```powershell
az login --tenant '<tenant-id>'

$token = az account get-access-token `
  --scope https://ai.azure.com/.default `
  --query accessToken `
  --output tsv
```

Do not print, save, commit, or share the token.

## VS Code

Copy `vscode-mcp.json.example` to `.vscode\mcp.json` in your workspace. Replace
`<FOUNDRY_TOOLBOX_MCP_URL>` with the published consumer endpoint.

Copy the token to the clipboard:

```powershell
Set-Clipboard $token
```

Then:

1. Run **MCP: List Servers**.
2. Start `foundry-toolbox-manual-token`.
3. Paste only the token, without the `Bearer` prefix.

When the token expires, obtain a new token and restart the MCP server.

## GitHub Copilot CLI

Copy `copilot-plugin\.mcp.json.example` to
`copilot-plugin\.mcp.json`, then replace `<FOUNDRY_TOOLBOX_MCP_URL>`.
The local `.mcp.json` is ignored by Git.

Pass the token through a temporary environment variable and start Copilot CLI
from this directory:

```powershell
$env:FOUNDRY_TOOLBOX_TOKEN = $token
copilot --plugin-dir .\copilot-plugin
```

Run `/mcp list` to confirm that `foundry-toolbox-manual-token` is running.
Exit Copilot CLI before the token expires, obtain a new token, and start it
again when necessary.

Clear both token variables when finished:

```powershell
$token = $null
$env:FOUNDRY_TOOLBOX_TOKEN = $null
```

## OAuth-connected Toolbox tools

If the Toolbox contains a per-user OAuth connection, the first tool discovery
can return `-32006` with `CONSENT_REQUIRED`. Open the consent URL from the MCP
output, authorize the service, and restart the client. The
[`1-apim-toolbox`](../../1-apim-toolbox/) sample provides a better cross-client
consent experience by translating this response into MCP URL elicitation.

## Common errors

| Error | Resolution |
|---|---|
| `401` | Obtain a new `https://ai.azure.com/.default` token and restart the client. |
| `403` | Assign **Foundry User** on the Foundry project. |
| Copilot CLI cannot find the server | Confirm `copilot-plugin\.mcp.json` exists and start with `copilot --plugin-dir .\copilot-plugin`. |

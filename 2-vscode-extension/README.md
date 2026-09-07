# Connect VS Code with the authentication extension

[English](README.md) | [简体中文](README.zh-CN.md)

This sample connects VS Code directly to a Microsoft Foundry Toolbox without
APIM. A command input:

1. Reuses **Azure: Sign In** to obtain a `https://ai.azure.com/.default` token.
2. Receives the Toolbox endpoint through `args.toolboxUrl`.
3. Calls `tools/list` before returning the token to VS Code.
4. Opens Foundry's GitHub consent URL when authorization is required.

VS Code then uses its standard HTTP MCP transport with the returned bearer
token.

## Prerequisites

You need:

- VS Code 1.136 or later
- [Azure Resources](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-azureresourcegroups)
- Node.js and npm to package the extension
- A published Foundry Toolbox MCP endpoint
- The **Foundry User** role on the Foundry project

## 1. Package and install the extension

Run these commands from the `2-vscode-extension` directory:

```powershell
npm ci
npm run package
code --install-extension .\foundry-toolbox-auth-0.0.5.vsix --force
```

Reload VS Code and install Azure Resources if it is not already installed.

## Debug the extension with F5

As an alternative to packaging and installing a VSIX, open `2-vscode-extension`
itself as the VS Code workspace folder, then run `npm ci` in its terminal.
Install **Azure Resources** in the VS Code instance used for debugging.

Set breakpoints in `extension.js` or `toolboxClient.js`, then press **F5** and
select **Run Foundry Toolbox Extension** if prompted. The pre-launch task runs
the type check and bundles the extension with source maps, then opens an
**Extension Development Host** window with this folder and the development
extension loaded.

In the development window, run **Foundry Toolbox: Sign In** to activate the
extension. To debug the Toolbox preflight, configure
`foundryToolboxAuth.toolboxUrl` using `settings.json.example`. Alternatively,
configure and start the MCP server as described below. Inspect variables and
the **Debug Console** in the original window. Restart debugging after source
changes to rebuild and load the updated extension.

### Authentication diagnostic logs

In the window running the extension, open **View > Output** and select
**Foundry Toolbox Authentication**. Reproduce the failure with **Foundry
Toolbox: Sign In** or by clearing the saved MCP token input and restarting
the MCP server.

Each command invocation has a numbered prefix. Logs distinguish Azure token
acquisition from Toolbox preflight, report the endpoint without credentials
or query parameters, HTTP status and timing, and include error stacks with
nested `cause`/aggregate error codes such as `ENOTFOUND` or
`UNABLE_TO_VERIFY_LEAF_SIGNATURE`. Tokens, request headers, response bodies,
and consent URLs are not logged. Review logs for environment-specific details
before sharing them.

## 2. Configure `mcp.json`

Copy `samples\vscode\mcp.json.example` to `.vscode\mcp.json` in your workspace.
Replace both `<FOUNDRY_TOOLBOX_MCP_URL>` values with the same published
consumer endpoint:

```text
https://<account>.services.ai.azure.com/api/projects/<project>/toolboxes/<toolbox>/mcp?api-version=v1
```

The important part is the command input:

```jsonc
{
  "inputs": [
    {
      "id": "toolboxExtensionTokenV2",
      "type": "command",
      "command": "foundryToolboxAuth.getAccessToken",
      "args": {
        "toolboxUrl": "<FOUNDRY_TOOLBOX_MCP_URL>"
      }
    }
  ],
  "servers": {
    "toolbox-extension-auth": {
      "type": "http",
      "url": "<FOUNDRY_TOOLBOX_MCP_URL>",
      "headers": {
        "Authorization": "Bearer ${input:toolboxExtensionTokenV2}"
      }
    }
  }
}
```

`foundryToolboxAuth.getAccessToken` accepts either the object above or a direct
URL string. If no endpoint argument is provided, it only returns the token
unless `foundryToolboxAuth.toolboxUrl` is set as a fallback in VS Code settings.

## 3. Start the MCP server

1. Run **MCP: List Servers**.
2. Start `toolbox-extension-auth`.
3. Complete Microsoft sign-in if prompted.

Before returning the token, the command calls `tools/list`. A successful
preflight allows the normal MCP startup to continue.

VS Code securely saves MCP input values. When the Azure token expires, open
`.vscode\mcp.json`, select **Clear** beside `toolboxExtensionTokenV2`, and then
restart `toolbox-extension-auth`. Clearing the saved input makes VS Code invoke
the command again for a refreshed token.

## 4. Authorize GitHub

If preflight receives nested `CONSENT_REQUIRED`, VS Code displays the exact
Foundry URL with an **Open GitHub Consent** action.

1. Select **Open GitHub Consent**.
2. Complete GitHub authorization in the browser.
3. Clear the saved `toolboxExtensionTokenV2` input in `.vscode\mcp.json`.
4. Restart `toolbox-extension-auth`.
5. If needed, run **MCP: Reset Cached Tools**.
6. Confirm that Microsoft Learn and GitHub tools are available.

## Optional manual preflight

To run the same preflight from the Command Palette, set
`foundryToolboxAuth.toolboxUrl` in `.vscode\settings.json` using
`settings.json.example`, then run **Foundry Toolbox: Sign In**.

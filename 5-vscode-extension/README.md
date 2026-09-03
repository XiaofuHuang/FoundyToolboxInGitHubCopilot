# Foundry Toolbox Authentication extension

This local VS Code extension depends on **Azure Resources**
(`ms-azuretools.vscode-azureresourcegroups`). It reuses the account from
**Azure: Sign In** and returns a `https://ai.azure.com/.default` access token
to an MCP command input.

## Setup

1. Install Azure Resources and run **Azure: Sign In**.
2. Optionally set `foundryToolboxAuth.tenantId` in `.vscode\settings.json`
   when the account has access to multiple tenants.
3. Package and install this extension:

   ```powershell
   npm ci
   npm run package
   code --install-extension .\foundry-toolbox-auth-0.0.2.vsix --force
   ```

4. Reload VS Code and run **Foundry Toolbox: Sign In**.
5. Use the `foundryToolboxAuth.getAccessToken` command input shown in the main
   [connection guide](https://github.com/XiaofuHuang/FoundyToolboxInGitHubCopilot/blob/main/README.md).

No separate Entra app registration or client ID is needed. Azure Resources and
VS Code's Microsoft authentication provider manage the login session.

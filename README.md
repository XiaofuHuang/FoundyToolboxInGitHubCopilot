# Microsoft Foundry Toolbox connection samples

[English](README.md) | [简体中文](README.zh-CN.md)

This repository shows practical ways to connect VS Code and GitHub Copilot CLI
to a Microsoft Foundry Toolbox. Start with one of the numbered samples. Use the
reference guides only for lower-level testing or temporary token-based access.

## Choose an approach

| Requirement | Recommended approach |
|---|---|
| VS Code and GitHub Copilot CLI with browser sign-in | [APIM OAuth gateway](1-apim-toolbox/) |
| VS Code only, using the Azure Resources sign-in | [VS Code authentication extension](2-vscode-extension/) |
| APIM subscription key for clients, dedicated Entra application for the backend | [API-key gateway with application authentication](4-apim-entra-app/) |
| Endpoint diagnostics or automation | [Direct Azure CLI and REST calls](references/direct-toolbox/) |
| Short-lived manual client test | [Manual token reference](references/manual-token/) |

## Samples

### 1. APIM OAuth gateway

[`1-apim-toolbox/`](1-apim-toolbox/) is the recommended cross-client sample.
It deploys:

- A Microsoft Foundry project and Toolbox with Microsoft Learn and GitHub MCP
- An OAuth-protected Azure API Management gateway
- Browser-based Microsoft sign-in for VS Code and GitHub Copilot CLI
- A custom GitHub OAuth App connection with per-user consent
- MCP URL elicitation so both clients can display the GitHub authorization URL

Use this sample when you need automatic token refresh and the same Toolbox
experience in VS Code and GitHub Copilot CLI.

### 2. VS Code authentication extension

[`2-vscode-extension/`](2-vscode-extension/) contains a local VS Code extension
that connects directly to a published Toolbox. Its MCP command input returns an
Azure token and preflights `tools/list` so VS Code can open Foundry-provided
GitHub authorization URLs.

Use this sample when only VS Code is required and you do not want to deploy an
APIM gateway or register a separate Entra client application.

### 4. API-key gateway with an Entra application

[`4-apim-entra-app/`](4-apim-entra-app/) is a standalone Microsoft Learn-only
sample. Clients send an API-scoped APIM subscription key; APIM obtains a Foundry
token using a dedicated Entra application's `client_credentials` grant and a
short-lived secret stored in an APIM secret named value. APIM has no managed
identity, performs no OBO, and grants no per-user backend access.

It provisions separate billable APIM Basic v2 and Foundry resources. Choose this
sample when a shared application identity is appropriate and you can operate
the documented secret-rotation lifecycle.

## Reference methods

| Reference | Use case |
|---|---|
| [Direct Azure CLI and REST calls](references/direct-toolbox/) | Test or automate a Toolbox endpoint without an MCP client. |
| [Manually pass a token to VS Code or Copilot CLI](references/manual-token/) | Temporarily connect a client with a short-lived token. |

## Microsoft documentation

- [Create and manage a Toolbox](https://learn.microsoft.com/azure/foundry/agents/how-to/tools/toolbox)
- [Foundry authentication and authorization](https://learn.microsoft.com/azure/foundry/concepts/authentication-authorization-foundry)
- [Foundry role-based access control](https://learn.microsoft.com/azure/foundry/concepts/rbac-foundry)

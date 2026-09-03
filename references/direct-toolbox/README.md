# Call a Foundry Toolbox directly

[English](README.md) | [简体中文](README.zh-CN.md)

This reference shows how to call a published Microsoft Foundry Toolbox
directly with Azure CLI or a REST request. Use it for diagnostics and
automation when a VS Code or GitHub Copilot client is not required.

## Prerequisites

You need:

- Azure CLI signed in to the correct tenant
- A published Toolbox MCP endpoint
- The **Foundry User** role on the Foundry project

Set the consumer endpoint:

```powershell
$toolboxUrl = 'https://<account>.services.ai.azure.com/api/projects/<project>/toolboxes/<toolbox>/mcp?api-version=v1'
```

## Azure CLI

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

`az rest` obtains the Microsoft Entra token. A successful response contains
`result.tools`.

## REST with a bearer token

Get a token from the Azure CLI session:

```powershell
$token = az account get-access-token `
  --scope https://ai.azure.com/.default `
  --query accessToken `
  --output tsv
```

Call the Toolbox:

```powershell
$body = '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'

curl.exe -sS -X POST $toolboxUrl `
  -H "Authorization: Bearer $token" `
  -H 'Content-Type: application/json' `
  -H 'MCP-Protocol-Version=2025-11-25' `
  --data $body
```

Clear the shell variable when finished:

```powershell
$token = $null
```

Access tokens normally expire in about one hour. Do not print, save, commit,
or share them.

## Common errors

| Error | Resolution |
|---|---|
| `401` | Sign in again and request the `https://ai.azure.com/.default` scope. |
| `403` | Assign **Foundry User** on the Foundry project. |
| `-32006` with `CONSENT_REQUIRED` | Open the consent URL, authorize the connected service, and repeat the request. |
| Token expired | Obtain a new token and repeat the request. |

## Microsoft documentation

- [Create and manage a Toolbox](https://learn.microsoft.com/azure/foundry/agents/how-to/tools/toolbox)
- [Foundry authentication and authorization](https://learn.microsoft.com/azure/foundry/concepts/authentication-authorization-foundry)

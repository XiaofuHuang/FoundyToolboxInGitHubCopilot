# 直接调用 Foundry Toolbox

[English](README.md) | **简体中文**

本参考指南介绍如何使用 Azure CLI 或 REST 请求直接调用已发布的 Microsoft
Foundry Toolbox。无需 VS Code 或 GitHub Copilot 客户端时，可使用此方式
进行诊断和自动化。

## 先决条件

你需要：

- Azure CLI 已登录到正确的租户
- 一个已发布的 Toolbox MCP 终结点
- Foundry 项目的 **Foundry User** 角色

设置使用者终结点：

```powershell
$toolboxUrl = 'https://<account>.services.ai.azure.com/api/projects/<project>/toolboxes/<toolbox>/mcp?api-version=v1'
```

## Azure CLI

登录：

```powershell
az login --tenant '<tenant-id>'
```

调用 `tools/list`：

```powershell
$body = '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'

az rest `
  --method post `
  --resource https://ai.azure.com `
  --url $toolboxUrl `
  --headers 'Content-Type=application/json' 'MCP-Protocol-Version=2025-11-25' `
  --body $body
```

`az rest` 会获取 Microsoft Entra 令牌。成功响应中会包含 `result.tools`。

## 使用持有者令牌发送 REST 请求

从 Azure CLI 会话获取令牌：

```powershell
$token = az account get-access-token `
  --scope https://ai.azure.com/.default `
  --query accessToken `
  --output tsv
```

调用 Toolbox：

```powershell
$body = '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'

curl.exe -sS -X POST $toolboxUrl `
  -H "Authorization: Bearer $token" `
  -H 'Content-Type: application/json' `
  -H 'MCP-Protocol-Version=2025-11-25' `
  --data $body
```

完成后清除 shell 变量：

```powershell
$token = $null
```

访问令牌通常会在约一小时后过期。请勿打印、保存、提交或分享令牌。

## 常见错误

| 错误 | 解决方法 |
|---|---|
| `401` | 重新登录并请求 `https://ai.azure.com/.default` 范围。 |
| `403` | 在 Foundry 项目中分配 **Foundry User** 角色。 |
| `-32006` 和 `CONSENT_REQUIRED` | 打开授权 URL，授权连接的服务，然后重新发送请求。 |
| 令牌已过期 | 获取新令牌，然后重新发送请求。 |

## Microsoft 文档

- [创建和管理 Toolbox](https://learn.microsoft.com/azure/foundry/agents/how-to/tools/toolbox)
- [Foundry 身份验证和授权](https://learn.microsoft.com/azure/foundry/concepts/authentication-authorization-foundry)

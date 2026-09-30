# Microsoft Foundry Toolbox 连接示例

[English](README.md) | **简体中文**

本仓库提供将 VS Code 和 GitHub Copilot CLI 连接到 Microsoft Foundry
Toolbox 的实用方式。请从带编号的示例开始；仅在进行底层测试或临时令牌访问时
使用参考指南。

## 选择方式

| 需求 | 推荐方式 |
|---|---|
| VS Code 和 GitHub Copilot CLI 使用浏览器登录 | [APIM OAuth 网关](1-apim-toolbox/README.zh-CN.md) |
| 仅使用 VS Code，并复用 Azure Resources 登录 | [VS Code 身份验证扩展](2-vscode-extension/README.zh-CN.md) |
| 客户端使用 APIM 订阅密钥，后端使用专用 Entra 应用 | [使用应用身份验证的 API-key 网关](4-apim-entra-app/README.zh-CN.md) |
| 终结点诊断或自动化 | [直接使用 Azure CLI 和 REST 调用](references/direct-toolbox/README.zh-CN.md) |
| 使用短期令牌手动测试客户端 | [手动令牌参考指南](references/manual-token/README.zh-CN.md) |

## 示例

### 1. APIM OAuth 网关

[`1-apim-toolbox/`](1-apim-toolbox/) 是推荐的跨客户端示例。它会部署：

- 一个包含 Microsoft Learn 和 GitHub MCP 的 Microsoft Foundry 项目及 Toolbox
- 一个受 OAuth 保护的 Azure API Management 网关
- 适用于 VS Code 和 GitHub Copilot CLI 的 Microsoft 浏览器登录
- 一个支持按用户授权的自定义 GitHub OAuth App 连接
- MCP URL elicitation，让两种客户端都能显示 GitHub 授权 URL

如果需要自动刷新令牌，并希望 VS Code 和 GitHub Copilot CLI 使用相同的
Toolbox 体验，请选择此示例。

### 2. VS Code 身份验证扩展

[`2-vscode-extension/`](2-vscode-extension/) 包含一个本地 VS Code 扩展，
用于直接连接已发布的 Toolbox。它的 MCP 命令输入会返回 Azure 令牌并预检
`tools/list`，让 VS Code 能够打开 Foundry 提供的 GitHub 授权 URL。

如果只需要 VS Code，并且不希望部署 APIM 网关或单独注册 Entra 客户端应用，
请选择此示例。

### 4. 使用 Entra 应用的 API-key 网关

[`4-apim-entra-app/`](4-apim-entra-app/README.zh-CN.md) 是仅包含 Microsoft Learn
的独立示例。客户端发送 API 范围的 APIM 订阅密钥；APIM 使用专用 Entra 应用的
`client_credentials` 授权和保存在 APIM secret named value 中的短期机密获取
Foundry 令牌。APIM 不使用托管标识，不执行 OBO，也不提供按用户区分的后端访问权限。

此示例会部署独立的计费 APIM Basic v2 和 Foundry 资源。如果共享应用身份符合需求，
且能够维护文档中说明的机密轮换生命周期，请选择此示例。

## 参考方式

| 参考指南 | 使用场景 |
|---|---|
| [直接使用 Azure CLI 和 REST 调用](references/direct-toolbox/README.zh-CN.md) | 不使用 MCP 客户端，直接测试 Toolbox 终结点或进行自动化。 |
| [向 VS Code 或 Copilot CLI 手动传递令牌](references/manual-token/README.zh-CN.md) | 使用短期令牌临时连接客户端。 |

## Microsoft 文档

- [创建和管理 Toolbox](https://learn.microsoft.com/azure/foundry/agents/how-to/tools/toolbox)
- [Foundry 身份验证和授权](https://learn.microsoft.com/azure/foundry/concepts/authentication-authorization-foundry)
- [Foundry 基于角色的访问控制](https://learn.microsoft.com/azure/foundry/concepts/rbac-foundry)

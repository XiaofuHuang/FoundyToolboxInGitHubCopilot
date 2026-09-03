# 使用手动获取的令牌连接客户端

[English](README.md) | **简体中文**

本参考指南通过手动获取 Microsoft Entra 访问令牌，将 VS Code 或 GitHub
Copilot CLI 直接连接到已发布的 Microsoft Foundry Toolbox。无需自动登录
时，可使用此方式进行临时测试。

令牌通常会在约一小时后过期。以下配置不会自动刷新令牌。

## 先决条件

你需要：

- Azure CLI 已登录到正确的租户
- 一个已发布的 Toolbox MCP 终结点
- Foundry 项目的 **Foundry User** 角色

## 获取令牌

```powershell
az login --tenant '<tenant-id>'

$token = az account get-access-token `
  --scope https://ai.azure.com/.default `
  --query accessToken `
  --output tsv
```

请勿打印、保存、提交或分享令牌。

## VS Code

将 `vscode-mcp.json.example` 复制到工作区的 `.vscode\mcp.json`，然后使用
已发布的使用者终结点替换 `<FOUNDRY_TOOLBOX_MCP_URL>`。

将令牌复制到剪贴板：

```powershell
Set-Clipboard $token
```

然后：

1. 运行 **MCP: List Servers**。
2. 启动 `foundry-toolbox-manual-token`。
3. 只粘贴令牌，不要添加 `Bearer` 前缀。

令牌过期后，请获取新令牌并重启 MCP 服务器。

## GitHub Copilot CLI

将 `copilot-plugin\.mcp.json.example` 复制为
`copilot-plugin\.mcp.json`，然后替换 `<FOUNDRY_TOOLBOX_MCP_URL>`。
本地 `.mcp.json` 已被 Git 忽略。

通过临时环境变量传递令牌，并在此目录中启动 Copilot CLI：

```powershell
$env:FOUNDRY_TOOLBOX_TOKEN = $token
copilot --plugin-dir .\copilot-plugin
```

运行 `/mcp list`，确认 `foundry-toolbox-manual-token` 正在运行。令牌过期前
退出 Copilot CLI；需要继续使用时，请获取新令牌并重新启动。

完成后清除两个令牌变量：

```powershell
$token = $null
$env:FOUNDRY_TOOLBOX_TOKEN = $null
```

## 包含 OAuth 连接的 Toolbox 工具

如果 Toolbox 包含按用户授权的 OAuth 连接，第一次发现工具时可能会返回
带有 `CONSENT_REQUIRED` 的 `-32006`。打开 MCP 输出中的授权 URL，授权服务，
然后重启客户端。[`1-apim-toolbox`](../../1-apim-toolbox/) 示例会将该响应
转换为 MCP URL elicitation，因此能够提供更好的跨客户端授权体验。

## 常见错误

| 错误 | 解决方法 |
|---|---|
| `401` | 获取新的 `https://ai.azure.com/.default` 令牌，然后重启客户端。 |
| `403` | 在 Foundry 项目中分配 **Foundry User** 角色。 |
| Copilot CLI 找不到服务器 | 确认 `copilot-plugin\.mcp.json` 存在，并使用 `copilot --plugin-dir .\copilot-plugin` 启动。 |

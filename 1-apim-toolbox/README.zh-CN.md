# 将 GitHub Copilot 连接到 Microsoft Foundry Toolbox

[English](README.md) | **简体中文**

此示例会部署一个 Microsoft Foundry 项目和 Toolbox，然后通过受 OAuth
保护的 Azure API Management（APIM）终结点公开该 Toolbox。Toolbox 中会
同时配置 Microsoft Learn 和 GitHub MCP 服务器工具。

```text
GitHub Copilot CLI 或 VS Code
  -> APIM（用户登录和令牌验证）
  -> Microsoft Foundry Toolbox（用户身份和 Foundry RBAC）
  -> Microsoft Learn MCP 或 GitHub MCP
```

> [!IMPORTANT]
> 此部署会创建一个 APIM Basic v2 实例，因此会产生 Azure 费用。

## 先决条件

请安装：

- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- [Azure Developer CLI（`azd`）](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- 如果需要在终端中使用 Toolbox，请安装
  [GitHub Copilot CLI](https://docs.github.com/copilot/how-tos/set-up/install-copilot-cli)

你还需要：

- 一个 Azure 订阅
- 在该订阅中创建资源组和资源的权限
- 创建应用、服务主体、联合凭据以及授予租户级委托权限所需的
  Microsoft Entra 权限
- 每个 Toolbox 用户都需要拥有已部署项目的 **Foundry User** 角色
- 创建 GitHub OAuth App 的权限
- 每个授权 GitHub 连接的用户都需要一个 GitHub 账户

如果你无法授予所需的 Entra 权限，请让租户管理员执行部署。

## 1. 安装 Foundry 扩展

在 `1-apim-toolbox` 目录中运行以下命令：

```powershell
azd extension install azure.ai.projects
azd extension install azure.ai.connections
azd extension install azure.ai.toolboxes
```

## 2. 登录并配置环境

替换所有尖括号中的值：

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

`APIM_NAME` 必须全局唯一，因为它会成为公共网关主机名的一部分。

## 3. 预配 Azure 资源

```powershell
azd provision --no-prompt
```

预配过程会创建：

- 用于 Foundry Toolbox、受 OAuth 保护的 APIM 网关

## 4. 部署 Toolbox

创建一个 [GitHub OAuth App](https://github.com/settings/applications/new)。
GitHub 要求在创建应用时提供授权回调 URL，因此先使用
`https://example.com/callback`。复制客户端 ID，并生成客户端密码。

创建自定义 OAuth2 连接。使用掩码提示输入客户端密码，避免将其写入
README、`azure.yaml`、azd 环境或 shell 历史记录：

```powershell
$projectEndpoint = azd env get-value FOUNDRY_PROJECT_ENDPOINT
$githubClientId = Read-Host 'GitHub OAuth App client ID'
$githubClientSecretSecure = Read-Host 'GitHub OAuth App client secret' -AsSecureString
$githubClientSecretPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR(
  $githubClientSecretSecure
)
$githubClientSecret = [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
  $githubClientSecretPointer
)

try {
  azd ai connection create github-oauth `
    --kind remote-tool `
    --target https://api.githubcopilot.com/mcp `
    --auth-type oauth2 `
    --client-id $githubClientId `
    --client-secret $githubClientSecret `
    --authorization-url https://github.com/login/oauth/authorize `
    --token-url https://github.com/login/oauth/access_token `
    --refresh-url https://github.com/login/oauth/access_token `
    --scopes 'repo read:org read:user user:email read:packages write:packages read:project project gist notifications workflow codespace' `
    --project-endpoint $projectEndpoint
}
finally {
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($githubClientSecretPointer)
  $githubClientSecret = $null
  $githubClientSecretSecure = $null
}
```

Foundry 会为每个连接生成唯一的回调 URL。使用以下命令输出该 URL：

```powershell
$subscriptionId = azd env get-value AZURE_SUBSCRIPTION_ID
$resourceGroup = azd env get-value AZURE_FOUNDRY_RESOURCE_GROUP
$accountName = azd env get-value AZURE_AI_ACCOUNT_NAME
$projectName = azd env get-value AZURE_AI_PROJECT_NAME

$githubRedirectUrl = az rest `
  --method get `
  --url "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.CognitiveServices/accounts/$accountName/projects/$projectName/connections/github-oauth?api-version=2025-06-01" `
  --query properties.redirectUrl `
  --output tsv

$githubRedirectUrl
```

返回 GitHub OAuth App 设置，将临时回调 URL 替换为这个准确值。回调 URL
匹配之前，该连接无法完成用户授权。

```powershell
azd deploy --no-prompt

$toolboxVersion = (
  azd ai toolbox versions list tools `
    --project-endpoint $projectEndpoint `
    --output json |
    ConvertFrom-Json
).versions |
  Sort-Object { [int]$_.version } -Descending |
  Select-Object -First 1 -ExpandProperty version

azd ai toolbox publish tools $toolboxVersion `
  --project-endpoint $projectEndpoint `
  --no-prompt
```

`azd deploy` 会创建不可变的 Toolbox 版本，但不会自动将后续版本设为默认版本。
必须发布新版本，使用者终结点和 APIM 才会提供新的 `github-oauth` 连接。

部署完成后，输出并复制两种客户端都需要的值：

```powershell
azd env get-value APIM_TOOLBOX_MCP_URL
azd env get-value MCP_COPILOT_CLIENT_ID
```

## 5. 连接客户端

### Visual Studio Code

将 `samples\vscode\mcp.json.example` 复制到工作区的
`.vscode/mcp.json`，然后使用部署后输出的值替换两个占位符：

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

打开 MCP 面板，启动 `foundry-toolbox`，然后在浏览器中完成登录。

### GitHub Copilot CLI

将 `samples\copilot-plugin\.mcp.json.example` 复制为
`samples\copilot-plugin\.mcp.json`。仓库已包含所需的
`samples\copilot-plugin\plugin.json`。

编辑 `samples\copilot-plugin\.mcp.json`，使用部署后输出的值替换两个占位符：

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

使用插件启动 Copilot CLI：

```powershell
$env:COPILOT_ENTRA_DISABLE_ONEAUTH = '1'
copilot --plugin-dir .\samples\copilot-plugin
```

在 Copilot CLI 中验证服务器身份：

```text
/mcp auth foundry-toolbox
```

在浏览器中完成登录。随后即可使用 `foundry-toolbox` 工具；每次调用工具前，
Copilot 都会请求批准。

### 一次性授权 GitHub

GitHub 尚未获得授权时，Foundry 会在工具发现期间返回
`CONSENT_REQUIRED`。APIM 会将该响应转换为 MCP URL elicitation：

1. 启动 `foundry-toolbox`。
2. 打开 GitHub 授权提示：
   - 在 VS Code 中，通过 **Authorization Required** 卡片批准
     `consent.azure-apim.net` 主机。
   - 在 Copilot CLI 中，打开 **foundry-toolbox wants you to visit**
     下方显示的 URL。
3. 授权 GitHub。
4. 重启 `foundry-toolbox`，加载 Microsoft Learn 和 GitHub 工具。

Foundry 会使用你的 OAuth App 存储并刷新每个用户的 GitHub 令牌。APIM
仍然是两种客户端中唯一配置的 MCP 服务器；GitHub MCP 不会部署到 APIM。

## 故障排除

| 问题 | 解决方法 |
|---|---|
| 创建 Microsoft Graph 资源时 `azd provision` 失败 | 使用能够创建 Entra 应用并授予委托权限的账户执行部署。 |
| 创建 APIM 时提示名称不可用 | 使用 `azd env set APIM_NAME '<new-name>'` 设置另一个全局唯一名称，然后再次运行 `azd provision`。 |
| 登录成功，但 Toolbox 调用返回 `403` | 为登录用户分配已部署 Foundry 项目的 **Foundry User** 角色。 |
| 需要 GitHub 授权 | 打开 VS Code 授权卡片或 Copilot CLI 授权提示中的 URL，授权 GitHub，然后重启 MCP 服务器。 |
| GitHub 报告回调 URL 或重定向 URL 不匹配 | 读取 `github-oauth` 连接的 `properties.redirectUrl`，并将其准确设置为 GitHub OAuth App 的授权回调 URL。 |
| GitHub 拒绝 OAuth 客户端或客户端密码 | 检查客户端 ID，生成新的客户端密码，然后使用 `--force` 重新创建 `github-oauth`。 |
| GitHub 返回 `HTTP_401`，但没有授权 URL | 删除并重新创建自定义 GitHub OAuth 连接。连接器令牌被撤销后，无法将其转换为新的授权 URL。 |
| Copilot CLI 无法发现服务器 | 在 `1-apim-toolbox` 目录中使用 `copilot --plugin-dir .\samples\copilot-plugin` 启动，并确认 `samples\copilot-plugin\.mcp.json` 存在。 |

## 清理

删除 Azure 资源之前，先删除租户级 Entra 对象：

```powershell
.\scripts\cleanup-entra.ps1
azd down
```

如果不再需要 GitHub OAuth App，请手动删除它。

## 安全注意事项

为简化示例，此处使用同一个 Entra 应用同时充当公共客户端和机密的代表用户
（OBO）客户端。因此，公共流程可以直接请求委托的 Foundry 范围。如果 APIM
必须作为强制治理边界，请分别使用公共客户端应用和资源应用。

GitHub OAuth App 会请求广泛权限，以便使用除删除仓库以外的全部 GitHub MCP
功能。在生产环境中，请将范围列表缩减为用户实际需要的功能。切勿将 GitHub
客户端密码存储在 `azure.yaml` 中或提交到源代码管理。

# 通过 APIM API key 和 managed identity 使用 Foundry Toolbox

[English](README.md) | **简体中文**

这是与 `1-apim-toolbox` 分开的独立部署。客户端提供 **APIM subscription key**，
APIM 使用自己的 system-assigned managed identity 访问 Foundry。
不透传用户 token，不执行 OAuth discovery 或 OBO，也不要求 MCP 客户端
进行交互式 Microsoft 登录。

```text
VS Code 或其他 MCP 客户端
  -> APIM：Ocp-Apim-Subscription-Key
  -> Foundry Toolbox：代表 APIM managed identity 的 bearer token
  -> Microsoft Learn MCP：公共工具，无需下游身份验证
```

## 身份和权限

APIM 要求访问 `foundry-toolbox` API 的请求携带 subscription key。
模板创建名为 `toolbox-client` 的 active subscription，作用域仅限该 API；
Azure 自动生成 primary 和 secondary keys，Bicep 不输出这些 key。

Key 验证通过后，API policy 删除该 key 和客户端提供的 `Authorization` header。
`authentication-managed-identity` 获取面向 `https://ai.azure.com` 的 token，
并设置后端 bearer header。APIM 会缓存 managed identity token，直到其过期。
请求被路由到固定的已发布 Toolbox endpoint，不转发客户端的 query parameters。

Inbound policy 显式转发 JSON-RPC 请求并返回 Toolbox 响应，而不是使用 APIM
自动生成的 MCP catalog 提供工具列表。与 OAuth 示例一样，这个请求/响应实现
会缓冲后端响应，不是通用的长连接 SSE 转发器。

Managed identity 只在 **project scope** 获得 **Foundry User**，而不是在整个
订阅上获得权限。客户端不需要自己的 Foundry 角色。所有 key 持有者共用同一个
后端身份及其权限，Foundry 不会收到各个客户端自己的 Entra 用户身份。

本示例**仅包含 Microsoft Learn**。原来的 per-user GitHub OAuth connection
不能通过这种模式保留用户身份；共享凭据或下游服务身份需要另外设计 connection。

## 先决条件和费用

- Azure CLI 和 Azure Developer CLI（`azd`）。
- azd 的 `azure.ai.projects` 和 `azure.ai.toolboxes` 扩展。
- 创建资源和角色分配的 Azure 权限，例如 Owner，或 Contributor 加
  Role Based Access Control Administrator。
- 支持 HTTP MCP 和 password input variables 的新版 VS Code。

本方案的网关不需要自定义 Entra client application、federated credential、
tenant-wide consent 或 GitHub OAuth App。

> [!IMPORTANT]
> 此部署会新建一个 **APIM BasicV2** 实例，并持续产生 Azure 费用。
> 请使用新的 environment 名称、resource group 和 APIM 名称。
> 没有配置自动清理，也不会修改原有 OAuth 示例的部署。

## 1. 配置新环境

在 `3-apim-api-key` 目录中执行命令。需要时安装缺少的 Foundry 扩展：

```powershell
azd extension install azure.ai.projects
azd extension install azure.ai.toolboxes
```

登录预期 tenant 和订阅：

```powershell
az login --tenant '<tenant-id>'
az account set --subscription '<subscription-id>'
azd auth login --check-status
```

如果 azd 使用内置身份验证，运行
`azd auth login --tenant-id '<tenant-id>'`。如果它将身份验证委托给 Azure CLI，
使用 `az login` 即可。

```powershell
azd env new '<new-environment-name>' `
  --subscription '<subscription-id>' `
  --location eastus2

azd env set AZURE_RESOURCE_GROUP '<new-resource-group>'
azd env set APIM_NAME '<new-globally-unique-apim-name>'
azd env set APIM_PUBLISHER_EMAIL '<your-email-address>'
azd env set APIM_PUBLISHER_NAME '<your-organization-name>'
```

## 2. 预配和部署

```powershell
azd provision --no-prompt
azd deploy --no-prompt
```

预配会创建新的 Foundry account/project、APIM managed identity、
项目级角色分配、MCP API、policy，以及仅针对该 API 的 subscription。
部署会创建包含 Microsoft Learn 的 `tools` Toolbox。

发布客户端应使用的版本：

```powershell
$projectEndpoint = azd env get-value FOUNDRY_PROJECT_ENDPOINT
$versions = azd ai toolbox versions list tools `
  --project-endpoint $projectEndpoint --output json | ConvertFrom-Json
$version = $versions.versions |
  Sort-Object { [int]$_.version } -Descending |
  Select-Object -First 1 -ExpandProperty version
if (-not $version) { throw 'No Toolbox version was returned.' }
azd ai toolbox publish tools $version `
  --project-endpoint $projectEndpoint --no-prompt

azd env get-value APIM_TOOLBOX_MCP_URL
```

新的 managed identity 和 RBAC 分配可能需要一定时间生效。后端暂时出现授权错误时，
不应关闭 key 验证，也不应改用部署者的用户 token。

## 3. 连接 VS Code

在 Azure Portal 中打开新建的 APIM，选择 **Subscriptions**，再打开
**Foundry Toolbox MCP client**。准备好向 VS Code 的 password input 输入时，
再显示并复制 key。它是 APIM key，不是 Foundry API key。

将[示例配置](samples/vscode/mcp.json.example)复制到实际打开的工作区中的
`.vscode\mcp.json`。已有 `inputs` 和 `servers` 时应合并，避免覆盖。
将 `<APIM_TOOLBOX_MCP_URL>` 替换为部署输出。

核心认证配置如下：

```json
{
  "inputs": [
    {
      "id": "foundryToolboxApimKey",
      "type": "promptString",
      "description": "APIM subscription key for the Foundry Toolbox",
      "password": true
    }
  ],
  "servers": {
    "foundry-toolbox-api-key": {
      "type": "http",
      "url": "<APIM_TOOLBOX_MCP_URL>",
      "headers": {
        "Ocp-Apim-Subscription-Key": "${input:foundryToolboxApimKey}"
      }
    }
  }
}
```

通过 **MCP: List Servers** 启动 `foundry-toolbox-api-key`，在掩码提示中输入 key。
无需 `oauth.clientId`，也无需终端用户登录 Azure。
在 Copilot 的工具选择器中启用 Microsoft Learn 工具即可使用。

VS Code 会安全保存 input 值。轮换 key 后，请清除已保存的
`foundryToolboxApimKey` input，并重启 server 输入新 key。

## Key 管理与运行边界

- 不要将 key 提交到代码，或写入 `azure.yaml`、azd environment、聊天、
  命令历史或日志。通过 header 发送，不要放在 URL query string 中。
- Key 泄露意味着该 API 的共享服务访问权泄露。为不同使用者建立独立的
  API-scoped subscriptions，便于单独撤销权限，并在 APIM 中轮换 key。
- 能修改网关 policy 的人可以影响 managed identity 的使用。请限制管理面权限，
  并将 Foundry 角色保持在独立项目范围内。
- 缺少或错误的 key 由 APIM 拒绝。Foundry 授权失败时应检查 managed identity
  和它的 RBAC，而不是客户端个人的 Foundry 权限。
- 这是公共 endpoint。向预期使用者之外的人开放前，应增加适当的网络控制、
  quota、限流和监控。

## 清理

在本目录确认选中的 azd environment 和订阅，只有在不再需要此部署时才执行
`azd down`。它会删除本部署的 Azure 资源，包括 APIM 及其 system-assigned
identity；没有单独的 Entra client application 需要删除。

关闭 VS Code 或停止 MCP server 不会停止 APIM 计费。

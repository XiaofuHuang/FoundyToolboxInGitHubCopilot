# 使用 Entra 应用的 API-key 网关

[English](README.md) | **简体中文**

## 架构与信任边界

```text
VS Code 或其他 MCP HTTP 客户端
  -- API 范围的 APIM 订阅密钥 --> APIM Basic v2 (identity: None)
  -- APIM 获取应用令牌 --> Microsoft Entra 令牌终结点
       grant_type=client_credentials, scope=https://ai.azure.com/.default
  -- 应用 bearer token --> Microsoft Foundry 项目 / Toolbox
  --> Microsoft Learn MCP
```

两个凭据的持有者和用途不同：

| 边界 | 凭据 | 授权 |
|---|---|---|
| 客户端 -> APIM | `Ocp-Apim-Subscription-Key` 中的 APIM 订阅密钥 | 限定于 `foundry-toolbox` API 的活动订阅 |
| APIM -> Foundry | 专用 Entra 应用的 30 天客户端机密，用于换取应用令牌 | 仅在此新项目范围内向其服务主体授予 **Foundry User** (`53ca6127-db72-4b80-b1b0-d745d6d5456d`) |

APIM **没有托管标识**。不使用 OBO、用户身份透传、网关 OAuth scope、重定向 URI、
委托权限授权或 GitHub consent。单租户应用仅用于后端。Foundry 访问由 Azure 项目
RBAC 控制，而不是由应用公开的 scope 控制。Foundry 账户/项目可能拥有自己的平台
标识；APIM 不会使用它们进行后端调用。

APIM 在 API 策略执行前验证订阅密钥，然后删除密钥请求头/查询参数及客户端
`Authorization` 请求头。它在**每次请求**时获取新应用令牌（无令牌缓存），覆盖
`Authorization`，并转发到固定的 `tools` Toolbox 终结点。有效密钥搭配无效客户端
bearer 仍然可用；仅有 bearer 而没有密钥则不可用。

所有密钥持有者都以**同一个应用**访问，而不是作为不同的 Foundry 用户。
应分别保护和轮换前端密钥与后端应用机密。此示例仅公开 Microsoft Learn；
它不是按用户授权的网关，也不向客户端授予任意 Foundry 访问权限。

> [!IMPORTANT]
> 此独立示例会部署**另一个计费的 APIM Basic v2 实例**，以及独立的 Foundry
> 账户/项目/应用。请使用新环境和全局唯一的 APIM 名称，不要复用其他示例的资源。

### MCP 传输限制

原生 APIM `type: mcp` API 使用显式的 inbound `send-request` / `return-response`
返回**真实 Toolbox 响应**。在此集成中，普通 `forward-request` 返回了 APIM 自身的
空工具目录。此模式缓冲后端响应，请求超时为 120 秒，**不是通用的长期 SSE 中继**。
覆盖范围是短时 JSON/SSE 请求-响应调用和初始化通知。如果需要持久流、服务器主动
消息或长时间运行的工具，请重新评估网关设计。每次获取令牌会增加延迟，并依赖
Entra 可用性和限流。

## 前提条件

- Azure CLI、Azure Developer CLI (`azd`)、PowerShell 7 (`pwsh`)。
- Azure 订阅，以及支持 APIM Basic v2 和 Foundry 的区域（此示例使用 `eastus2`）。
- 创建 Azure 资源和项目角色分配的权限，例如目标订阅/资源组上的 Owner。
- 创建/管理应用、服务主体和应用密码的 Entra 权限。Azure Owner 本身**不授予**
  目录权限。
- 部署用户在新项目上具有 Foundry User 数据平面访问权限（或继承的角色分配），
  用于部署和发布 Toolbox。
- 仅可选的自动验证需要 Python 3.10+。

Azure CLI 和 azd 应使用**同一租户/账户**。凭据 hook 使用当前 Azure CLI 登录，
不会切换账户。不要在启用 shell transcription、HTTP/debug 日志或凭据采集跟踪时运行。

## 预配与发布

在 `4-apim-entra-app` 目录中使用 PowerShell 执行命令。替换尖括号中的值；
下面所有环境值都不是机密。

### 1. 准备工具和环境

检查 `azd extension list`，安装缺少的扩展：

```powershell
azd extension install microsoft.foundry
azd extension install azure.ai.projects
azd extension install azure.ai.toolboxes
```

Toolbox 扩展至少需要 `1.0.0-beta.5`。Graph Bicep 扩展版本固定在
`infra\bicepconfig.json`；APIM MCP 使用预览版管理 API。

```powershell
az login --tenant '<tenant-id>'
azd auth login

azd env new '<new-environment-name>' `
  --subscription '<subscription-id>' --location eastus2
azd env set AZURE_TENANT_ID '<tenant-id>'
azd env set AZURE_RESOURCE_GROUP '<new-resource-group-name>'
azd env set APIM_NAME '<new-globally-unique-apim-name>'
azd env set APIM_PUBLISHER_EMAIL '<your-email-address>'
azd env set APIM_PUBLISHER_NAME '<your-organization-name>'
```

### 2. 预配基础设施和后端凭据

```powershell
azd provision --no-prompt
```

Foundry 层创建账户/项目。Bicep 创建 `identity.type: None` 的 APIM、后端应用/
服务主体、项目范围 RBAC、API 范围订阅，以及初始值为 `UNCONFIGURED` 的 secret
named value。完成配置之前，策略以 HTTP 503 拒绝访问。

`scripts\configure-app-credential.ps1` 中必需的 `postprovision` hook 会：

1. 仅删除此 hook 所属的已过期密码，然后通过 Microsoft Graph `addPassword`
   创建有效期 30 天的应用密码。
2. 确认能获取 `https://ai.azure.com/.default` 的令牌。
3. 通过 ARM HTTPS 直接把机密写入 `foundry-app-client-secret`，设置 `secret: true`，
   并等待 named value 完成预配。
4. 保留**所有未过期凭据**（包括先前轮换的凭据），仅将
   `ENTRA_APP_SECRET_EXPIRES_AT` 保存到 azd。

配置过程中机密和令牌仅保留在进程内存中，不写入本地文件、azd 环境值、部署参数
或命令行参数。持久机密保存在 Entra 和 APIM secret named value 中。hook 隐藏
敏感 HTTP 详情，并在失败时退出；它不能替代下文对网关传播和项目 RBAC 的验证。

### 3. 部署并显式发布 Toolbox 版本

```powershell
azd deploy --no-prompt
if ($LASTEXITCODE -ne 0) { throw 'Toolbox deployment failed.' }
$projectEndpoint = azd env get-value FOUNDRY_PROJECT_ENDPOINT
if ($LASTEXITCODE -ne 0) { throw 'Cannot read the project endpoint.' }
$versionsJson = azd ai toolbox versions list tools `
  --project-endpoint $projectEndpoint --output json
if ($LASTEXITCODE -ne 0) { throw 'Cannot list Toolbox versions.' }
$toolboxVersion = ($versionsJson | ConvertFrom-Json).versions |
  Sort-Object { [int]$_.version } -Descending |
  Select-Object -First 1 -ExpandProperty version
if (-not $toolboxVersion) { throw 'No Toolbox version is available.' }
azd ai toolbox publish tools $toolboxVersion `
  --project-endpoint $projectEndpoint --no-prompt
if ($LASTEXITCODE -ne 0) { throw 'Toolbox publication failed.' }
azd env get-value APIM_TOOLBOX_MCP_URL
```

对于这次独立的首次部署，发布刚创建的版本。后续部署时，如果有其他操作人员并发
部署，应检查版本列表并明确选择目标版本。仅创建不可变版本并不会更新默认客户端终结点。

## 连接 VS Code

将 `samples\vscode\mcp.json.example` 复制到此示例文件夹的 `.vscode\mcp.json`
（Git 已忽略），替换 `<APIM_TOOLBOX_MCP_URL>`，并将此文件夹作为 VS Code
工作区打开。启动 **foundry-toolbox-entra-app**。

在 Azure 门户的 APIM **Subscriptions** 页面安全地获取
**Foundry Toolbox Entra app client** 的密钥，将其输入密码提示
`foundryToolboxEntraAppKey`。这是**前端 APIM 订阅密钥**，绝不是 Entra 应用
客户端机密。不要将任何一种凭据写入 JSON。此网关不要求客户端 OAuth/浏览器登录。

## 验证 API 行为

在选定的示例环境中运行：

```powershell
python .\scripts\verify.py
if ($LASTEXITCODE -ne 0) { throw 'Gateway verification failed.' }
```

验证器使用当前 Azure CLI/azd 身份验证，仅在内存中持有密钥/令牌，输出安全的 JSON
报告。它需要管理平面的读取/listSecrets、Graph 读取、角色分配读取权限，以及部署用户
的 Foundry 令牌。检查内容如下：

| 检查 | 预期结果 |
|---|---|
| 缺少密钥、错误密钥、仅有有效 Foundry bearer | HTTP 401 |
| 仅密钥的 `initialize` 和 `tools/list` | 成功结果和非空 Learn 工具目录 |
| `notifications/initialized` | HTTP 200、202 或 204 |
| 密钥搭配故意无效的客户端 bearer | `tools/list` 成功 |
| Microsoft Learn `microsoft_docs_search` | 成功结果且包含 Learn 引用 |
| 在线架构 | APIM 无标识、Application SP、client credentials 策略、固定后端、API 范围密钥、仅项目范围的 Foundry User、就绪的 secret named value |

这些是 API 级检查，**不代表已经完成 VS Code UI 测试**。

## 轮换、失败和运维限制

- **在 30 天到期前轮换：**在此示例选定的 azd 环境中执行
  `pwsh -File .\scripts\configure-app-credential.ps1`，然后重新运行验证器。
  请设置外部到期提醒；此示例不会安排自动轮换。
- 每个环境内应串行执行预配/轮换。单独轮换时，保留所有未过期密码，而不只是当前
  已安装的密码。仅在创建替代凭据前自动删除名为 `sample-4-apim-backend` 的
  已过期密码。不修改其他 displayName 的凭据。
- **不要通过反复轮换来排查传播问题。**ARM `Succeeded` 不代表所有网关节点都
  已使用新机密。凭据创建时间或猜测的等待时长都不能证明旧凭据已经不再使用。
  过早删除可能使仍使用旧值的网关节点间歇返回 `FoundryApplicationTokenFailed` 502。
- 保留是有意设计：旧密码在原定到期时间之前仍有效，因此频繁轮换会积累凭据并
  可能触及目录限制。hook 会对保留的凭据发出警告。如果 `addPassword` 失败，
  包括凭据数量限制或租户密码策略导致的失败，hook 会报告失败并保留未过期凭据，
  绝不会静默撤销某个凭据以腾出空间。应在到期前充分提前安排正常轮换，而不是
  反复重试，并监控有效期和凭据数量。
- **重新预配并非零停机。**`azd provision` 会先写入 `UNCONFIGURED` 并重置
  named-value 标签，然后由 hook 轮换/安装机密。网关传播期间预计会出现拒绝访问的
  503 窗口。重置标签不会导致 hook 删除任何未过期凭据。
- 配置失败会返回错误，绝不报告成功。新创建的凭据会保留用于恢复，到期元数据可能
  仍描述上次成功运行。重新运行 hook，验证在线网关，并检查应用凭据元数据中是否有
  过时的 hook 所属凭据。
- 令牌终结点拒绝时返回通用 502，不返回 Entra 的响应/令牌；named value 未配置时
  返回 503。请检查有效期、租户/应用 ID、named-value 状态、网络连通性和项目 RBAC。
  为 Entra/RBAC/APIM 传播留出时间。不要通过打印 secret named value、令牌或
  HTTP 请求体排查问题。
- 限制 APIM/Entra 管理权限：拥有机密访问权限的 APIM 管理员可以获取 named value。
  `secret: true` 隐藏值，但不能将其与这些管理员隔离。不要启用会记录订阅密钥、
  令牌或令牌终结点表单正文的 APIM tracing 或请求/请求头/正文日志。
  示例订阅设置了 `allowTracing: false`。
- APIM 订阅也可以通过配置的 `subscription-key` 查询参数传入密钥，但应优先使用
  请求头，避免密钥出现在 URL 日志中。两种形式都会在转发到 Foundry 前删除。
- 此示例使用公共终结点和共享应用授权。用于生产之前，应加入适当的网络控制、
  客户端配额、监控、生产级凭据生命周期管理及流式传输支持。

### 由操作人员控制的凭据撤销

应优先让旧密码自然到期。如果凭据数量限制、安全事件或明确的清理决策要求提前
撤销，请在 Entra 门户的 **Certificates & secrets** 中检查应用密码元数据，并查看
APIM named-value 的 `credential-<keyId>` 标签（绝不显示机密值）。
不要删除标签标记的已安装凭据，也不要认为未标记就代表未使用：网关节点可能
仍持有先前配置。

主动撤销时应安排中断：暂停前端 APIM 订阅，等待正在进行的调用结束，然后由获授权的
操作人员仅删除明确选定的旧密码。保留当前配置的密码。恢复订阅后反复执行验证器，
待调用稳定再向客户端重新开放访问；传播期间旧节点仍可能失败。如果密码已泄露，
应立即撤销并接受中断。此示例中的任何时间间隔都不保证全体节点完成传播，已删除的
密码无法恢复。如需完全停用此示例，请使用下文的清理脚本。

## 清理

删除 Azure 资源组不能可靠地删除租户级 Graph 对象。请保留本地 azd 环境直到清理
完成。先撤销后端应用和服务主体（会立即中断访问），再删除计费的 Azure 资源：

```powershell
pwsh -File .\scripts\cleanup-entra.ps1
if ($LASTEXITCODE -ne 0) { throw 'Entra cleanup failed; investigate before continuing.' }
azd down --no-prompt
```

此脚本仅操作此示例选定环境中的 ID，要求匹配租户，仅将 HTTP 404 视为已删除。
权限失败会报错。不要在其他示例/环境中执行这两个命令。

## Microsoft 文档

- [创建和管理 Toolbox](https://learn.microsoft.com/azure/foundry/agents/how-to/tools/toolbox)
- [OAuth client credentials flow](https://learn.microsoft.com/entra/identity-platform/v2-oauth2-client-creds-grant-flow)
- [Foundry RBAC](https://learn.microsoft.com/azure/foundry/concepts/rbac-foundry)
- [APIM subscriptions](https://learn.microsoft.com/azure/api-management/api-management-subscriptions)
- [APIM named values](https://learn.microsoft.com/azure/api-management/api-management-howto-properties)
- [APIM send-request policy](https://learn.microsoft.com/azure/api-management/send-request-policy)

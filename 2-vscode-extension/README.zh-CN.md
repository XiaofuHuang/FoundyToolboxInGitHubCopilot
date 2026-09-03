# 使用身份验证扩展连接 VS Code

[English](README.md) | **简体中文**

此示例无需 APIM，可将 VS Code 直接连接到 Microsoft Foundry Toolbox。
命令输入会：

1. 复用 **Azure: Sign In**，获取 `https://ai.azure.com/.default` 令牌。
2. 通过 `args.toolboxUrl` 接收 Toolbox 终结点。
3. 返回令牌前调用 `tools/list`。
4. 需要授权时打开 Foundry 返回的 GitHub 授权 URL。

随后，VS Code 会使用返回的 bearer token 和标准 HTTP MCP 传输连接 Toolbox。

## 先决条件

你需要：

- VS Code 1.136 或更高版本
- [Azure Resources](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-azureresourcegroups)
- 用于打包扩展的 Node.js 和 npm
- 一个已发布的 Foundry Toolbox MCP 终结点
- Foundry 项目的 **Foundry User** 角色

## 1. 打包并安装扩展

在 `2-vscode-extension` 目录中运行：

```powershell
npm ci
npm run package
code --install-extension .\foundry-toolbox-auth-0.0.5.vsix --force
```

重新加载 VS Code。如果尚未安装 Azure Resources，请先安装它。

## 2. 配置 `mcp.json`

将 `samples\vscode\mcp.json.example` 复制到工作区的
`.vscode\mcp.json`。将两个 `<FOUNDRY_TOOLBOX_MCP_URL>` 替换为同一个
已发布的使用者终结点：

```text
https://<account>.services.ai.azure.com/api/projects/<project>/toolboxes/<toolbox>/mcp?api-version=v1
```

关键部分是命令输入：

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

`foundryToolboxAuth.getAccessToken` 可以接收上面的对象，也可以直接接收 URL
字符串。如果没有提供终结点参数，它只返回令牌；如果 VS Code 设置中配置了
`foundryToolboxAuth.toolboxUrl`，则使用该值作为后备。

## 3. 启动 MCP 服务器

1. 运行 **MCP: List Servers**。
2. 启动 `toolbox-extension-auth`。
3. 如果出现提示，请完成 Microsoft 登录。

返回令牌前，命令会调用 `tools/list`。预检成功后，正常 MCP 启动会继续执行。

VS Code 会安全保存 MCP 输入值。Azure 令牌过期后，请打开
`.vscode\mcp.json`，选择 `toolboxExtensionTokenV2` 旁边的 **Clear**，然后
重启 `toolbox-extension-auth`。清除已保存输入后，VS Code 会再次调用命令以
获取刷新后的令牌。

## 4. 授权 GitHub

如果预检收到嵌套的 `CONSENT_REQUIRED`，VS Code 会显示 Foundry 返回的准确
URL 和 **Open GitHub Consent** 操作。

1. 选择 **Open GitHub Consent**。
2. 在浏览器中完成 GitHub 授权。
3. 在 `.vscode\mcp.json` 中清除已保存的 `toolboxExtensionTokenV2` 输入。
4. 重启 `toolbox-extension-auth`。
5. 如有需要，运行 **MCP: Reset Cached Tools**。
6. 确认 Microsoft Learn 和 GitHub 工具均可使用。

## 可选的手动预检

如需从命令面板运行相同预检，请参考 `settings.json.example`，在
`.vscode\settings.json` 中设置 `foundryToolboxAuth.toolboxUrl`，然后运行
**Foundry Toolbox: Sign In**。

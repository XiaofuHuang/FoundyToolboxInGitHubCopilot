# API-key gateway with an Entra application

[English](README.md) | [简体中文](README.zh-CN.md)

## Architecture and trust boundaries

```text
VS Code or another MCP HTTP client
  -- API-scoped APIM subscription key --> APIM Basic v2 (identity: None)
  -- APIM obtains an application token --> Microsoft Entra token endpoint
       grant_type=client_credentials, scope=https://ai.azure.com/.default
  -- application bearer token --> Microsoft Foundry project / Toolbox
  --> Microsoft Learn MCP
```

The two credentials have different owners and purposes:

| Boundary | Credential | Authorization |
|---|---|---|
| Client -> APIM | APIM subscription key in `Ocp-Apim-Subscription-Key` | Active subscription scoped to the `foundry-toolbox` API |
| APIM -> Foundry | Dedicated Entra application's 30-day client secret, exchanged for an application token | **Foundry User** (`53ca6127-db72-4b80-b1b0-d745d6d5456d`) assigned to its service principal at this new project only |

APIM has **no managed identity**. There is no OBO, user identity passthrough,
gateway OAuth scope, redirect URI, delegated permission grant, or GitHub consent.
The single-tenant app is backend-only. Foundry access is controlled by Azure
project RBAC, not an exposed application scope. The Foundry account/project may
have their own platform identities; APIM does not use them for backend calls.

APIM validates the subscription key before the API policy, then removes the key
header/query parameter and any client `Authorization` header. It obtains a new
application token **on every request** (no token cache), overrides `Authorization`,
and forwards to the fixed `tools` Toolbox endpoint. A valid key plus an invalid
client bearer still works; a bearer without a key does not.

All key holders act as the **same application**, not individual Foundry users.
Protect and rotate the frontend key independently of the backend app secret.
This sample exposes Microsoft Learn only; it is not a per-user authorization
gateway and does not grant clients arbitrary Foundry access.

> [!IMPORTANT]
> This standalone sample provisions **another billable APIM Basic v2 instance**
> and a separate Foundry account/project/application. Use a new environment and
> globally unique APIM name; do not reuse another sample's resources.

### MCP transport limitation

The native APIM `type: mcp` API uses explicit inbound
`send-request` / `return-response` to return the **real Toolbox response**.
Ordinary `forward-request` produced APIM's own empty tool catalog in this
integration. This pattern buffers the backend response, with a 120-second
request timeout; it is **not a general long-lived SSE relay**. Short JSON/SSE
request-response calls and initialization notifications are covered. Reassess
the gateway design before using persistent streams, server-initiated messages,
or long-running tools. Per-request token acquisition adds latency and Entra
availability/throttling dependencies.

## Prerequisites

- Azure CLI, Azure Developer CLI (`azd`), PowerShell 7 (`pwsh`).
- An Azure subscription and a region supporting APIM Basic v2 and Foundry
  (this example uses `eastus2`).
- Permission to create Azure resources and project role assignments, such as
  Owner on the target subscription/resource group.
- Entra permission to create/manage an application, service principal, and app
  passwords. Azure Owner alone does **not** grant directory permissions.
- Foundry User data-plane access for the deploying user on the new project
  (or an inherited assignment) to deploy/publish the Toolbox.
- Python 3.10+ only for the optional automated verification.

Use the **same tenant/account** for Azure CLI and azd. The credential hook uses
the current Azure CLI login without changing it. Do not run it with shell
transcription, HTTP/debug logging, or credential-capturing tracing enabled.

## Provision and publish

Run commands in PowerShell from `4-apim-entra-app`. Replace angle-bracket values;
all environment values below are non-secret.

### 1. Prepare tools and environment

Check `azd extension list`; install missing extensions:

```powershell
azd extension install microsoft.foundry
azd extension install azure.ai.projects
azd extension install azure.ai.toolboxes
```

The Toolbox extension must be at least `1.0.0-beta.5`. The Graph Bicep extension
is pinned in `infra\bicepconfig.json`; APIM MCP uses a preview management API.

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

### 2. Provision infrastructure and backend credential

```powershell
azd provision --no-prompt
```

The Foundry layer creates the account/project. Bicep creates APIM with
`identity.type: None`, the backend app/service principal, project-scoped RBAC,
the API-scoped subscription, and a secret named value initially containing
`UNCONFIGURED`. The policy fails closed with HTTP 503 until configured.

The mandatory `postprovision` hook in `scripts\configure-app-credential.ps1`:

1. Removes only expired passwords owned by this hook, then creates a 30-day app
   password with Microsoft Graph `addPassword`.
2. Confirms it can obtain a token for `https://ai.azure.com/.default`.
3. Writes the secret directly to `foundry-app-client-secret` via ARM HTTPS,
   with `secret: true`, and waits for named value provisioning.
4. Retains **all unexpired credentials**, including previous rotations, and saves
   only `ENTRA_APP_SECRET_EXPIRES_AT` to azd.

The secret and tokens stay in process memory during setup. They are not written
to local files, azd environment values, deployment parameters, or command-line
arguments. The persistent secret is in Entra and the APIM secret named value.
The hook suppresses sensitive HTTP details, exits on failures, and is not a
substitute for verifying gateway propagation and project RBAC below.

### 3. Deploy and explicitly publish the Toolbox version

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

For this isolated initial deployment, publish the version just created. On
subsequent deployments, inspect the version list and deliberately select the
intended version if another operator is deploying concurrently. Creating an
immutable version alone does not update the default consumer endpoint.

## Connect VS Code

Copy `samples\vscode\mcp.json.example` to `.vscode\mcp.json` inside this sample
folder (ignored by Git), replace `<APIM_TOOLBOX_MCP_URL>`, and open this folder
as the VS Code workspace. Start **foundry-toolbox-entra-app**.

Use the Azure portal's APIM **Subscriptions** page to securely retrieve the key
for **Foundry Toolbox Entra app client**. Enter it in the password prompt
`foundryToolboxEntraAppKey`. This is the **frontend APIM subscription key**, never
the Entra application client secret. Do not put either credential in JSON.
No client OAuth/browser login is required by this gateway.

## Verify API behavior

From the selected sample environment:

```powershell
python .\scripts\verify.py
if ($LASTEXITCODE -ne 0) { throw 'Gateway verification failed.' }
```

The verifier uses current Azure CLI/azd authentication, holds keys/tokens only
in memory, and emits a safe JSON report. It requires management read/listSecrets,
Graph read, role assignment read, and a deployer Foundry token. It checks:

| Check | Expected result |
|---|---|
| Missing key, wrong key, valid Foundry bearer only | HTTP 401 |
| Key-only `initialize` and `tools/list` | Successful result and nonempty Learn catalog |
| `notifications/initialized` | HTTP 200, 202, or 204 |
| Key plus deliberately invalid client bearer | Successful `tools/list` |
| Microsoft Learn `microsoft_docs_search` | Successful result with Learn references |
| Live architecture | No APIM identity, Application SP, client credentials policy, fixed backend, API-scoped key, project-only Foundry User, ready secret named value |

These are API-level checks, **not proof of a VS Code UI test**.

## Rotation, failures, and operational limits

- **Rotate before 30 days:** run `pwsh -File .\scripts\configure-app-credential.ps1`
  from this sample's selected azd environment, then rerun the verifier. Set an
  external expiry reminder; this sample does not schedule automatic rotation.
- Run provisioning/rotation serially per environment. Standalone rotation keeps
  all unexpired passwords, not just the currently installed one. Only expired
  passwords named `sample-4-apim-backend` are automatically removed, before
  creating a replacement. Credentials with other display names are untouched.
- **Do not rotate repeatedly to troubleshoot propagation.** ARM `Succeeded`
  does not mean every gateway node has the new secret. Neither credential
  creation time nor a guessed waiting period proves that an old credential is
  no longer in use. Removing it prematurely can cause intermittent
  `FoundryApplicationTokenFailed` 502 responses on stale gateway nodes.
- Retention is intentional: old passwords remain valid until their original
  expiry, so frequent rotation accumulates credentials and can reach directory
  limits. The hook warns about retained credentials. If `addPassword` fails,
  including because of a credential limit or tenant password policy, the hook
  reports failure and leaves unexpired credentials in place; it never silently
  revokes one to make space. Schedule normal rotation well before expiry rather
  than repeated retries, and monitor both expiry and credential count.
- **Reprovisioning is not zero-downtime.** `azd provision` writes `UNCONFIGURED`
  and resets the named-value tags before its hook rotates/reinstalls the secret.
  Expect a fail-closed 503 interval during gateway propagation. Resetting tags
  does not cause the hook to remove any unexpired credential.
- A failed setup returns an error, never success. A newly created credential
  is retained for recovery, and expiry metadata may still describe the previous
  successful run. Rerun the hook, verify the live gateway, and inspect
  application credential metadata for stale hook-owned credentials.
- Token endpoint rejection returns a generic 502 without returning Entra's
  response/token; an unconfigured named value returns 503. Check expiry,
  tenant/app IDs, named-value state, network connectivity, and project RBAC.
  Allow time for Entra/RBAC/APIM propagation. Never troubleshoot by printing
  secret named values, tokens, or HTTP request bodies.
- Restrict APIM/Entra administrative access: APIM administrators with secret
  access can retrieve the named value. `secret: true` masks the value; it is
  not isolation from those administrators. Do not enable APIM tracing or
  request/header/body logging containing subscription keys, tokens, or the
  token endpoint's form body. The sample subscription has `allowTracing: false`.
- An APIM subscription can also use its configured `subscription-key` query
  parameter, but prefer the header so keys do not appear in URL logs. Both
  forms are stripped before Foundry forwarding.
- The sample has public endpoints and shared application authorization. Add
  appropriate network controls, client quotas, monitoring, a production-grade
  credential lifecycle, and streaming support before adapting it to production.

### Operator-controlled credential revocation

Prefer letting old passwords expire naturally. If credential limits, a security
incident, or an explicit cleanup decision require earlier revocation, inspect
the app's **Certificates & secrets** metadata in the Entra portal and the APIM
named-value `credential-<keyId>` tag (never reveal the secret value).
Do not delete the tagged installed credential or assume that untagged means
unused: gateway nodes can still hold a previous configuration.

For deliberate revocation, plan an interruption: suspend the frontend APIM
subscription, wait for in-flight calls to finish, then have an authorized
operator delete only the specifically selected old password(s). Keep the
currently configured password. Restore the subscription and repeat the verifier
until calls are stable before reopening access to clients; stale nodes may
still fail during propagation. If a password was compromised, revoke it
immediately and accept the interruption. No time interval in this sample is a
guarantee of fleet-wide propagation, and a deleted password cannot be restored.
Full retirement of this sample uses the cleanup helper below instead.

## Cleanup

Removing Azure resource groups does not reliably remove tenant-level Graph
objects. Keep the local azd environment until cleanup finishes. First revoke
the backend application and service principal (this immediately breaks access),
then remove the billable Azure resources:

```powershell
pwsh -File .\scripts\cleanup-entra.ps1
if ($LASTEXITCODE -ne 0) { throw 'Entra cleanup failed; investigate before continuing.' }
azd down --no-prompt
```

The helper targets only IDs in this sample's selected environment, requires the
matching tenant, and treats only HTTP 404 as already absent. Permission failures
are errors. Do not run either command in another sample/environment.

## Microsoft documentation

- [Create and manage a Toolbox](https://learn.microsoft.com/azure/foundry/agents/how-to/tools/toolbox)
- [OAuth client credentials flow](https://learn.microsoft.com/entra/identity-platform/v2-oauth2-client-creds-grant-flow)
- [Foundry RBAC](https://learn.microsoft.com/azure/foundry/concepts/rbac-foundry)
- [APIM subscriptions](https://learn.microsoft.com/azure/api-management/api-management-subscriptions)
- [APIM named values](https://learn.microsoft.com/azure/api-management/api-management-howto-properties)
- [APIM send-request policy](https://learn.microsoft.com/azure/api-management/send-request-policy)

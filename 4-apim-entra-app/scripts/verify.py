"""Verify the selected sample 4 environment without printing credentials."""

import json
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APIM_VERSION = "2025-09-01-preview"
FOUNDRY_USER = "53ca6127-db72-4b80-b1b0-d745d6d5456d"


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def cli(executable, *args):
    path = shutil.which(executable)
    require(path is not None, f"{executable} is not installed.")
    result = subprocess.run(
        [path, *args], cwd=ROOT, capture_output=True, text=True,
        timeout=90, check=False,
    )
    require(result.returncode == 0, f"{executable} command failed; output suppressed.")
    return result.stdout.strip()


def request(method, url, headers=None, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    if method == "POST" and data is None:
        data = b""
    outgoing = {"Accept": "application/json, text/event-stream", **(headers or {})}
    if payload is not None:
        outgoing["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=outgoing, method=method)
    try:
        response = urllib.request.urlopen(req, timeout=130)
    except urllib.error.HTTPError as error:
        response = error
    except (urllib.error.URLError, TimeoutError):
        raise RuntimeError("HTTP transport failed; request details suppressed.") from None
    with response:
        return response.status, response.headers, response.read().decode("utf-8-sig")


def messages(body, headers):
    if not body.strip():
        return []
    if "text/event-stream" not in headers.get("Content-Type", ""):
        return [json.loads(body)]
    replies = []
    for event in body.replace("\r\n", "\n").split("\n\n"):
        data = [line[5:].lstrip() for line in event.splitlines() if line.startswith("data:")]
        if data:
            replies.append(json.loads("\n".join(data)))
    return replies


def require_gateway_success(status, body, operation):
    if status == 200:
        return
    code = ""
    try:
        parsed = json.loads(body)
        error = parsed.get("error") if isinstance(parsed, dict) else None
        candidate = error.get("code") if isinstance(error, dict) else None
        if candidate in ("BackendCredentialNotConfigured", "FoundryApplicationTokenFailed"):
            code = f" ({candidate})"
    except ValueError:
        pass
    raise RuntimeError(f"{operation} returned HTTP {status}{code}. Response details suppressed.")


def verify(checks):
    env = json.loads(cli("azd", "env", "get-values", "--output", "json"))
    subscription_id = env["AZURE_SUBSCRIPTION_ID"]
    tenant_id = env["ENTRA_TENANT_ID"]
    client_id = env["ENTRA_APP_CLIENT_ID"]
    principal_id = env["ENTRA_SERVICE_PRINCIPAL_OBJECT_ID"]
    service_id = (
        f"/subscriptions/{subscription_id}/resourceGroups/{env['AZURE_RESOURCE_GROUP']}"
        f"/providers/Microsoft.ApiManagement/service/{env['APIM_NAME']}"
    )
    project_id = (
        f"/subscriptions/{subscription_id}/resourceGroups/{env['AZURE_FOUNDRY_RESOURCE_GROUP']}"
        f"/providers/Microsoft.CognitiveServices/accounts/{env['AZURE_AI_ACCOUNT_NAME']}"
        f"/projects/{env['AZURE_AI_PROJECT_NAME']}"
    )
    mcp_url = f"https://{env['APIM_NAME']}.azure-api.net/toolbox/mcp"
    require(env["APIM_TOOLBOX_MCP_URL"] == mcp_url, "Gateway URL does not match this environment.")
    require(
        env["APIM_APP_SECRET_NAMED_VALUE_ID"].lower()
        == (service_id + "/namedValues/foundry-app-client-secret").lower(),
        "Named value is outside this environment.",
    )
    arm_token = cli(
        "az", "account", "get-access-token", "--subscription", subscription_id,
        "--resource", "https://management.azure.com/", "--query", "accessToken", "-o", "tsv",
    )
    graph_token = cli(
        "az", "account", "get-access-token", "--tenant", tenant_id,
        "--resource", "https://graph.microsoft.com/", "--query", "accessToken", "-o", "tsv",
    )

    def arm(path, method="GET", version=APIM_VERSION):
        status, _, body = request(
            method, f"https://management.azure.com{path}?api-version={version}",
            {"Authorization": "Bearer " + arm_token},
        )
        require(status == 200, f"Management request failed with HTTP {status}.")
        return json.loads(body)

    def graph(path):
        status, _, body = request(
            "GET", "https://graph.microsoft.com/v1.0/" + path,
            {"Authorization": "Bearer " + graph_token},
        )
        require(status == 200, f"Graph verification failed with HTTP {status}.")
        return json.loads(body)

    service = arm(service_id)
    # ARM may omit identity altogether when type is None.
    require((service.get("identity") or {}).get("type", "None") == "None",
            "APIM unexpectedly has a managed identity.")
    require(service["properties"]["provisioningState"] == "Succeeded", "APIM is not ready.")
    checks["apimIdentityNone"] = True
    principal = graph(f"servicePrincipals/{principal_id}")
    require(principal["servicePrincipalType"] == "Application" and principal["appId"] == client_id,
            "Backend principal is not the expected application.")
    app = graph(f"applications/{env['ENTRA_APP_OBJECT_ID']}")
    require(app["appId"] == client_id and app["signInAudience"] == "AzureADMyOrg",
            "Application is not the expected single-tenant registration.")
    require(not app.get("requiredResourceAccess"), "Unexpected delegated/API permission grants.")
    require(not app.get("web", {}).get("redirectUris"), "Unexpected web redirect URI.")
    require(not app.get("spa", {}).get("redirectUris"), "Unexpected SPA redirect URI.")
    require(not app.get("publicClient", {}).get("redirectUris"), "Unexpected public client redirect URI.")
    require(not app.get("api", {}).get("oauth2PermissionScopes"), "Unexpected exposed OAuth scope.")
    checks["backendOnlyApplication"] = True
    assignments = json.loads(cli(
        "az", "role", "assignment", "list", "--assignee", principal_id,
        "--all", "--output", "json",
    ))
    require(len(assignments) == 1, "Application should have exactly one assignment in this subscription.")
    assignment = assignments[0]
    require(assignment["scope"].lower() == project_id.lower(), "RBAC is not project-scoped.")
    require(assignment["roleDefinitionId"].endswith("/" + FOUNDRY_USER), "Wrong Foundry role.")
    checks["projectOnlyFoundryUser"] = True
    named_value = arm(env["APIM_APP_SECRET_NAMED_VALUE_ID"], version="2024-05-01")["properties"]
    require(named_value["secret"] is True and named_value["provisioningState"] == "Succeeded",
            "Secret named value is not ready.")
    active = [
        item for item in app["passwordCredentials"]
        if "credential-" + item["keyId"] in named_value.get("tags", [])
    ]
    require(len(active) == 1, "Named value has no matching installed application credential.")
    expiry = datetime.fromisoformat(active[0]["endDateTime"].replace("Z", "+00:00"))
    require(expiry > datetime.now(timezone.utc), "Application credential has expired.")
    require(expiry == datetime.fromisoformat(env["ENTRA_APP_SECRET_EXPIRES_AT"].replace("Z", "+00:00")),
            "Saved credential expiry does not match Entra.")
    checks["secretNamedValueReady"] = True
    checks["credentialExpiresAt"] = active[0]["endDateTime"]
    api = arm(service_id + "/apis/foundry-toolbox")["properties"]
    require(api["subscriptionRequired"] is True, "API subscription is not required.")
    subscription_path = service_id + "/subscriptions/toolbox-client"
    subscription = arm(subscription_path)["properties"]
    require(subscription["state"] == "active", "APIM subscription is not active.")
    require(subscription["scope"].lower() == (service_id + "/apis/foundry-toolbox").lower(),
            "APIM subscription is not API-scoped.")
    checks["apiScopedSubscription"] = True
    policy_text = arm(service_id + "/apis/foundry-toolbox/policies/policy")["properties"]["value"]
    policy = ET.fromstring(policy_text)
    require(policy.find(".//authentication-managed-identity") is None, "Unexpected managed identity policy.")
    require("on_behalf_of" not in policy_text and "requested_token_use" not in policy_text,
            "Unexpected OBO policy.")
    sends = policy.findall("inbound/send-request")
    require(len(sends) == 2, "Expected explicit token and Toolbox requests.")
    require(sends[0].findtext("set-url") == f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token",
            "Unexpected token endpoint.")
    token_body = sends[0].findtext("set-body", "")
    require("grant_type=client_credentials" in token_body and "https://ai.azure.com/.default" in token_body
            and client_id in token_body, "Unexpected client credentials policy.")
    target = (
        f"https://{env['AZURE_AI_ACCOUNT_NAME']}.services.ai.azure.com/api/projects/"
        f"{env['AZURE_AI_PROJECT_NAME']}/toolboxes/tools/mcp?api-version=v1"
    )
    require(sends[1].findtext("set-url") == target, "Unexpected Toolbox backend.")
    require(policy.find("inbound/return-response").get("response-variable-name") == "toolbox-response",
            "Gateway does not return the real Toolbox response.")
    checks["clientCredentialsForwarding"] = True

    key = arm(subscription_path + "/listSecrets", "POST")["primaryKey"]
    require(bool(key), "APIM subscription key is unavailable.")
    bearer = cli(
        "az", "account", "get-access-token", "--tenant", tenant_id,
        "--resource", "https://ai.azure.com/", "--query", "accessToken", "-o", "tsv",
    )
    initialize = {
        "jsonrpc": "2.0", "id": 1, "method": "initialize",
        "params": {
            "protocolVersion": "2025-11-25", "capabilities": {},
            "clientInfo": {"name": "entra-app-gateway-check", "version": "1.0"},
        },
    }
    for name, headers in (
        ("missingKeyRejected", {}),
        ("wrongKeyRejected", {"Ocp-Apim-Subscription-Key": "invalid-test-key"}),
        ("bearerOnlyRejected", {"Authorization": "Bearer " + bearer}),
    ):
        status, _, _ = request("POST", mcp_url, headers, initialize)
        require(status == 401, f"{name}: expected 401, received {status}.")
        checks[name] = status
    client_headers = {"Ocp-Apim-Subscription-Key": key}
    status, headers, body = request("POST", mcp_url, client_headers, initialize)
    require_gateway_success(status, body, "Key-only initialize")
    reply = next((item for item in messages(body, headers) if item.get("id") == 1), {})
    require("result" in reply and "error" not in reply, "Initialize returned no successful result.")
    require(bool(reply["result"].get("serverInfo", {}).get("name")), "Missing MCP server identity.")
    checks["keyOnlyInitialize"] = reply["result"]["serverInfo"]
    client_headers["MCP-Protocol-Version"] = reply["result"]["protocolVersion"]
    if headers.get("Mcp-Session-Id"):
        client_headers["Mcp-Session-Id"] = headers["Mcp-Session-Id"]
    status, _, _ = request(
        "POST", mcp_url, client_headers,
        {"jsonrpc": "2.0", "method": "notifications/initialized"},
    )
    require(status in (200, 202, 204), f"Initialized notification returned HTTP {status}.")
    checks["initializedNotification"] = status
    next_id = 2

    def call(method, params, extra_headers=None):
        nonlocal next_id
        request_id = next_id
        next_id += 1
        status, headers, body = request(
            "POST", mcp_url, {**client_headers, **(extra_headers or {})},
            {"jsonrpc": "2.0", "id": request_id, "method": method, "params": params},
        )
        require_gateway_success(status, body, method)
        reply = next((item for item in messages(body, headers) if item.get("id") == request_id), {})
        require("error" not in reply and "result" in reply, f"{method} did not return a successful result.")
        return reply["result"]

    tools, params, cursors = [], {}, set()
    while True:
        listed = call("tools/list", params)
        require(isinstance(listed.get("tools"), list), "Missing tools array.")
        tools.extend(listed["tools"])
        cursor = listed.get("nextCursor")
        if not cursor:
            break
        require(cursor not in cursors and len(cursors) < 100, "Invalid tools pagination.")
        cursors.add(cursor)
        params = {"cursor": cursor}
    require(bool(tools), "Gateway returned an empty catalog.")
    checks["toolsList"] = {"count": len(tools), "names": [tool["name"] for tool in tools]}
    listed = call("tools/list", {}, {"Authorization": "Bearer deliberately-invalid-client-token"})
    require(bool(listed.get("tools")), "Invalid client bearer interfered with application authentication.")
    checks["invalidClientBearerIgnored"] = True
    search = next((tool for tool in tools if tool["name"].endswith("microsoft_docs_search")), None)
    require(search is not None, "Microsoft Learn search is unavailable.")
    result = call("tools/call", {
        "name": search["name"],
        "arguments": {"query": "Microsoft Entra OAuth client credentials flow"},
    })
    require(result.get("isError") is not True and bool(result.get("content")), "Learn search failed.")
    require("learn.microsoft.com" in json.dumps(result), "Search returned no Microsoft Learn references.")
    checks["learnSearch"] = True
    return {"endpoint": mcp_url, "applicationClientId": client_id, "projectId": project_id}


def main():
    report = {"startedAt": datetime.now(timezone.utc).isoformat(), "checks": {}}
    try:
        report.update(verify(report["checks"]))
        report["status"] = "passed"
    except RuntimeError as error:
        report.update(status="failed", error=str(error))
    except Exception:
        report.update(status="failed", error="Unexpected verification failure; details suppressed to protect credentials.")
    report["completedAt"] = datetime.now(timezone.utc).isoformat()
    print(json.dumps(report, indent=2))
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    sys.exit(main())

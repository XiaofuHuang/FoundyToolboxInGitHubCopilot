// @ts-check

/**
 * @param {unknown} argument
 */
function getToolboxUrlArgument(argument) {
  const value =
    typeof argument === 'string'
      ? argument
      : argument && typeof argument === 'object' && 'toolboxUrl' in argument
        ? argument.toolboxUrl
        : undefined;
  return typeof value === 'string' && value.trim() ? value.trim() : undefined;
}

/**
 * @param {string} toolboxUrl
 * @param {string} accessToken
 * @param {typeof fetch} [fetchImpl]
 * @param {(message: string) => void} [log]
 */
async function getToolboxConsentUrl(toolboxUrl, accessToken, fetchImpl = fetch, log) {
  const endpoint = new URL(toolboxUrl);
  log?.(`Toolbox preflight: POST ${endpoint.origin}${endpoint.pathname} (credentials, query and fragment omitted).`);
  const started = Date.now();
  const response = await fetchImpl(toolboxUrl, {
    method: 'POST',
    headers: {
      Accept: 'application/json',
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
      'MCP-Protocol-Version': '2025-11-25'
    },
    body: JSON.stringify({
      jsonrpc: '2.0',
      id: 'foundry-toolbox-auth-tools-list',
      method: 'tools/list',
      params: {}
    })
  });

  log?.(`Toolbox preflight: HTTP ${response.status} received in ${Date.now() - started} ms.`);
  if (!response.ok) {
    throw new Error(`Foundry Toolbox tools/list returned HTTP ${response.status}.`);
  }

  log?.('Toolbox preflight: reading the JSON response (body not logged).');
  const payload = await response.json();
  log?.('Toolbox preflight: JSON response read; checking for consent requirements.');
  const message =
    payload &&
    typeof payload === 'object' &&
    'error' in payload &&
    payload.error &&
    typeof payload.error === 'object' &&
    'message' in payload.error &&
    typeof payload.error.message === 'string'
      ? payload.error.message
      : '';
  const jsonStart = message.indexOf('{');
  if (jsonStart < 0) {
    return undefined;
  }

  const details = JSON.parse(message.slice(jsonStart));
  for (const item of details.errors || []) {
    if (item.error?.code === 'CONSENT_REQUIRED') {
      return item.error.message;
    }
  }
  return undefined;
}

module.exports = { getToolboxConsentUrl, getToolboxUrlArgument };

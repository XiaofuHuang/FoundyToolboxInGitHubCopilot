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
 */
async function getToolboxConsentUrl(toolboxUrl, accessToken, fetchImpl = fetch) {
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

  if (!response.ok) {
    throw new Error(`Foundry Toolbox tools/list returned HTTP ${response.status}.`);
  }

  const payload = await response.json();
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

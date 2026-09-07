// @ts-check

const vscode = require('vscode');
const { getSessionFromVSCode } = require('@microsoft/vscode-azext-azureauth');
const { showConsentUrl } = require('./notifications');
const { getToolboxConsentUrl, getToolboxUrlArgument } = require('./toolboxClient');
const { formatError } = require('./diagnostics');

const TOKEN_SCOPE = 'https://ai.azure.com/.default';

/**
 * @param {string} name
 */
function getSetting(name) {
  return vscode.workspace.getConfiguration('foundryToolboxAuth').get(name, '').trim();
}

/**
 * @param {(message: string) => void} log
 */
async function getAzureToken(log) {
  const tenantId = getSetting('tenantId') || undefined;
  log(`Azure token: requesting a silent session (${tenantId ? 'configured' : 'default'} tenant).`);
  let session = await getSessionFromVSCode(TOKEN_SCOPE, tenantId, { silent: true });
  if (!session) {
    log('Azure token: no silent session; starting Azure sign-in.');
    await vscode.commands.executeCommand('azureResourceGroups.logIn');
    log('Azure token: requesting a session after sign-in.');
    session = await getSessionFromVSCode(TOKEN_SCOPE, tenantId, { createIfNone: true });
  }
  if (!session) {
    throw new Error('Azure sign-in did not return a Foundry token.');
  }
  log('Azure token: acquired successfully (token not logged).');
  return session.accessToken;
}

/**
 * @param {unknown} argument
 * @param {(message: string) => void} log
 */
async function getTokenAndShowConsent(argument, log) {
  const token = await getAzureToken(log);
  const toolboxUrl = getToolboxUrlArgument(argument) || getSetting('toolboxUrl');
  if (toolboxUrl) {
    log('Toolbox preflight: starting.');
    const consentUrl = await getToolboxConsentUrl(toolboxUrl, token, undefined, log);
    if (consentUrl) {
      log('Toolbox preflight: consent required; showing the consent prompt (URL not logged).');
      await showConsentUrl(vscode, consentUrl);
      log('Consent prompt closed.');
    } else {
      log('Toolbox preflight: no consent URL returned.');
    }
  } else {
    log('Toolbox preflight: skipped because no Toolbox URL is configured.');
  }
  log('Returning the Azure token to the caller (token not logged).');
  return token;
}

/**
 * @param {vscode.ExtensionContext} context
 */
function activate(context) {
  const output = vscode.window.createOutputChannel('Foundry Toolbox Authentication', { log: true });
  context.subscriptions.push(output);
  output.info(`Extension activated. VS Code ${vscode.version}; Node ${process.version}; host: ${vscode.env.remoteName || 'local'}.`);
  let requestId = 0;

  /**
   * @param {unknown} argument
   */
  const run = (argument) => {
    const id = ++requestId;
    const started = Date.now();
    /** @param {string} message */
    const log = (message) => output.info(`[${id}] ${message}`);
    log('Authentication command started.');
    return getTokenAndShowConsent(argument, log)
      .then((token) => {
        log(`Authentication command completed in ${Date.now() - started} ms.`);
        return token;
      })
      .catch((error) => {
        const details = formatError(error);
        output.error(`[${id}] Authentication command failed after ${Date.now() - started} ms.\n${details}`);
        void vscode.window.showErrorMessage(
          `Foundry Toolbox authentication failed: ${details.split('\n')[0]}. See Output > Foundry Toolbox Authentication for details.`
        );
        throw error;
      });
  };

  context.subscriptions.push(
    vscode.commands.registerCommand('foundryToolboxAuth.getAccessToken', run),
    vscode.commands.registerCommand('foundryToolboxAuth.signIn', () => run(undefined))
  );
}

function deactivate() {}

module.exports = { activate, deactivate };

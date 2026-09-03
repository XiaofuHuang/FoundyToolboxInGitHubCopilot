// @ts-check

const vscode = require('vscode');
const { getSessionFromVSCode } = require('@microsoft/vscode-azext-azureauth');
const { showConsentUrl } = require('./notifications');
const { getToolboxConsentUrl, getToolboxUrlArgument } = require('./toolboxClient');

const TOKEN_SCOPE = 'https://ai.azure.com/.default';

/**
 * @param {string} name
 */
function getSetting(name) {
  return vscode.workspace.getConfiguration('foundryToolboxAuth').get(name, '').trim();
}

async function getAzureToken() {
  const tenantId = getSetting('tenantId') || undefined;
  let session = await getSessionFromVSCode(TOKEN_SCOPE, tenantId, { silent: true });
  if (!session) {
    await vscode.commands.executeCommand('azureResourceGroups.logIn');
    session = await getSessionFromVSCode(TOKEN_SCOPE, tenantId, { createIfNone: true });
  }
  if (!session) {
    throw new Error('Azure sign-in did not return a Foundry token.');
  }
  return session.accessToken;
}

/**
 * @param {unknown} argument
 */
async function getTokenAndShowConsent(argument) {
  const token = await getAzureToken();
  const toolboxUrl = getToolboxUrlArgument(argument) || getSetting('toolboxUrl');
  if (toolboxUrl) {
    const consentUrl = await getToolboxConsentUrl(toolboxUrl, token);
    if (consentUrl) {
      await showConsentUrl(vscode, consentUrl);
    }
  }
  return token;
}

/**
 * @param {vscode.ExtensionContext} context
 */
function activate(context) {
  /**
   * @param {unknown} argument
   */
  const run = (argument) =>
    getTokenAndShowConsent(argument).catch((error) => {
      void vscode.window.showErrorMessage(
        `Foundry Toolbox authentication failed: ${error instanceof Error ? error.message : String(error)}`
      );
      throw error;
    });

  context.subscriptions.push(
    vscode.commands.registerCommand('foundryToolboxAuth.getAccessToken', run),
    vscode.commands.registerCommand('foundryToolboxAuth.signIn', () => run(undefined))
  );
}

function deactivate() {}

module.exports = { activate, deactivate };

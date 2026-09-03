const vscode = require('vscode');
const { getSessionFromVSCode } = require('@microsoft/vscode-azext-azureauth');

const TOKEN_SCOPE = 'https://ai.azure.com/.default';

function getTenantId() {
  return vscode.workspace.getConfiguration('foundryToolboxAuth').get('tenantId', '').trim() || undefined;
}

async function getAzureSession() {
  const tenantId = getTenantId();
  let session = await getSessionFromVSCode(TOKEN_SCOPE, tenantId, { silent: true });
  if (session) {
    return session;
  }

  await vscode.commands.executeCommand('azureResourceGroups.logIn');
  session = await getSessionFromVSCode(TOKEN_SCOPE, tenantId, { createIfNone: true });
  if (!session) {
    throw new Error('Azure sign-in completed, but no Foundry token was returned.');
  }
  return session;
}

async function runWithErrorMessage(action) {
  try {
    return await action();
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    vscode.window.showErrorMessage(`Foundry Toolbox authentication failed: ${message}`);
    throw error;
  }
}

function activate(context) {
  context.subscriptions.push(
    vscode.commands.registerCommand('foundryToolboxAuth.getAccessToken', () =>
      runWithErrorMessage(async () => (await getAzureSession()).accessToken)
    ),
    vscode.commands.registerCommand('foundryToolboxAuth.signIn', () =>
      runWithErrorMessage(async () => {
        await vscode.commands.executeCommand('azureResourceGroups.logIn');
        const session = await getSessionFromVSCode(TOKEN_SCOPE, getTenantId(), { createIfNone: true });
        if (!session) {
          throw new Error('Azure sign-in completed, but no Foundry token was returned.');
        }
        vscode.window.showInformationMessage(`Signed in to Foundry Toolbox as ${session.account.label}.`);
      })
    )
  );
}

function deactivate() {}

module.exports = { activate, deactivate };

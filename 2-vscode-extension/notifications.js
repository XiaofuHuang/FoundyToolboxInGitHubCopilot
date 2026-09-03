// @ts-check

const OPEN_CONSENT = 'Open GitHub Consent';

/**
 * @param {typeof import('vscode')} vscode
 * @param {string} consentUrl
 */
async function showConsentUrl(vscode, consentUrl) {
  const selected = await vscode.window.showWarningMessage(
    'GitHub authorization is required for this Foundry Toolbox.',
    { modal: true, detail: consentUrl },
    OPEN_CONSENT
  );
  if (selected === OPEN_CONSENT) {
    await vscode.env.openExternal(vscode.Uri.parse(consentUrl, true));
  }
}

module.exports = { showConsentUrl };

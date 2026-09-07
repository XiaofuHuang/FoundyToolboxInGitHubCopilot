// @ts-check

/**
 * @param {string} text
 */
function redactDiagnosticText(text) {
  return text
    .replace(/\bBearer\s+[^\s"',;]+/gi, 'Bearer [REDACTED]')
    .replace(/\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*/g, '[REDACTED]')
    .replace(/https?:\/\/[^\s"'<>]+/gi, (value) => {
      if (!URL.canParse(value)) {
        return '[invalid URL]';
      }
      const url = new URL(value);
      return `${url.origin}${url.pathname}${url.search ? '?[REDACTED]' : ''}${url.hash ? '#[REDACTED]' : ''}`;
    })
    .replace(
      /\b(access_token|refresh_token|id_token|client_secret|authorization|token|sig)(["']?\s*[:=]\s*["']?)[^\s"'&,;]+/gi,
      '$1$2[REDACTED]'
    );
}

/**
 * Keep nested network causes, without dumping request headers or response bodies.
 * @param {unknown} error
 * @param {Set<object>} [seen]
 * @returns {string}
 */
function formatError(error, seen = new Set()) {
  if (!error || typeof error !== 'object') {
    return redactDiagnosticText(String(error));
  }
  if (seen.has(error)) {
    return '[circular error]';
  }
  seen.add(error);

  const details = [];
  if (error instanceof SyntaxError) {
    // JSON parsing errors can include excerpts of the response body.
    details.push('SyntaxError: parsing failed (input omitted).');
  } else if ('stack' in error && typeof error.stack === 'string') {
    details.push(error.stack);
  } else if ('message' in error && typeof error.message === 'string') {
    details.push(error.message);
  } else {
    details.push('Unknown error');
  }
  if ('code' in error && (typeof error.code === 'string' || typeof error.code === 'number')) {
    details.push(`code: ${error.code}`);
  }
  if ('cause' in error && error.cause !== undefined) {
    details.push(`Caused by: ${formatError(error.cause, seen)}`);
  }
  if ('errors' in error && Array.isArray(error.errors)) {
    for (const [index, nested] of error.errors.entries()) {
      details.push(`Inner error ${index + 1}: ${formatError(nested, seen)}`);
    }
  }
  return redactDiagnosticText(details.join('\n'));
}

module.exports = { formatError };

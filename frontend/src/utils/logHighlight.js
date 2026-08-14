/** Shared toast timing (ms) */
export const TOAST_VISIBLE_MS = 2000;
export const TOAST_FADE_MS = 200;

/**
 * Tokenize hardware log text for terminal-style highlighting.
 * Single-pass regex; safe for a few hundred lines.
 */
const TOKEN_RE = /(\b(?:Error|Exception|Fatal)\b)|(0x[0-9a-fA-F]+)/gi;

/**
 * @param {string} text
 * @returns {{ type: 'kw'|'hex'|'text', value: string }[]}
 */
export function tokenizeLog(text) {
  if (!text) return [];

  const tokens = [];
  let lastIndex = 0;
  let match;

  // Reset lastIndex for global regex reuse
  TOKEN_RE.lastIndex = 0;

  while ((match = TOKEN_RE.exec(text)) !== null) {
    if (match.index > lastIndex) {
      tokens.push({ type: 'text', value: text.slice(lastIndex, match.index) });
    }
    if (match[1]) {
      tokens.push({ type: 'kw', value: match[1] });
    } else if (match[2]) {
      tokens.push({ type: 'hex', value: match[2] });
    }
    lastIndex = TOKEN_RE.lastIndex;
  }

  if (lastIndex < text.length) {
    tokens.push({ type: 'text', value: text.slice(lastIndex) });
  }

  return tokens;
}

const TOKEN_CLASS = {
  kw: 'log-tok-kw',
  hex: 'log-tok-hex',
  text: 'log-tok-text',
};

/**
 * Render highlighted spans for a log string (React elements via createElement-free map).
 * Call from a component that imports React.
 */
export function mapLogTokens(text, React) {
  const tokens = tokenizeLog(text);
  if (tokens.length === 0) {
    return null;
  }
  return tokens.map((tok, i) =>
    React.createElement(
      'span',
      { key: i, className: TOKEN_CLASS[tok.type] || TOKEN_CLASS.text },
      tok.value
    )
  );
}

/**
 * Models wrap identifiers in Markdown backticks. In this chat font those
 * glyphs sit on the next letter and look like grave accents. Rewrite them
 * to plain ASCII double quotes, then drop any leftover backtick/grave marks.
 */
export function spaceQuoteMarks(text: string): string {
  return text
    .replace(/`([^`\n]+)`/g, '"$1"')
    .replace(/[‘’‛‚`´]/g, '');
}

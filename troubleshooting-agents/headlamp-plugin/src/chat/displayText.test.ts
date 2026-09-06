import { describe, expect, it } from 'vitest';
import { spaceQuoteMarks } from './displayText';

describe('spaceQuoteMarks', () => {
  it('rewrites paired backticks to ASCII double quotes', () => {
    expect(spaceQuoteMarks('reporting `ready: true`:')).toBe('reporting "ready: true":');
  });

  it('strips leftover grave/backtick marks', () => {
    expect(spaceQuoteMarks('stuck at `booting')).toBe('stuck at booting');
  });

  it('does not change text without quote marks', () => {
    expect(spaceQuoteMarks('All four nodes are Ready.')).toBe('All four nodes are Ready.');
  });
});

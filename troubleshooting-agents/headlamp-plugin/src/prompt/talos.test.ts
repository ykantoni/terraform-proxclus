import { describe, expect, it } from 'vitest';
import { TALOS_SYSTEM_PROMPT } from './talos';

describe('Talos system prompt', () => {
  it('forbids SSH, talosctl, and mutating actions', () => {
    expect(TALOS_SYSTEM_PROMPT).toMatch(/Never suggest ssh, talosctl/i);
    expect(TALOS_SYSTEM_PROMPT).toMatch(/troubleshooting-agents/);
    expect(TALOS_SYSTEM_PROMPT).toMatch(/ext-nvidia-persistenced/);
    expect(TALOS_SYSTEM_PROMPT).toMatch(/192\.168\.1\.99/);
    expect(TALOS_SYSTEM_PROMPT).toMatch(/do not invent cluster state/i);
  });
});

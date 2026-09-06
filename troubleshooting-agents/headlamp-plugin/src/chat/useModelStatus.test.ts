import { renderHook, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import * as client from '../ollama/client';
import { PluginSettings } from '../settings/types';
import { useModelStatus } from './useModelStatus';

vi.mock('../ollama/client', () => ({ pingModel: vi.fn() }));

const settings: PluginSettings = {
  baseUrl: 'http://ollama.local:11434',
  model: 'gemma4:26b',
  timeoutSeconds: 5,
  keepAlive: '30m',
  transport: 'direct',
  proxyNamespace: 'ollama',
  proxyService: 'ollama',
  proxyPort: 11434,
};

beforeEach(() => {
  vi.mocked(client.pingModel).mockReset();
});

describe('useModelStatus', () => {
  it('starts null, then resolves to the ping result', async () => {
    vi.mocked(client.pingModel).mockResolvedValue({
      loaded: true,
      transport: 'direct',
      name: 'gemma4:26b',
    });

    const { result } = renderHook(() => useModelStatus(settings));
    expect(result.current).toBeNull();

    await waitFor(() => expect(result.current).not.toBeNull());
    expect(result.current).toMatchObject({ loaded: true, name: 'gemma4:26b' });
  });

  it('re-pings when baseUrl/model/transport change', async () => {
    vi.mocked(client.pingModel).mockResolvedValue({ loaded: false, transport: 'direct' });

    const { rerender } = renderHook(({ s }) => useModelStatus(s), { initialProps: { s: settings } });
    await waitFor(() => expect(client.pingModel).toHaveBeenCalledTimes(1));

    rerender({ s: { ...settings, model: 'other-model' } });
    await waitFor(() => expect(client.pingModel).toHaveBeenCalledTimes(2));
  });

  it('does not update state after unmount', async () => {
    let resolvePing: (v: { loaded: boolean; transport: 'direct' }) => void;
    vi.mocked(client.pingModel).mockReturnValue(
      new Promise(resolve => {
        resolvePing = resolve;
      }) as any
    );

    const { unmount } = renderHook(() => useModelStatus(settings));
    unmount();
    // Resolving after unmount must not throw a "state update on unmounted
    // component" warning/error — this just asserts it doesn't blow up.
    resolvePing!({ loaded: true, transport: 'direct' });
  });
});

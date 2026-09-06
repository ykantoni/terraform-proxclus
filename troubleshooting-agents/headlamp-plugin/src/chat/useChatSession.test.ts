import { act, renderHook } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import * as kube from '../gather/kube';
import { ClusterSnapshot } from '../gather/types';
import * as client from '../ollama/client';
import { PluginSettings } from '../settings/types';
import { useChatSession } from './useChatSession';

vi.mock('../gather/kube', () => ({ gatherSnapshot: vi.fn() }));
vi.mock('../ollama/client', () => ({ streamChat: vi.fn() }));

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

const emptySnapshot: ClusterSnapshot = {
  gatheredAt: 't',
  errors: [],
  nodes: [],
  unhealthyPods: [],
  warningEvents: [],
};

afterEach(() => {
  vi.clearAllMocks();
});

describe('useChatSession', () => {
  it('ignores blank input', async () => {
    const { result } = renderHook(() =>
      useChatSession({ cluster: 'c1', settings, includeSnapshot: false })
    );

    await act(async () => {
      await result.current.send('   ');
    });

    expect(result.current.messages).toHaveLength(0);
    expect(client.streamChat).not.toHaveBeenCalled();
  });

  it('appends a user message and a pending assistant message, then fills in the streamed reply', async () => {
    vi.mocked(client.streamChat).mockImplementation(async ({ onToken }) => {
      onToken('Hello');
      onToken(' world');
      return 'direct';
    });

    const { result } = renderHook(() =>
      useChatSession({ cluster: 'c1', settings, includeSnapshot: false })
    );

    await act(async () => {
      await result.current.send('is the cluster healthy?');
    });

    expect(result.current.messages).toHaveLength(2);
    expect(result.current.messages[0]).toMatchObject({
      role: 'user',
      content: 'is the cluster healthy?',
    });
    expect(result.current.messages[1]).toMatchObject({
      role: 'assistant',
      content: 'Hello world',
      pending: false,
    });
    expect(result.current.messages[1].elapsedSeconds).toBeGreaterThanOrEqual(0);
    expect(result.current.busy).toBe(false);
    expect(result.current.phase).toBe('idle');
  });

  it('does not call streamChat again while a send is already in flight', async () => {
    let releaseStream: () => void = () => undefined;
    vi.mocked(client.streamChat).mockImplementation(
      () =>
        new Promise(resolve => {
          releaseStream = () => resolve('direct');
        })
    );

    const { result } = renderHook(() =>
      useChatSession({ cluster: 'c1', settings, includeSnapshot: false })
    );

    let firstSend!: Promise<void>;
    act(() => {
      firstSend = result.current.send('first question');
    });
    expect(result.current.busy).toBe(true);

    await act(async () => {
      await result.current.send('second question, should be ignored');
    });

    expect(client.streamChat).toHaveBeenCalledTimes(1);
    expect(result.current.messages).toHaveLength(2); // only the first question's turn

    await act(async () => {
      releaseStream();
      await firstSend;
    });
  });

  it('gathers a snapshot first when includeSnapshot is true, and attaches it to the assistant message', async () => {
    vi.mocked(kube.gatherSnapshot).mockResolvedValue(emptySnapshot);
    vi.mocked(client.streamChat).mockImplementation(async ({ onToken }) => {
      onToken('ok');
      return 'direct';
    });

    const current = { kind: 'Pod', name: 'x', namespace: 'ns' };
    const { result } = renderHook(() =>
      useChatSession({ cluster: 'c1', settings, current, includeSnapshot: true })
    );

    await act(async () => {
      await result.current.send('what is wrong with this pod?');
    });

    expect(kube.gatherSnapshot).toHaveBeenCalledWith(current, 'c1');
    expect(result.current.messages[1].snapshot).toBe(emptySnapshot);
  });

  it('never calls gatherSnapshot when includeSnapshot is false', async () => {
    vi.mocked(client.streamChat).mockImplementation(async ({ onToken }) => {
      onToken('ok');
      return 'direct';
    });

    const { result } = renderHook(() =>
      useChatSession({ cluster: 'c1', settings, includeSnapshot: false })
    );

    await act(async () => {
      await result.current.send('hello');
    });

    expect(kube.gatherSnapshot).not.toHaveBeenCalled();
    expect(result.current.messages[1].snapshot).toBeUndefined();
  });

  it('marks the assistant message as an error when streamChat rejects', async () => {
    vi.mocked(client.streamChat).mockRejectedValue(new Error('Ollama unreachable'));

    const { result } = renderHook(() =>
      useChatSession({ cluster: 'c1', settings, includeSnapshot: false })
    );

    await act(async () => {
      await result.current.send('hello');
    });

    expect(result.current.messages[1]).toMatchObject({ error: true, pending: false });
    expect(result.current.messages[1].content).toMatch(/Ollama unreachable/);
    expect(result.current.busy).toBe(false);
    expect(result.current.phase).toBe('idle');
  });

  it('only replays the last few turns as conversation history', async () => {
    let lastPayload: { role: string; content: string }[] = [];
    vi.mocked(client.streamChat).mockImplementation(async ({ messages, onToken }) => {
      lastPayload = messages;
      onToken('ack');
      return 'direct';
    });

    const { result } = renderHook(() =>
      useChatSession({ cluster: 'c1', settings, includeSnapshot: false })
    );

    for (let i = 0; i < 5; i++) {
      // eslint-disable-next-line no-await-in-loop
      await act(async () => {
        await result.current.send(`question ${i}`);
      });
    }

    // payload = [system prompt, ...history, this turn's question] —
    // history itself must never exceed the configured window.
    const historyCount = lastPayload.length - 2;
    expect(historyCount).toBeLessThanOrEqual(6);
  });
});

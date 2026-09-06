import { ApiProxy } from '@kinvolk/headlamp-plugin/lib';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { PluginSettings } from '../settings/types';
import { pingModel, streamChat } from './client';

vi.mock('@kinvolk/headlamp-plugin/lib', () => ({
  ApiProxy: { request: vi.fn() },
  Utils: { getCluster: vi.fn(() => null) },
}));

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

function ndjsonBody(objs: unknown[]): ReadableStream<Uint8Array> {
  const encoder = new TextEncoder();
  return new ReadableStream({
    start(controller) {
      for (const obj of objs) {
        controller.enqueue(encoder.encode(`${JSON.stringify(obj)}\n`));
      }
      controller.close();
    },
  });
}

function chunkedBody(chunks: string[]): ReadableStream<Uint8Array> {
  const encoder = new TextEncoder();
  return new ReadableStream({
    start(controller) {
      for (const c of chunks) {
        controller.enqueue(encoder.encode(c));
      }
      controller.close();
    },
  });
}

let fetchMock: ReturnType<typeof vi.fn>;

beforeEach(() => {
  fetchMock = vi.fn();
  vi.stubGlobal('fetch', fetchMock);
  vi.mocked(ApiProxy.request).mockReset();
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('streamChat', () => {
  it('streams tokens over direct transport and resolves with "direct"', async () => {
    fetchMock.mockResolvedValueOnce(
      new Response(ndjsonBody([{ message: { content: 'Hel' } }, { message: { content: 'lo' } }]), {
        status: 200,
      })
    );

    const tokens: string[] = [];
    const transport = await streamChat({
      settings: { ...settings, transport: 'direct' },
      messages: [{ role: 'user', content: 'hi' }],
      onToken: t => tokens.push(t),
    });

    expect(transport).toBe('direct');
    expect(tokens.join('')).toBe('Hello');
    expect(fetchMock).toHaveBeenCalledWith(
      'http://ollama.local:11434/api/chat',
      expect.objectContaining({ method: 'POST' })
    );
  });

  it('reassembles an NDJSON line that arrives split across two chunks', async () => {
    const line = `${JSON.stringify({ message: { content: 'partial-line' } })}\n`;
    const mid = Math.floor(line.length / 2);
    fetchMock.mockResolvedValueOnce(
      new Response(chunkedBody([line.slice(0, mid), line.slice(mid)]), { status: 200 })
    );

    const tokens: string[] = [];
    await streamChat({
      settings: { ...settings, transport: 'direct' },
      messages: [],
      onToken: t => tokens.push(t),
    });

    expect(tokens.join('')).toBe('partial-line');
  });

  it('falls back to a non-streaming request on the same transport if streaming fails', async () => {
    fetchMock
      .mockRejectedValueOnce(new Error('stream connection reset'))
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ message: { content: 'fallback answer' } }), { status: 200 })
      );

    const tokens: string[] = [];
    const transport = await streamChat({
      settings: { ...settings, transport: 'direct' },
      messages: [],
      onToken: t => tokens.push(t),
    });

    expect(transport).toBe('direct');
    expect(tokens).toEqual(['fallback answer']);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('rejects with the most recent error when both stream and non-stream fail on the only configured transport', async () => {
    fetchMock
      .mockResolvedValueOnce(new Response(ndjsonBody([{ error: 'model not found' }]), { status: 200 }))
      .mockRejectedValueOnce(new Error('non-stream also down'));

    await expect(
      streamChat({
        settings: { ...settings, transport: 'direct' },
        messages: [],
        onToken: () => undefined,
      })
    ).rejects.toThrow('non-stream also down');
  });

  it('moves on to the proxy transport when direct fails entirely, in "auto" mode', async () => {
    fetchMock
      .mockRejectedValueOnce(new Error('direct stream unreachable'))
      .mockRejectedValueOnce(new Error('direct non-stream unreachable'))
      .mockResolvedValueOnce(new Response(ndjsonBody([{ message: { content: 'via proxy stream' } }]), { status: 200 }));

    const tokens: string[] = [];
    const transport = await streamChat({
      settings: { ...settings, transport: 'auto' },
      messages: [],
      onToken: t => tokens.push(t),
    });

    expect(transport).toBe('proxy');
    expect(tokens).toEqual(['via proxy stream']);
    expect(fetchMock).toHaveBeenCalledTimes(3);
  });

  it('uses ApiProxy.request for the non-streaming proxy fallback', async () => {
    fetchMock.mockRejectedValueOnce(new Error('proxy stream failed'));
    vi.mocked(ApiProxy.request).mockResolvedValueOnce({ message: { content: 'via proxy' } });

    const tokens: string[] = [];
    const transport = await streamChat({
      settings: { ...settings, transport: 'proxy' },
      messages: [],
      onToken: t => tokens.push(t),
    });

    expect(transport).toBe('proxy');
    expect(tokens).toEqual(['via proxy']);
    expect(ApiProxy.request).toHaveBeenCalledTimes(1);
  });

  it('never touches the proxy when transport is forced to "direct"', async () => {
    fetchMock
      .mockRejectedValueOnce(new Error('stream down'))
      .mockRejectedValueOnce(new Error('non-stream down too'));

    await expect(
      streamChat({
        settings: { ...settings, transport: 'direct' },
        messages: [],
        onToken: () => undefined,
      })
    ).rejects.toThrow('non-stream down too');
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(ApiProxy.request).not.toHaveBeenCalled();
  });
});

describe('pingModel', () => {
  it('reports loaded:true when the configured model is in /api/ps', async () => {
    fetchMock.mockResolvedValueOnce(
      new Response(JSON.stringify({ models: [{ name: 'gemma4:26b' }] }), { status: 200 })
    );

    const status = await pingModel({ ...settings, transport: 'direct' });
    expect(status).toEqual({ loaded: true, name: 'gemma4:26b', transport: 'direct' });
  });

  it('matches on either the "name" or "model" field Ollama uses across versions', async () => {
    fetchMock.mockResolvedValueOnce(
      new Response(JSON.stringify({ models: [{ model: 'gemma4:26b' }] }), { status: 200 })
    );

    const status = await pingModel({ ...settings, transport: 'direct' });
    expect(status.loaded).toBe(true);
  });

  it('reports loaded:false when the model list does not include it', async () => {
    fetchMock.mockResolvedValueOnce(new Response(JSON.stringify({ models: [] }), { status: 200 }));

    const status = await pingModel({ ...settings, transport: 'direct' });
    expect(status.loaded).toBe(false);
  });

  it('surfaces a descriptive error when Ollama responds with a non-2xx status', async () => {
    fetchMock.mockResolvedValueOnce(new Response('boom', { status: 500 }));

    const status = await pingModel({ ...settings, transport: 'direct' });
    expect(status.loaded).toBe(false);
    expect(status.error).toMatch(/500/);
  });

  it('surfaces the underlying error when unreachable on every transport', async () => {
    fetchMock.mockRejectedValue(new Error('ECONNREFUSED'));

    const status = await pingModel({ ...settings, transport: 'direct' });
    expect(status.loaded).toBe(false);
    expect(status.error).toMatch(/ECONNREFUSED/);
  });
});

import { ApiProxy, Utils } from '@kinvolk/headlamp-plugin/lib';
import { PluginSettings, Transport } from '../settings/types';

export interface ChatMessage {
  role: 'system' | 'user' | 'assistant';
  content: string;
}

export interface ModelStatus {
  loaded: boolean;
  name?: string;
  transport: Transport;
  error?: string;
}

export interface StreamChatOptions {
  settings: PluginSettings;
  messages: ChatMessage[];
  onToken: (chunk: string) => void;
  signal?: AbortSignal;
}

function timeoutSignal(seconds: number, parent?: AbortSignal): AbortSignal {
  const extra = AbortSignal.timeout(Math.max(1, seconds) * 1000);
  if (!parent) {
    return extra;
  }
  if (typeof AbortSignal.any === 'function') {
    return AbortSignal.any([parent, extra]);
  }
  return extra;
}

/** Which transport(s) to try, in order. `auto` means "LAN first, kube
 * service proxy as fallback" — see streamChat's doc comment for why. */
function transportOrder(settings: PluginSettings): Array<'direct' | 'proxy'> {
  if (settings.transport === 'proxy') {
    return ['proxy'];
  }
  if (settings.transport === 'direct') {
    return ['direct'];
  }
  return ['direct', 'proxy'];
}

function findModel(models: any[], name: string): any {
  return models.find((m: any) => m.name === name || m.model === name);
}

function chatBody(settings: PluginSettings, messages: ChatMessage[], stream: boolean) {
  return {
    model: settings.model,
    messages,
    stream,
    keep_alive: settings.keepAlive,
    options: { temperature: 0 },
  };
}

function proxyApiPath(settings: PluginSettings, apiPath: string): string {
  const ns = encodeURIComponent(settings.proxyNamespace);
  const svc = encodeURIComponent(settings.proxyService);
  const port = settings.proxyPort;
  const suffix = apiPath.startsWith('/') ? apiPath : `/${apiPath}`;
  return `/api/v1/namespaces/${ns}/services/http:${svc}:${port}/proxy${suffix}`;
}

function clusterPrefixed(path: string): string {
  const cluster = Utils.getCluster();
  const trimmed = path.replace(/^\//, '');
  return cluster ? `/clusters/${encodeURIComponent(cluster)}/${trimmed}` : `/${trimmed}`;
}

async function directFetch(
  settings: PluginSettings,
  apiPath: string,
  init: RequestInit
): Promise<Response> {
  const base = settings.baseUrl.replace(/\/$/, '');
  const res = await fetch(`${base}${apiPath}`, init);
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`Ollama ${apiPath} ${res.status}: ${text.slice(0, 200)}`);
  }
  return res;
}

async function proxyFetch(
  settings: PluginSettings,
  apiPath: string,
  init: RequestInit
): Promise<Response> {
  const url = clusterPrefixed(proxyApiPath(settings, apiPath));
  const res = await fetch(url, { ...init, credentials: 'same-origin' });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`Ollama proxy ${apiPath} ${res.status}: ${text.slice(0, 200)}`);
  }
  return res;
}

async function consumeNdjson(
  body: ReadableStream<Uint8Array> | null,
  onToken: (chunk: string) => void
): Promise<void> {
  if (!body) {
    throw new Error('Ollama returned an empty body');
  }
  const reader = body.getReader();
  const decoder = new TextDecoder();
  let buf = '';
  for (;;) {
    const { value, done } = await reader.read();
    if (done) {
      break;
    }
    buf += decoder.decode(value, { stream: true });
    const lines = buf.split('\n');
    buf = lines.pop() || '';
    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed) {
        continue;
      }
      try {
        const ev = JSON.parse(trimmed);
        const piece = ev?.message?.content;
        if (piece) {
          onToken(piece);
        }
        if (ev?.error) {
          throw new Error(String(ev.error));
        }
      } catch (err) {
        if (err instanceof SyntaxError) {
          continue;
        }
        throw err;
      }
    }
  }
}

async function tryStream(
  settings: PluginSettings,
  transport: 'direct' | 'proxy',
  messages: ChatMessage[],
  onToken: (chunk: string) => void,
  signal: AbortSignal
): Promise<void> {
  const init: RequestInit = {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(chatBody(settings, messages, true)),
    signal,
  };
  const res =
    transport === 'direct'
      ? await directFetch(settings, '/api/chat', init)
      : await proxyFetch(settings, '/api/chat', init);
  await consumeNdjson(res.body, onToken);
}

async function tryNonStream(
  settings: PluginSettings,
  transport: 'direct' | 'proxy',
  messages: ChatMessage[],
  onToken: (chunk: string) => void,
  signal: AbortSignal
): Promise<void> {
  const payload = chatBody(settings, messages, false);
  if (transport === 'direct') {
    const res = await directFetch(settings, '/api/chat', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
      signal,
    });
    const json = await res.json();
    const text = json?.message?.content || '';
    if (text) {
      onToken(text);
    }
    return;
  }
  const json = await ApiProxy.request(proxyApiPath(settings, '/api/chat'), {
    method: 'POST',
    body: JSON.stringify(payload),
    headers: { 'Content-Type': 'application/json' },
  });
  const text = json?.message?.content || '';
  if (text) {
    onToken(text);
  }
}

/**
 * Stream one /api/chat turn. `auto` tries LAN first (CORS probe on 2026-09-06
 * showed Ollama reflecting Origin), then kube service proxy.
 *
 * For each transport in order: try a real stream first, and only if that
 * fails (a proxy that buffers the whole response, a server that rejects
 * `stream: true`, ...) fall back to one non-streaming request on the *same*
 * transport before giving up on it and moving to the next. `lastErr` always
 * holds the most recent failure, so if every transport is unreachable the
 * error the caller sees is the last, most specific one — usually the more
 * useful of the two forms for a given transport.
 */
export async function streamChat(opts: StreamChatOptions): Promise<Transport> {
  const { settings, messages, onToken } = opts;
  const signal = timeoutSignal(settings.timeoutSeconds, opts.signal);

  let lastErr: unknown;
  for (const transport of transportOrder(settings)) {
    try {
      await tryStream(settings, transport, messages, onToken, signal);
      return transport;
    } catch (err) {
      lastErr = err;
      try {
        await tryNonStream(settings, transport, messages, onToken, signal);
        return transport;
      } catch (err2) {
        lastErr = err2;
      }
    }
  }
  throw lastErr instanceof Error ? lastErr : new Error(String(lastErr));
}

export async function pingModel(settings: PluginSettings): Promise<ModelStatus> {
  let lastErr: unknown;
  for (const transport of transportOrder(settings)) {
    try {
      const json =
        transport === 'direct'
          ? await (await directFetch(settings, '/api/ps', { method: 'GET' })).json()
          : await ApiProxy.request(proxyApiPath(settings, '/api/ps'));
      const hit = findModel(json?.models || [], settings.model);
      return { loaded: Boolean(hit), name: hit?.name || hit?.model, transport };
    } catch (err) {
      lastErr = err;
    }
  }
  return {
    loaded: false,
    transport: settings.transport === 'proxy' ? 'proxy' : 'direct',
    error: lastErr instanceof Error ? lastErr.message : String(lastErr),
  };
}

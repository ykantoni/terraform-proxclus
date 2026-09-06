export type Transport = 'auto' | 'direct' | 'proxy';

export interface PluginSettings {
  baseUrl: string;
  model: string;
  timeoutSeconds: number;
  keepAlive: string;
  transport: Transport;
  proxyNamespace: string;
  proxyService: string;
  proxyPort: number;
}

export const PLUGIN_NAME = 'cluster-chat';

export const DEFAULT_SETTINGS: PluginSettings = {
  baseUrl: 'http://192.168.1.63:11434',
  model: 'gemma4:26b',
  timeoutSeconds: 300,
  keepAlive: '30m',
  transport: 'auto',
  proxyNamespace: 'ollama',
  proxyService: 'ollama',
  proxyPort: 11434,
};

export function mergeSettings(partial?: Partial<PluginSettings> | null): PluginSettings {
  return { ...DEFAULT_SETTINGS, ...(partial || {}) };
}

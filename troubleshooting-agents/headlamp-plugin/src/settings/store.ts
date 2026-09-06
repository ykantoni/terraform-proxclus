import { ConfigStore } from '@kinvolk/headlamp-plugin/lib';
import { DEFAULT_SETTINGS, mergeSettings, PLUGIN_NAME, PluginSettings } from './types';

export const store = new ConfigStore<PluginSettings>(PLUGIN_NAME);

export function readSettings(): PluginSettings {
  return mergeSettings(store.get() || DEFAULT_SETTINGS);
}

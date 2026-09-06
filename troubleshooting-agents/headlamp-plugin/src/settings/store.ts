import { ConfigStore } from '@kinvolk/headlamp-plugin/lib';
import { PLUGIN_NAME, PluginSettings } from './types';

export const store = new ConfigStore<PluginSettings>(PLUGIN_NAME);

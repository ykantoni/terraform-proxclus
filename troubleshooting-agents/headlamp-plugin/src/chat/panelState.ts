import { createModuleState } from './moduleState';

const panelOpen = createModuleState(false);

export const isChatPanelOpen = panelOpen.get;
export const setChatPanelOpen = panelOpen.set;
export const useChatPanelOpen = panelOpen.useValue;

export function toggleChatPanel() {
  panelOpen.set(!panelOpen.get());
}

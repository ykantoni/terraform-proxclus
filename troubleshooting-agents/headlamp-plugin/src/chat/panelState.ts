import { useEffect, useState } from 'react';

type Listener = () => void;

let open = false;
const listeners = new Set<Listener>();

function notify() {
  listeners.forEach(l => l());
}

export function isChatPanelOpen(): boolean {
  return open;
}

export function setChatPanelOpen(next: boolean) {
  if (open === next) {
    return;
  }
  open = next;
  notify();
}

export function toggleChatPanel() {
  setChatPanelOpen(!open);
}

export function useChatPanelOpen(): boolean {
  const [value, setValue] = useState(open);
  useEffect(() => {
    const listener = () => setValue(open);
    listeners.add(listener);
    return () => {
      listeners.delete(listener);
    };
  }, []);
  return value;
}

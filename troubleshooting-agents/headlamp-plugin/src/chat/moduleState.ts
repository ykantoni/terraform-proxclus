import { useEffect, useState } from 'react';

/**
 * Minimal shared mutable value with a React hook to subscribe to it — for
 * state that needs to be read or written from outside React (e.g. a
 * details-view button opening the chat panel) as well as from components.
 * `panelState.ts` and `askTarget.ts` are both one of these; this factors
 * out the get/set/subscribe boilerplate they'd otherwise each repeat.
 */
export function createModuleState<T>(initial: T) {
  let value = initial;
  const listeners = new Set<() => void>();

  function get(): T {
    return value;
  }

  function set(next: T): void {
    if (value === next) {
      return;
    }
    value = next;
    listeners.forEach(l => l());
  }

  function useValue(): T {
    const [state, setState] = useState(value);
    useEffect(() => {
      const listener = () => setState(value);
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    }, []);
    return state;
  }

  return { get, set, useValue };
}

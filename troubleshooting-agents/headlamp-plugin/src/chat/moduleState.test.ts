import { act, renderHook } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { createModuleState } from './moduleState';

describe('createModuleState', () => {
  it('get/set update the value and notify subscribed hooks', () => {
    const state = createModuleState(1);
    const { result } = renderHook(() => state.useValue());
    expect(result.current).toBe(1);
    expect(state.get()).toBe(1);

    act(() => {
      state.set(2);
    });

    expect(result.current).toBe(2);
    expect(state.get()).toBe(2);
  });

  it('does not notify listeners when set to the same value', () => {
    const state = createModuleState('a');
    const renders = vi.fn();
    const { result } = renderHook(() => {
      renders();
      return state.useValue();
    });
    renders.mockClear();

    act(() => {
      state.set('a');
    });

    expect(renders).not.toHaveBeenCalled();
    expect(result.current).toBe('a');
  });

  it('keeps two independent hook subscriptions in sync', () => {
    const state = createModuleState(false);
    const a = renderHook(() => state.useValue());
    const b = renderHook(() => state.useValue());

    act(() => {
      state.set(true);
    });

    expect(a.result.current).toBe(true);
    expect(b.result.current).toBe(true);
  });
});

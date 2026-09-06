import { act, renderHook } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { useElapsedSeconds } from './useElapsedSeconds';

describe('useElapsedSeconds', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('stays at 0 while inactive', () => {
    const { result } = renderHook(() => useElapsedSeconds(false));
    expect(result.current).toBe(0);
  });

  it('counts up while active, holds when deactivated, and resets on reactivation', () => {
    const { result, rerender } = renderHook(({ active }) => useElapsedSeconds(active), {
      initialProps: { active: true },
    });

    act(() => {
      vi.advanceTimersByTime(1200);
    });
    expect(result.current).toBe(1);

    rerender({ active: false });
    expect(result.current).toBe(1); // stopping doesn't reset it

    rerender({ active: true });
    expect(result.current).toBe(0); // starting again does

    act(() => {
      vi.advanceTimersByTime(600);
    });
    expect(result.current).toBe(1);
  });
});

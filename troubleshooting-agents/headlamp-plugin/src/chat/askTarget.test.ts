import { act, renderHook } from '@testing-library/react';
import { afterEach, describe, expect, it } from 'vitest';
import { setAskTarget, useAskTarget } from './askTarget';

describe('askTarget', () => {
  afterEach(() => {
    act(() => {
      setAskTarget(undefined);
    });
  });

  it('starts undefined and reflects the resource set by AskAboutSection', () => {
    const { result } = renderHook(() => useAskTarget());
    expect(result.current).toBeUndefined();

    act(() => {
      setAskTarget({ kind: 'Pod', name: 'ollama-x', namespace: 'ollama' });
    });

    expect(result.current).toEqual({ kind: 'Pod', name: 'ollama-x', namespace: 'ollama' });
  });
});

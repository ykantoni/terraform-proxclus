import { useEffect, useRef, useState } from 'react';

const TICK_MS = 500;

/**
 * Live seconds-elapsed counter, ticking every TICK_MS while `active`, reset
 * to 0 each time `active` turns on. Used for the "waiting on model (12s)"
 * style progress labels without every caller managing its own interval.
 */
export function useElapsedSeconds(active: boolean): number {
  const [elapsed, setElapsed] = useState(0);
  const timerRef = useRef<number | null>(null);

  useEffect(() => {
    if (!active) {
      if (timerRef.current) {
        window.clearInterval(timerRef.current);
        timerRef.current = null;
      }
      return;
    }
    setElapsed(0);
    const t0 = Date.now();
    timerRef.current = window.setInterval(() => {
      setElapsed(Math.round((Date.now() - t0) / 1000));
    }, TICK_MS);
    return () => {
      if (timerRef.current) {
        window.clearInterval(timerRef.current);
      }
    };
  }, [active]);

  return elapsed;
}

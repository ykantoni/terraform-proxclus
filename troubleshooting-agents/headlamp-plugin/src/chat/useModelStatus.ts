import { useEffect, useState } from 'react';
import { ModelStatus, pingModel } from '../ollama/client';
import { PluginSettings } from '../settings/types';

/**
 * Reachability/loaded-state of the configured model, refreshed whenever the
 * connection settings change. `null` while the first check is in flight.
 */
export function useModelStatus(settings: PluginSettings): ModelStatus | null {
  const [status, setStatus] = useState<ModelStatus | null>(null);

  useEffect(() => {
    let cancelled = false;
    pingModel(settings)
      .then(result => {
        if (!cancelled) {
          setStatus(result);
        }
      })
      .catch(() => undefined);
    return () => {
      cancelled = true;
    };
    // settings identity changes every render if we depend on the object
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [settings.baseUrl, settings.model, settings.transport]);

  return status;
}

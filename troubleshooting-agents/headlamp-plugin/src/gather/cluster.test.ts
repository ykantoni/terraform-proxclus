import { describe, expect, it } from 'vitest';
import { clusterFromLocation } from './cluster';

describe('clusterFromLocation', () => {
  it('reads /c/<name> from a Headlamp cluster path', () => {
    expect(clusterFromLocation('/c/talos/cluster-chat')).toBe('talos');
    expect(clusterFromLocation('#/c/talos/pods')).toBe('talos');
    expect(clusterFromLocation('/c/talos+other/nodes')).toBe('talos');
  });

  it('returns null when no cluster segment is present', () => {
    expect(clusterFromLocation('/')).toBeNull();
    expect(clusterFromLocation('/settings/plugins')).toBeNull();
  });
});

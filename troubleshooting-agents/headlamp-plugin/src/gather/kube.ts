import { ApiProxy, K8s, Utils } from '@kinvolk/headlamp-plugin/lib';
import { clusterFromLocation } from './cluster';
import { assembleSnapshot, currentResourceFromKube, emptySnapshot, eventFromKube } from './format';
import { ClusterSnapshot, CurrentResourceRef, EventFact } from './types';

function resolveCluster(preferred?: string | null): string | null {
  if (preferred) {
    return preferred;
  }
  try {
    const fromUtil = Utils.getCluster();
    if (fromUtil) {
      return fromUtil;
    }
  } catch {
    // older Headlamp
  }
  return clusterFromLocation();
}

async function kubeGet(
  path: string,
  cluster: string,
  queryParams?: Record<string, string | number>
): Promise<any> {
  return ApiProxy.request(path, { cluster }, true, true, queryParams);
}

async function tryList(
  path: string,
  label: string,
  cluster: string,
  queryParams?: Record<string, string | number>
): Promise<{ items: any[]; error?: string }> {
  try {
    const body = await kubeGet(path, cluster, queryParams);
    return { items: body?.items || [] };
  } catch (err) {
    return { items: [], error: `${label}: ${err instanceof Error ? err.message : String(err)}` };
  }
}

function resourcePath(ref: CurrentResourceRef): string | null {
  const name = encodeURIComponent(ref.name);
  const ns = ref.namespace ? encodeURIComponent(ref.namespace) : '';
  switch (ref.kind) {
    case 'Node':
      return `/api/v1/nodes/${name}`;
    case 'Pod':
      return ns ? `/api/v1/namespaces/${ns}/pods/${name}` : null;
    case 'Deployment':
      return ns ? `/apis/apps/v1/namespaces/${ns}/deployments/${name}` : null;
    case 'DaemonSet':
      return ns ? `/apis/apps/v1/namespaces/${ns}/daemonsets/${name}` : null;
    case 'StatefulSet':
      return ns ? `/apis/apps/v1/namespaces/${ns}/statefulsets/${name}` : null;
    case 'ReplicaSet':
      return ns ? `/apis/apps/v1/namespaces/${ns}/replicasets/${name}` : null;
    default:
      return null;
  }
}

async function loadCurrent(
  ref: CurrentResourceRef,
  cluster: string
): Promise<{
  current?: ReturnType<typeof currentResourceFromKube>;
  error?: string;
}> {
  const path = resourcePath(ref);
  if (!path) {
    return { error: `unsupported current resource ${ref.kind}` };
  }
  try {
    const obj = await kubeGet(path, cluster);
    let events: EventFact[] = [];
    try {
      const evPath = ref.namespace
        ? `/api/v1/namespaces/${encodeURIComponent(ref.namespace)}/events`
        : `/api/v1/events`;
      const evBody = await kubeGet(evPath, cluster, {
        fieldSelector: `involvedObject.name=${ref.name}`,
      });
      events = (evBody?.items || []).map(eventFromKube);
    } catch {
      // object events are optional
    }
    return { current: currentResourceFromKube(ref.kind, obj, events) };
  } catch (err) {
    return { error: `current ${ref.kind}: ${err instanceof Error ? err.message : String(err)}` };
  }
}

/** Read-only cluster snapshot. Never fetches Secrets. */
export async function gatherSnapshot(
  current?: CurrentResourceRef,
  preferredCluster?: string | null
): Promise<ClusterSnapshot> {
  const cluster = resolveCluster(preferredCluster);
  if (!cluster) {
    return emptySnapshot(
      [
        'No Headlamp cluster is selected. Open a cluster (sidebar should show Workloads/Nodes), then ask again. The gatherer must call /clusters/<name>/api/v1/...; without a cluster name Headlamp returns Not Found.',
      ],
      undefined
    );
  }

  const errors: string[] = [];
  const [nodes, pods, events] = await Promise.all([
    tryList('/api/v1/nodes', 'nodes', cluster),
    tryList('/api/v1/pods', 'pods', cluster),
    tryList('/api/v1/events', 'events', cluster, { limit: 80 }),
  ]);
  errors.push(...[nodes.error, pods.error, events.error].filter((e): e is string => Boolean(e)));

  let currentFact;
  if (current?.kind && current.name) {
    const loaded = await loadCurrent(current, cluster);
    currentFact = loaded.current;
    if (loaded.error) {
      errors.push(loaded.error);
    }
  }

  return assembleSnapshot({
    cluster,
    nodes: nodes.items,
    pods: pods.items,
    events: events.items,
    current: currentFact,
    errors,
  });
}

export function useGatherCluster(): string | null {
  const selected = K8s.useSelectedClusters();
  return resolveCluster(selected?.[0] || null);
}

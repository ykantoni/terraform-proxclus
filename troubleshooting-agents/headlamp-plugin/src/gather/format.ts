import {
  ClusterSnapshot,
  CurrentResourceFact,
  EventFact,
  NodeFact,
  PodFact,
  SNAPSHOT_CAPS,
} from './types';

const BAD_WAITING = new Set([
  'CrashLoopBackOff',
  'ImagePullBackOff',
  'ErrImagePull',
  'CreateContainerConfigError',
  'InvalidImageName',
  'RunContainerError',
  'OOMKilled',
]);

function labelsToRoles(labels: Record<string, string> | undefined): string[] {
  if (!labels) {
    return [];
  }
  return Object.keys(labels)
    .filter(k => k.startsWith('node-role.kubernetes.io/'))
    .map(k => k.replace('node-role.kubernetes.io/', '') || 'node')
    .slice(0, 4);
}

function isReady(conditions: any[] | undefined): boolean {
  const ready = (conditions || []).find((c: any) => c.type === 'Ready');
  return ready?.status === 'True';
}

export function nodeFromKube(item: any): NodeFact {
  const status = item.status || {};
  const alloc = status.allocatable || {};
  const conditions = (status.conditions || [])
    .filter((c: any) => c.status === 'True' && c.type !== 'Ready')
    .map((c: any) => c.type);
  return {
    name: item.metadata?.name || 'unknown',
    ready: isReady(status.conditions),
    roles: labelsToRoles(item.metadata?.labels),
    conditions,
    taints: (item.spec?.taints || []).map((t: any) => `${t.key}${t.effect ? `:${t.effect}` : ''}`),
    allocatable: {
      cpu: alloc.cpu,
      memory: alloc.memory,
      gpu: alloc['nvidia.com/gpu'],
    },
  };
}

function containerReasons(pod: any): string[] {
  const statuses = [
    ...(pod.status?.containerStatuses || []),
    ...(pod.status?.initContainerStatuses || []),
  ];
  const reasons: string[] = [];
  for (const cs of statuses) {
    const waiting = cs.state?.waiting?.reason;
    const last = cs.lastState?.terminated?.reason;
    if (waiting) {
      reasons.push(waiting);
    }
    if (last) {
      reasons.push(last);
    }
  }
  return [...new Set(reasons)];
}

function restartCount(pod: any): number {
  const statuses = pod.status?.containerStatuses || [];
  return statuses.reduce((sum: number, cs: any) => sum + (cs.restartCount || 0), 0);
}

function isPodReady(pod: any): boolean {
  const cond = (pod.status?.conditions || []).find((c: any) => c.type === 'Ready');
  if (cond) {
    return cond.status === 'True';
  }
  return pod.status?.phase === 'Succeeded';
}

export function podFromKube(item: any): PodFact {
  return {
    namespace: item.metadata?.namespace || 'default',
    name: item.metadata?.name || 'unknown',
    phase: item.status?.phase || 'Unknown',
    ready: isPodReady(item),
    restarts: restartCount(item),
    node: item.spec?.nodeName,
    reasons: containerReasons(item),
  };
}

export function isUnhealthyPod(pod: PodFact): boolean {
  if (['Failed', 'Pending', 'Unknown'].includes(pod.phase)) {
    return true;
  }
  if (pod.reasons.some(r => BAD_WAITING.has(r))) {
    return true;
  }
  if (pod.phase === 'Running' && !pod.ready) {
    return true;
  }
  return false;
}

export function eventFromKube(item: any): EventFact {
  const involved = item.involvedObject || {};
  const object =
    involved.kind && involved.name
      ? `${involved.kind}/${involved.namespace ? `${involved.namespace}/` : ''}${involved.name}`
      : undefined;
  const message = String(item.message || '').slice(0, SNAPSHOT_CAPS.eventMessageChars);
  return {
    namespace: item.metadata?.namespace,
    name: item.metadata?.name,
    type: item.type || 'Normal',
    reason: item.reason || '',
    message,
    object,
    lastSeen: item.lastTimestamp || item.eventTime || item.metadata?.creationTimestamp,
  };
}

export function isWarningEvent(ev: EventFact): boolean {
  return ev.type === 'Warning';
}

const DROP_ANNOTATION_KEYS = [/token/i, /secret/i, /password/i, /kubeconfig/i];

function trimObject(obj: any): Record<string, unknown> {
  const metadata = obj.metadata || {};
  const annotations = metadata.annotations || {};
  const safeAnnotations: Record<string, string> = {};
  for (const [k, v] of Object.entries(annotations)) {
    if (DROP_ANNOTATION_KEYS.some(re => re.test(k))) {
      continue;
    }
    safeAnnotations[k] = String(v).slice(0, 120);
  }

  const summary: Record<string, unknown> = {
    kind: obj.kind,
    name: metadata.name,
    namespace: metadata.namespace,
    labels: metadata.labels,
    annotations: Object.keys(safeAnnotations).length ? safeAnnotations : undefined,
    spec: stripHeavy(obj.spec),
    status: stripHeavy(obj.status),
  };
  const encoded = JSON.stringify(summary);
  if (encoded.length > SNAPSHOT_CAPS.summaryChars) {
    return {
      kind: obj.kind,
      name: metadata.name,
      namespace: metadata.namespace,
      statusPhase: obj.status?.phase,
      conditions: (obj.status?.conditions || []).slice(0, 6),
      truncated: true,
    };
  }
  return summary;
}

function stripHeavy(value: unknown): unknown {
  if (!value || typeof value !== 'object') {
    return value;
  }
  if (Array.isArray(value)) {
    return value.slice(0, 20).map(stripHeavy);
  }
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
    if (k === 'managedFields' || k === 'data' || k === 'binaryData' || k === 'stringData') {
      continue;
    }
    out[k] = stripHeavy(v);
  }
  return out;
}

export function currentResourceFromKube(
  kind: string,
  obj: any,
  events: EventFact[]
): CurrentResourceFact {
  return {
    kind,
    name: obj.metadata?.name || 'unknown',
    namespace: obj.metadata?.namespace,
    summary: trimObject({ ...obj, kind }),
    events: events.filter(isWarningEvent).slice(0, 8),
  };
}

export function emptySnapshot(errors: string[] = [], cluster?: string): ClusterSnapshot {
  return {
    gatheredAt: new Date().toISOString(),
    cluster,
    errors,
    nodes: [],
    unhealthyPods: [],
    warningEvents: [],
  };
}

export function assembleSnapshot(parts: {
  cluster?: string;
  nodes?: any[];
  pods?: any[];
  events?: any[];
  current?: CurrentResourceFact;
  errors?: string[];
}): ClusterSnapshot {
  const nodes = (parts.nodes || []).map(nodeFromKube).slice(0, SNAPSHOT_CAPS.nodes);
  const unhealthyPods = (parts.pods || [])
    .map(podFromKube)
    .filter(isUnhealthyPod)
    .slice(0, SNAPSHOT_CAPS.unhealthyPods);
  const warningEvents = (parts.events || [])
    .map(eventFromKube)
    .filter(isWarningEvent)
    .sort((a, b) => String(b.lastSeen || '').localeCompare(String(a.lastSeen || '')))
    .slice(0, SNAPSHOT_CAPS.warningEvents);

  return {
    gatheredAt: new Date().toISOString(),
    cluster: parts.cluster,
    errors: parts.errors || [],
    nodes,
    unhealthyPods,
    warningEvents,
    currentResource: parts.current,
  };
}

export function formatSnapshot(snapshot: ClusterSnapshot): string {
  return JSON.stringify(snapshot, null, 2);
}

export function snapshotPreviewLines(snapshot: ClusterSnapshot): string[] {
  const lines = [
    snapshot.cluster ? `cluster: ${snapshot.cluster}` : 'cluster: (none)',
    `nodes: ${snapshot.nodes.length} (${snapshot.nodes.filter(n => n.ready).length} Ready)`,
    `unhealthy pods: ${snapshot.unhealthyPods.length}`,
    `warning events: ${snapshot.warningEvents.length}`,
  ];
  if (snapshot.currentResource) {
    const r = snapshot.currentResource;
    lines.push(
      `current: ${r.kind}/${r.namespace ? `${r.namespace}/` : ''}${r.name}`
    );
  }
  if (snapshot.errors.length) {
    lines.push(`errors: ${snapshot.errors.join('; ')}`);
  }
  return lines;
}

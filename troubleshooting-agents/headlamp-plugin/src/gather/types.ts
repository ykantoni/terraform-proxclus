export interface NodeFact {
  name: string;
  ready: boolean;
  roles: string[];
  conditions: string[];
  taints: string[];
  allocatable: {
    cpu?: string;
    memory?: string;
    gpu?: string;
  };
}

export interface PodFact {
  namespace: string;
  name: string;
  phase: string;
  ready: boolean;
  restarts: number;
  node?: string;
  reasons: string[];
}

export interface EventFact {
  namespace?: string;
  name?: string;
  type: string;
  reason: string;
  message: string;
  object?: string;
  lastSeen?: string;
}

export interface CurrentResourceFact {
  kind: string;
  name: string;
  namespace?: string;
  summary: Record<string, unknown>;
  events: EventFact[];
}

export interface ClusterSnapshot {
  gatheredAt: string;
  cluster?: string;
  errors: string[];
  nodes: NodeFact[];
  unhealthyPods: PodFact[];
  warningEvents: EventFact[];
  currentResource?: CurrentResourceFact;
}

export interface CurrentResourceRef {
  kind: string;
  name: string;
  namespace?: string;
}

export const SNAPSHOT_CAPS = {
  nodes: 16,
  unhealthyPods: 20,
  warningEvents: 25,
  eventMessageChars: 240,
  summaryChars: 4000,
};

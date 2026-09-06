import { describe, expect, it } from 'vitest';
import {
  assembleSnapshot,
  isUnhealthyPod,
  nodeFromKube,
  podFromKube,
  snapshotPreviewLines,
} from './format';

const readyNode = {
  metadata: {
    name: '192.168.1.201',
    labels: { 'node-role.kubernetes.io/control-plane': '' },
  },
  spec: { taints: [{ key: 'node-role.kubernetes.io/control-plane', effect: 'NoSchedule' }] },
  status: {
    conditions: [{ type: 'Ready', status: 'True' }],
    allocatable: { cpu: '4', memory: '8Gi', 'nvidia.com/gpu': '1' },
  },
};

const crashloopPod = {
  metadata: { name: 'ollama-x', namespace: 'ollama' },
  spec: { nodeName: '192.168.1.201' },
  status: {
    phase: 'Running',
    conditions: [{ type: 'Ready', status: 'False' }],
    containerStatuses: [
      {
        restartCount: 7,
        state: { waiting: { reason: 'CrashLoopBackOff' } },
        lastState: { terminated: { reason: 'OOMKilled' } },
      },
    ],
  },
};

const healthyPod = {
  metadata: { name: 'coredns', namespace: 'kube-system' },
  spec: { nodeName: '192.168.1.202' },
  status: {
    phase: 'Running',
    conditions: [{ type: 'Ready', status: 'True' }],
    containerStatuses: [{ restartCount: 0, state: { running: {} } }],
  },
};

describe('gatherer', () => {
  it('reads node Ready, roles, and GPU allocatable', () => {
    const n = nodeFromKube(readyNode);
    expect(n.ready).toBe(true);
    expect(n.roles).toContain('control-plane');
    expect(n.allocatable.gpu).toBe('1');
  });

  it('flags CrashLoopBackOff / OOMKilled pods and ignores healthy ones', () => {
    expect(isUnhealthyPod(podFromKube(crashloopPod))).toBe(true);
    expect(isUnhealthyPod(podFromKube(healthyPod))).toBe(false);
    const snap = assembleSnapshot({
      nodes: [readyNode],
      pods: [crashloopPod, healthyPod],
      events: [
        {
          type: 'Warning',
          reason: 'BackOff',
          message: 'Back-off restarting failed container',
          involvedObject: { kind: 'Pod', namespace: 'ollama', name: 'ollama-x' },
        },
      ],
    });
    expect(snap.unhealthyPods).toHaveLength(1);
    expect(snap.unhealthyPods[0].reasons).toContain('CrashLoopBackOff');
    expect(snap.unhealthyPods[0].reasons).toContain('OOMKilled');
    expect(snap.warningEvents[0].reason).toBe('BackOff');
    expect(snapshotPreviewLines(snap).join(' ')).toMatch(/unhealthy pods: 1/);
  });

  it('never copies Secret-like annotation keys into the current-resource summary', () => {
    const snap = assembleSnapshot({
      current: {
        kind: 'Pod',
        name: 'x',
        namespace: 'ns',
        summary: { kind: 'Pod', name: 'x' },
        events: [],
      },
    });
    expect(JSON.stringify(snap)).not.toMatch(/password|token|kubeconfig/i);
  });
});

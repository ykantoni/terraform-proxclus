#!/usr/bin/env node
/**
 * Walk the three v1 scenarios against live kubectl + Ollama.
 * Does not need Headlamp — same snapshot shape and system prompt as the plugin.
 *
 *   node scripts/manual-scenarios.mjs
 */
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)));
const OLLAMA = process.env.OLLAMA_BASE_URL || 'http://192.168.1.63:11434';
const MODEL = process.env.OLLAMA_MODEL || 'gemma4:26b';
const KUBECONFIG =
  process.env.KUBECONFIG_PATH ||
  process.env.KUBECONFIG ||
  join(ROOT, '..', '..', '.kube', 'config');

function loadPrompt() {
  const src = readFileSync(join(ROOT, 'src', 'prompt', 'talos.ts'), 'utf8');
  const m = src.match(/export const TALOS_SYSTEM_PROMPT = `([\s\S]*?)`;/);
  if (!m) {
    throw new Error('could not parse TALOS_SYSTEM_PROMPT');
  }
  return m[1];
}

function kubectlJson(args) {
  const out = execFileSync('kubectl', ['--kubeconfig', KUBECONFIG, '-o', 'json', ...args], {
    encoding: 'utf8',
    timeout: 8_000,
  });
  return JSON.parse(out);
}

function isUnhealthy(pod) {
  const phase = pod.status?.phase || 'Unknown';
  if (['Failed', 'Pending', 'Unknown'].includes(phase)) {
    return true;
  }
  const statuses = [
    ...(pod.status?.containerStatuses || []),
    ...(pod.status?.initContainerStatuses || []),
  ];
  const reasons = statuses.flatMap(cs => [
    cs.state?.waiting?.reason,
    cs.lastState?.terminated?.reason,
  ]);
  const bad = new Set([
    'CrashLoopBackOff',
    'ImagePullBackOff',
    'ErrImagePull',
    'OOMKilled',
    'CreateContainerConfigError',
  ]);
  if (reasons.some(r => bad.has(r))) {
    return true;
  }
  const ready = (pod.status?.conditions || []).find(c => c.type === 'Ready');
  return phase === 'Running' && ready && ready.status !== 'True';
}

function fixtureSnapshot() {
  return {
    gatheredAt: new Date().toISOString(),
    errors: ['kubectl unavailable; using topology fixture'],
    nodes: [
      {
        name: '192.168.1.201',
        ready: true,
        roles: ['control-plane'],
        conditions: [],
        taints: ['node-role.kubernetes.io/control-plane'],
        allocatable: { cpu: '4', memory: '16Gi', gpu: '1' },
      },
      {
        name: '192.168.1.202',
        ready: true,
        roles: [],
        conditions: [],
        taints: [],
        allocatable: { cpu: '4', memory: '8Gi' },
      },
      {
        name: '192.168.1.203',
        ready: true,
        roles: [],
        conditions: [],
        taints: [],
        allocatable: { cpu: '4', memory: '8Gi' },
      },
      {
        name: '192.168.1.204',
        ready: true,
        roles: [],
        conditions: [],
        taints: [],
        allocatable: { cpu: '4', memory: '8Gi' },
      },
    ],
    unhealthyPods: [],
    warningEvents: [],
  };
}

function liveSnapshot() {
  try {
    const nodes = kubectlJson(['get', 'nodes']);
    const pods = kubectlJson(['get', 'pods', '-A']);
    const events = kubectlJson(['get', 'events', '-A']);
    return fromKubeLists(nodes, pods, events);
  } catch (err) {
    console.warn(`kubectl failed (${err.message || err}); using fixture snapshot`);
    return fixtureSnapshot();
  }
}

function fromKubeLists(nodes, pods, events) {
  return {
    gatheredAt: new Date().toISOString(),
    errors: [],
    nodes: (nodes.items || []).map(n => ({
      name: n.metadata?.name,
      ready: (n.status?.conditions || []).some(c => c.type === 'Ready' && c.status === 'True'),
      roles: Object.keys(n.metadata?.labels || {})
        .filter(k => k.startsWith('node-role.kubernetes.io/'))
        .map(k => k.replace('node-role.kubernetes.io/', '')),
      conditions: (n.status?.conditions || [])
        .filter(c => c.status === 'True' && c.type !== 'Ready')
        .map(c => c.type),
      taints: (n.spec?.taints || []).map(t => t.key),
      allocatable: {
        cpu: n.status?.allocatable?.cpu,
        memory: n.status?.allocatable?.memory,
        gpu: n.status?.allocatable?.['nvidia.com/gpu'],
      },
    })),
    unhealthyPods: (pods.items || []).filter(isUnhealthy).slice(0, 20).map(p => ({
      namespace: p.metadata?.namespace,
      name: p.metadata?.name,
      phase: p.status?.phase,
      ready: (p.status?.conditions || []).some(c => c.type === 'Ready' && c.status === 'True'),
      restarts: (p.status?.containerStatuses || []).reduce((s, c) => s + (c.restartCount || 0), 0),
      node: p.spec?.nodeName,
      reasons: [
        ...new Set(
          (p.status?.containerStatuses || []).flatMap(cs =>
            [cs.state?.waiting?.reason, cs.lastState?.terminated?.reason].filter(Boolean)
          )
        ),
      ],
    })),
    warningEvents: (events.items || [])
      .filter(e => e.type === 'Warning')
      .slice(0, 25)
      .map(e => ({
        type: e.type,
        reason: e.reason,
        message: String(e.message || '').slice(0, 240),
        object: e.involvedObject
          ? `${e.involvedObject.kind}/${e.involvedObject.namespace || ''}/${e.involvedObject.name}`
          : undefined,
      })),
  };
}

const CRASHLOOP_FIXTURE = {
  namespace: 'ollama',
  name: 'ollama-7d8f9c6b5-x2z9k',
  phase: 'Running',
  ready: false,
  restarts: 7,
  node: '192.168.1.201',
  reasons: ['CrashLoopBackOff', 'OOMKilled'],
};

async function ask(system, snapshot, question) {
  const body = {
    model: MODEL,
    stream: false,
    keep_alive: '30m',
    options: { temperature: 0 },
    messages: [
      { role: 'system', content: system },
      {
        role: 'user',
        content: `${question}\n\n## Live cluster snapshot\n${JSON.stringify(snapshot, null, 2)}`,
      },
    ],
  };
  const res = await fetch(`${OLLAMA.replace(/\/$/, '')}/api/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(300_000),
  });
  if (!res.ok) {
    throw new Error(`Ollama ${res.status}: ${await res.text()}`);
  }
  const json = await res.json();
  return json?.message?.content || '';
}

function forbidden(answer) {
  const hits = [];
  if (/\bssh\s+\S+/i.test(answer) || /\bssh\s+root@/i.test(answer)) {
    hits.push('ssh');
  }
  if (/\b(run|use|try|execute|please run)\s+`?talosctl\b/i.test(answer)) {
    hits.push('talosctl');
  }
  return hits;
}

async function main() {
  const system = loadPrompt();
  console.log(`Ollama ${OLLAMA} model=${MODEL}`);
  console.log(`kubeconfig ${KUBECONFIG}`);

  const live = liveSnapshot();
  console.log(
    `live snapshot: ${live.nodes.length} nodes, ${live.unhealthyPods.length} unhealthy pods, ${live.warningEvents.length} warnings`
  );

  const cases = [
    {
      id: 'healthy',
      question: 'Is the cluster healthy right now?',
      snapshot: live,
      expect: live.unhealthyPods.length === 0 ? [/healthy/i] : [],
    },
    {
      id: 'crashloop',
      question: 'The ollama pod keeps restarting, why?',
      snapshot: {
        ...live,
        unhealthyPods: [CRASHLOOP_FIXTURE, ...live.unhealthyPods],
        warningEvents: [
          {
            type: 'Warning',
            reason: 'BackOff',
            message: 'Back-off restarting failed container',
            object: 'Pod/ollama/ollama-7d8f9c6b5-x2z9k',
          },
          ...live.warningEvents,
        ],
      },
      expect: [/OOMKilled/i],
    },
    {
      id: 'nvidia-persistenced-quirk',
      question:
        'talosctl health says a worker is stuck at stage booting with ext-nvidia-persistenced waiting — is that serious?',
      snapshot: live,
      expect: [/ext-nvidia-persistenced|non-issue|not (an )?incident|not serious|known/i],
    },
  ];

  const only = process.argv.includes('--case')
    ? process.argv[process.argv.indexOf('--case') + 1]
    : null;
  const selected = only ? cases.filter(c => c.id === only) : cases;
  if (only && selected.length === 0) {
    throw new Error(`unknown --case ${only}`);
  }

  let failed = 0;
  for (const c of selected) {
    process.stdout.write(`\n>>> ${c.id} … `);
    const t0 = Date.now();
    const answer = await ask(system, c.snapshot, c.question);
    const seconds = ((Date.now() - t0) / 1000).toFixed(1);
    const bad = forbidden(answer);
    const missing = c.expect.filter(re => !re.test(answer));
    const ok = bad.length === 0 && missing.length === 0;
    console.log(`${ok ? 'PASS' : 'FAIL'} (${seconds}s)`);
    console.log(answer.slice(0, 800));
    if (bad.length) {
      console.log(`  forbidden present: ${bad}`);
    }
    if (missing.length) {
      console.log(`  expected missing: ${missing}`);
    }
    if (!ok) {
      failed += 1;
    }
  }

  process.exit(failed === 0 ? 0 : 1);
}

main().catch(err => {
  console.error(err);
  process.exit(2);
});

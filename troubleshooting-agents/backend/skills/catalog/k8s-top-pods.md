---
name: k8s-top-pods
description: >
  Show CPU/memory usage per pod (kubectl top pods). Needs metrics-server.
  Use when a specific pod (e.g. ollama) looks starved or is being OOM
  killed.
agents: [talos, ollama]
target: kubectl
safe: true
timeout: 20
mode: top
resource: pods
namespace: "{namespace}"
params:
  namespace:
    type: string
    description: Namespace to check, or "*" for all namespaces
    default: "*"
---

Memory usage climbing steadily right up to a restart is the usual
fingerprint of an OOM kill — cross-check with `k8s-pod-logs` and
`k8s-describe-pod` (look for `OOMKilled` in the container's last state).

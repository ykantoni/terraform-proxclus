---
name: k8s-top-nodes
description: >
  Show CPU/memory usage per node (kubectl top nodes). Needs metrics-server.
  Use when a node looks under resource pressure.
agents: [talos]
target: kubectl
safe: true
timeout: 20
mode: top
resource: nodes
---

If this errors outright, metrics-server itself may be down — that's a
`k8s-get-pods` (namespace kube-system) check away.

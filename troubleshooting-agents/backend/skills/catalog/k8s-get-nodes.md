---
name: k8s-get-nodes
description: >
  List every Kubernetes node with wide output (kubectl get nodes -o wide):
  Ready/NotReady, roles, versions, internal IPs. Use to see node-level
  Kubernetes state at a glance.
agents: [talos]
target: kubectl
safe: true
timeout: 20
mode: get
resource: nodes
extra_args: ["-o", "wide"]
---

Cross-check against `talos-health`/`talos-members` when a node's
Kubernetes state and Talos-level state seem to disagree.

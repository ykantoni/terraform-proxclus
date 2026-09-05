---
name: talos-members
description: >
  List cluster membership as Talos's own discovery service sees it
  (talosctl get members). Use to check whether a node has dropped out of
  the cluster at the Talos level, separate from Kubernetes node status.
agents: [talos]
target: local
safe: true
timeout: 20
command: ["talosctl", "-n", "{node}", "get", "members"]
params:
  node:
    type: string
    description: Node IP to query
    default: "${TALOS_VIP}"
---

A node missing here but present in `k8s-get-nodes` (or vice versa) is
itself a useful, specific symptom to report — it means the two layers
disagree about cluster membership.

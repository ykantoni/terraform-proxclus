---
name: k8s-events
description: >
  List recent Kubernetes events across all namespaces, newest last
  (kubectl get events --sort-by=.lastTimestamp -A). Use when you don't yet
  know which pod or namespace is involved.
agents: [talos]
target: kubectl
safe: true
timeout: 20
mode: get
resource: events
namespace: "*"
extra_args: ["--sort-by=.lastTimestamp"]
---

Cluster-wide events roll off quickly on a busy cluster — treat this as a
recent-history view, not a full audit log.

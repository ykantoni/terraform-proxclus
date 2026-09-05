---
name: k8s-get-pods
description: >
  List pods and their status (kubectl get pods -o wide). Use with a
  specific namespace ("ollama", "kube-system", "longhorn-system", ...) once
  you know where to look, or the default "*" for every namespace when you
  don't yet.
agents: [talos, ollama]
target: kubectl
safe: true
timeout: 20
mode: get
resource: pods
namespace: "{namespace}"
extra_args: ["-o", "wide"]
params:
  namespace:
    type: string
    description: Namespace to list, or "*" for all namespaces
    default: "*"
---

Wide output includes the node each pod landed on and its pod IP — useful
for correlating with `k8s-get-nodes` or a specific node's Talos-level
state.

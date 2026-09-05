---
name: k8s-pod-logs
description: >
  Tail a pod's own logs (kubectl logs). Give either an exact pod name or a
  label selector (the first matching pod is used) plus its namespace. Use
  after k8s-describe-pod to see the container's own stdout/stderr.
agents: [talos, ollama]
target: kubectl
safe: true
timeout: 20
mode: logs
namespace: "{namespace}"
pod: "{pod}"
selector: "{selector}"
container: "{container}"
tail: "{tail}"
params:
  namespace:
    type: string
    description: Namespace the pod is in
  pod:
    type: string
    description: Exact pod name; leave empty and use `selector` instead if you don't have it
    default: ""
  selector:
    type: string
    description: Label selector to find the pod (e.g. "app.kubernetes.io/name=ollama"); ignored if `pod` is set
    default: ""
  container:
    type: string
    description: Container name, only needed for a multi-container pod
    default: ""
  tail:
    type: integer
    description: Number of most recent lines to fetch
    default: 200
---

For the ollama pod specifically, `app.kubernetes.io/name=ollama` in
namespace `ollama` is the selector to use.

---
name: k8s-describe-pod
description: >
  Describe one pod (kubectl describe pod): its events, container states,
  and why it's Pending/CrashLoopBackOff/ImagePullBackOff. Use once
  k8s-get-pods has told you which pod is the problem.
agents: [talos, ollama]
target: kubectl
safe: true
timeout: 20
mode: describe
resource: pods
namespace: "{namespace}"
resource_name: "{resource_name}"
params:
  namespace:
    type: string
    description: Namespace the pod is in
  resource_name:
    type: string
    description: Exact pod name (from k8s-get-pods)
---

The "Events" section at the bottom is usually the fastest path to a root
cause — scheduling failures, image pull errors, and readiness/liveness
probe failures all show up there before they show up in the pod's own
logs.

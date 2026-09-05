---
name: nvidia-smi
description: >
  Run nvidia-smi inside a currently GPU-scheduled pod. Use to check driver
  version, VRAM usage, temperature, and which processes hold the GPU right
  now. Requires such a pod to be Running — if none is, this fails and that
  absence is itself the finding.
agents: [nvidia]
target: kubectl
safe: true
timeout: 20
mode: exec
namespace: "{namespace}"
selector: "{selector}"
command: ["nvidia-smi"]
params:
  namespace:
    type: string
    description: Namespace of a pod that has the GPU attached
    default: "ollama"
  selector:
    type: string
    description: Label selector for a GPU-attached pod
    default: "app.kubernetes.io/name=ollama"
---

Defaults target the ollama pod, today's only GPU consumer on this cluster.
If it fails because no matching pod is Running, say that explicitly — it
means nothing is currently exercising the GPU, which is a `talos`/`ollama`
scheduling question, not proof the GPU itself is broken.

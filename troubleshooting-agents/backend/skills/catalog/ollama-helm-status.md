---
name: ollama-helm-status
description: >
  Show the Helm release status for the ollama chart (helm status ollama -n
  ollama). Use when the API itself is unreachable and you suspect a stuck
  or failed deployment/upgrade rather than a running-but-broken pod.
agents: [ollama]
target: local
safe: true
timeout: 20
command: ["helm", "status", "ollama", "-n", "ollama", "--kubeconfig", "${KUBECONFIG}"]
---

A release stuck `pending-upgrade` or `failed` explains a missing/old pod
better than anything `kubectl` alone will show you.

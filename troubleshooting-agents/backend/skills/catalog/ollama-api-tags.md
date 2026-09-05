---
name: ollama-api-tags
description: >
  List models available on the Ollama server (GET /api/tags) — what's
  actually pulled, not necessarily what's loaded in memory right now. Use
  to confirm a model the user expects is really there.
agents: [ollama]
target: http
safe: true
timeout: 15
method: GET
url: "${OLLAMA_BASE_URL}/api/tags"
---

An empty or missing model here means it was never pulled (or pull failed)
— check `k8s-pod-logs` for pull errors, not GPU/runtime issues.

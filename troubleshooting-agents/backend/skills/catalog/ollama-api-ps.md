---
name: ollama-api-ps
description: >
  List models currently loaded in memory/VRAM on the Ollama server (GET
  /api/ps). Use to check whether a model stays resident or keeps getting
  evicted (a VRAM-pressure symptom).
agents: [ollama]
target: http
safe: true
timeout: 15
method: GET
url: "${OLLAMA_BASE_URL}/api/ps"
---

Empty here right after a request that should have used a model points at
either a crash-and-reload loop (check `k8s-pod-logs`) or GPU/VRAM trouble
(hand off to the `nvidia` agent).

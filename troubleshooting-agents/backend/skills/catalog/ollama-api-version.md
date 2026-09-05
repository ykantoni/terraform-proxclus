---
name: ollama-api-version
description: >
  Basic reachability + version check of the Ollama server (GET
  /api/version). Use first, before the more specific API calls, to confirm
  the server answers at all.
agents: [ollama]
target: http
safe: true
timeout: 10
method: GET
url: "${OLLAMA_BASE_URL}/api/version"
---

A failure here (timeout, connection refused) is itself the finding — the
server isn't reachable at all, which points at the pod/Service rather than
anything model-specific. Note that this is the same server answering your
own queries; a timeout you experience directly is the same symptom.

# Default (300s) is too tight for open-webui's ~1.8GB image on a cold pull
# (observed 6m32s on 2026-08-24). Raised so a slow/cold image pull doesn't
# time out the helm_release wait.
helm_timeout        = 600
ollama_storage_size = "20Gi"


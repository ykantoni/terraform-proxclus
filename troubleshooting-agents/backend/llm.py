"""The single LLM every agent shares: gemma running on the cluster's own
Ollama server. Swapping model/host/temperature is a .env change
(OLLAMA_BASE_URL / OLLAMA_MODEL / OLLAMA_TEMPERATURE) — nothing else in this
package hardcodes it.
"""
from __future__ import annotations

from langchain_ollama import ChatOllama

from config import settings


def build_llm() -> ChatOllama:
    return ChatOllama(
        base_url=settings.ollama_base_url,
        model=settings.ollama_model,
        temperature=settings.ollama_temperature,
        keep_alive=settings.ollama_keep_alive,
        # This model measures slow on this repo's own server (a bare 2-token
        # reply took ~58s) — a generous client timeout matters more than it
        # would for a typical hosted model. See OLLAMA_REQUEST_TIMEOUT.
        client_kwargs={"timeout": settings.ollama_request_timeout},
    )


# One shared instance — cheap to construct, but sharing avoids each agent
# opening its own client.
llm = build_llm()

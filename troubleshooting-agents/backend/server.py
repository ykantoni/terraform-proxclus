"""FastAPI backend for the troubleshooting GUI.

Two endpoints:
  GET  /api/agents  -> the agent picker's contents
  POST /api/chat     -> runs one turn, streamed as newline-delimited JSON
                        events (route decision, tool calls, tool results,
                        the final answer) so the GUI can show its trace live.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

# Runs correctly regardless of cwd (`python server.py`, `python -m uvicorn
# server:app`, or from run.py) by making sure this directory is importable.
sys.path.insert(0, str(Path(__file__).resolve().parent))

from fastapi import FastAPI  # noqa: E402
from fastapi.middleware.cors import CORSMiddleware  # noqa: E402
from fastapi.responses import StreamingResponse  # noqa: E402
from pydantic import BaseModel  # noqa: E402

from agents.loader import agent_defs, compiled_agent  # noqa: E402
from config import settings  # noqa: E402
from graph import resolve_agent_id  # noqa: E402

app = FastAPI(title="Troubleshooting Agents")

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_methods=["*"],
    allow_headers=["*"],
)


class ChatRequest(BaseModel):
    message: str
    agent_id: str = "auto"
    thread_id: str = "default"


@app.get("/api/agents")
def list_agents():
    return [
        {"id": name, "title": d.title, "description": d.description}
        for name, d in agent_defs().items()
    ]


@app.get("/api/health")
def health():
    return {"ok": True, "model": settings.ollama_model, "ollama_base_url": settings.ollama_base_url}


def _event(obj: dict) -> bytes:
    return (json.dumps(obj) + "\n").encode()


def _stream_chat(req: ChatRequest):
    try:
        resolved = resolve_agent_id(req.agent_id, req.message)
    except Exception as exc:  # noqa: BLE001 - surfaced to the GUI, not swallowed
        yield _event({"type": "error", "message": f"Routing failed: {exc}"})
        return

    if req.agent_id == "auto":
        yield _event({"type": "route", "agent_id": resolved})

    agent = compiled_agent(resolved)
    config = {"configurable": {"thread_id": req.thread_id}}
    graph_input = {"messages": [("user", req.message)]}

    try:
        for update in agent.stream(graph_input, config=config, stream_mode="updates"):
            for _node, payload in update.items():
                for msg in payload.get("messages", []):
                    tool_calls = getattr(msg, "tool_calls", None)
                    if tool_calls:
                        yield _event({
                            "type": "tool_call",
                            "calls": [{"name": tc["name"], "args": tc["args"]} for tc in tool_calls],
                        })
                    elif getattr(msg, "type", "") == "tool":
                        yield _event({
                            "type": "tool_result",
                            "name": getattr(msg, "name", ""),
                            "content": str(msg.content),
                        })
                    elif getattr(msg, "content", ""):
                        yield _event({"type": "message", "content": str(msg.content)})
    except Exception as exc:  # noqa: BLE001
        yield _event({"type": "error", "message": f"Agent '{resolved}' failed: {exc}"})
        return

    yield _event({"type": "done", "agent_id": resolved})


@app.post("/api/chat")
def chat(req: ChatRequest):
    return StreamingResponse(_stream_chat(req), media_type="application/x-ndjson")

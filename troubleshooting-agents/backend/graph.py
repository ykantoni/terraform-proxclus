"""Top-level orchestration: picks which domain agent answers a question.

Two paths, matching the diagram in ../AGENTS.md:
  - explicit agent_id ("talos" | "ollama" | "nvidia" | "proxmox"): returned
    as-is, no extra LLM call — this is what the GUI's dropdown sends by
    default.
  - agent_id == "auto": a tiny one-node LangGraph graph classifies the
    question against every agent's `description` and returns its pick.

The actual domain work happens in the resolved agent itself (a LangGraph
ReAct agent from agents/loader.py), invoked/streamed separately by
server.py so tool-call events can be surfaced to the caller as they happen.
"""
from __future__ import annotations

from typing import TypedDict

from langgraph.graph import END, START, StateGraph

from agents.loader import agent_defs
from llm import llm


class RouteState(TypedDict):
    message: str
    resolved: str


def _router_node(state: RouteState) -> dict:
    defs = agent_defs()
    catalog = "\n".join(f"- {name}: {d.description}" for name, d in defs.items())
    prompt = (
        "You are a router for a troubleshooting system with these specialist agents:\n\n"
        f"{catalog}\n\n"
        "Pick exactly one agent id that best matches the user's question below. "
        "Reply with only the agent id, nothing else.\n\n"
        f"Question: {state['message']}\n"
        "Agent id:"
    )
    reply = llm.invoke(prompt).content.strip().lower()
    resolved = next((name for name in defs if name in reply), None)
    if resolved is None:
        # Unparseable/unexpected model output: fall back to the first
        # defined agent rather than failing the request outright.
        resolved = next(iter(defs))
    return {"resolved": resolved}


def _build_router_graph():
    g = StateGraph(RouteState)
    g.add_node("router", _router_node)
    g.add_edge(START, "router")
    g.add_edge("router", END)
    return g.compile()


_router_graph = None


def resolve_agent_id(agent_id: str, message: str) -> str:
    valid_ids = agent_defs().keys()
    if agent_id in valid_ids:
        return agent_id

    global _router_graph
    if _router_graph is None:
        _router_graph = _build_router_graph()
    result = _router_graph.invoke({"message": message, "resolved": ""})
    return result["resolved"]

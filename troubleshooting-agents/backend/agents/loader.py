"""Reads every *.md file in agents/catalog/ and compiles it into a LangGraph
ReAct agent. See ../../AGENTS.md for the file format this implements.
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from langgraph.checkpoint.memory import MemorySaver
from langgraph.prebuilt import create_react_agent

from llm import llm
from md_frontmatter import FrontmatterError, parse
from skills.loader import tools_for_agent

CATALOG_DIR = Path(__file__).parent / "catalog"

# Shared across every agent so a thread_id's history survives moving between
# agents in the same conversation (the router case) without extra wiring.
checkpointer = MemorySaver()


@dataclass
class AgentDef:
    name: str
    title: str
    description: str
    prompt: str
    source_path: str = ""


def _load_one(path: Path) -> AgentDef:
    frontmatter, body = parse(path.read_text(), path=str(path))
    for required in ("name", "title", "description"):
        if required not in frontmatter:
            raise FrontmatterError(f"{path}: missing required field '{required}'")
    if not body:
        raise FrontmatterError(f"{path}: body (the system prompt) must not be empty")
    return AgentDef(
        name=frontmatter["name"],
        title=frontmatter["title"],
        description=frontmatter["description"],
        prompt=body,
        source_path=str(path),
    )


def load_agent_defs() -> dict[str, AgentDef]:
    defs: dict[str, AgentDef] = {}
    for path in sorted(CATALOG_DIR.glob("*.md")):
        agent_def = _load_one(path)
        if agent_def.name in defs:
            raise FrontmatterError(f"{path}: duplicate agent name '{agent_def.name}' (also in {defs[agent_def.name].source_path})")
        defs[agent_def.name] = agent_def
    return defs


_agent_defs_cache: dict[str, AgentDef] | None = None
_compiled_cache: dict[str, object] = {}


def agent_defs() -> dict[str, AgentDef]:
    global _agent_defs_cache
    if _agent_defs_cache is None:
        _agent_defs_cache = load_agent_defs()
    return _agent_defs_cache


def compiled_agent(name: str):
    """The compiled, runnable LangGraph ReAct agent for one agent id (built once, cached)."""
    if name not in _compiled_cache:
        agent_def = agent_defs()[name]
        tools = tools_for_agent(name)
        _compiled_cache[name] = create_react_agent(
            llm,
            tools=tools,
            prompt=agent_def.prompt,
            checkpointer=checkpointer,
        )
    return _compiled_cache[name]

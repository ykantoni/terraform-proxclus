"""Reads every *.md file in skills/catalog/, and turns each into a LangChain
tool. See ../../SKILLS.md for the file format this implements.
"""
from __future__ import annotations

import string
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

from langchain_core.tools import StructuredTool
from pydantic import BaseModel, Field, create_model

from config import settings
from md_frontmatter import FrontmatterError, parse
from skills.executor import ExecResult, run_http, run_kubectl, run_local, run_ssh

CATALOG_DIR = Path(__file__).parent / "catalog"

_TYPE_MAP: dict[str, type] = {"string": str, "integer": int, "enum": str}


@dataclass
class SkillDef:
    name: str
    description: str
    agents: list[str]
    target: str
    safe: bool
    timeout: int
    params: dict[str, dict]
    spec: dict[str, Any] = field(default_factory=dict)  # the rest of the frontmatter (command/url/mode/...)
    source_path: str = ""


def _sub_vars(value: Any) -> Any:
    """Resolves "${VAR}" against config.settings.template_vars, recursively."""
    if isinstance(value, str):
        return string.Template(value).safe_substitute(settings.template_vars)
    if isinstance(value, list):
        return [_sub_vars(v) for v in value]
    if isinstance(value, dict):
        return {k: _sub_vars(v) for k, v in value.items()}
    return value


def _load_one(path: Path) -> SkillDef:
    frontmatter, _body = parse(path.read_text(), path=str(path))
    frontmatter = _sub_vars(frontmatter)

    for required in ("name", "description", "agents", "target"):
        if required not in frontmatter:
            raise FrontmatterError(f"{path}: missing required field '{required}'")

    known = {"name", "description", "agents", "target", "safe", "timeout", "params"}
    spec = {k: v for k, v in frontmatter.items() if k not in known}

    return SkillDef(
        name=frontmatter["name"],
        description=frontmatter["description"],
        agents=frontmatter["agents"],
        target=frontmatter["target"],
        safe=frontmatter.get("safe", True),
        timeout=int(frontmatter.get("timeout", 30)),
        params=frontmatter.get("params", {}) or {},
        spec=spec,
        source_path=str(path),
    )


def load_skills() -> dict[str, SkillDef]:
    skills: dict[str, SkillDef] = {}
    for path in sorted(CATALOG_DIR.glob("*.md")):
        skill = _load_one(path)
        if skill.name in skills:
            raise FrontmatterError(f"{path}: duplicate skill name '{skill.name}' (also in {skills[skill.name].source_path})")
        skills[skill.name] = skill
    return skills


def _param_model(skill: SkillDef) -> type[BaseModel]:
    fields: dict[str, tuple] = {}
    for pname, pspec in skill.params.items():
        ptype = _TYPE_MAP.get(pspec.get("type", "string"), str)
        desc = pspec.get("description", "")
        if "default" in pspec:
            fields[pname] = (ptype, Field(default=pspec["default"], description=desc))
        else:
            fields[pname] = (ptype, Field(..., description=desc))

    if not skill.safe:
        fields["confirm"] = (
            bool,
            Field(default=False, description="Must be explicitly set true to run this non-read-only action."),
        )

    return create_model(f"{skill.name.replace('-', '_')}_args", **fields)  # type: ignore[call-overload]


def _fill(template: Any, kwargs: dict) -> Any:
    if isinstance(template, str):
        return template.format(**kwargs)
    if isinstance(template, list):
        return [_fill(v, kwargs) for v in template]
    if isinstance(template, dict):
        return {k: _fill(v, kwargs) for k, v in template.items()}
    return template


def _execute(skill: SkillDef, kwargs: dict) -> str:
    if not skill.safe and not kwargs.pop("confirm", False):
        return (
            f"Refused: '{skill.name}' is marked non-read-only and requires confirm=true "
            "to actually run. Ask the user to confirm before retrying with confirm=true."
        )

    spec = skill.spec
    try:
        if skill.target == "local":
            argv = _fill(spec["command"], kwargs)
            result = run_local(argv, skill.timeout)

        elif skill.target == "ssh":
            connection = settings.connections[spec["connection"]]
            argv = _fill(spec["command"], kwargs)
            result = run_ssh(connection, argv, skill.timeout)

        elif skill.target == "kubectl":
            filled = _fill(spec, kwargs)
            result = run_kubectl(
                mode=filled["mode"],
                namespace=filled.get("namespace"),
                pod=filled.get("pod"),
                selector=filled.get("selector"),
                container=filled.get("container"),
                command=filled.get("command"),
                resource=filled.get("resource"),
                resource_name=filled.get("resource_name"),
                extra_args=filled.get("extra_args"),
                tail=filled.get("tail"),
                timeout=skill.timeout,
            )

        elif skill.target == "http":
            filled = _fill(spec, kwargs)
            result = run_http(
                method=filled.get("method", "GET"),
                url=filled["url"],
                timeout=skill.timeout,
                json_body=filled.get("json"),
            )

        else:
            result = ExecResult(ok=False, output=f"Skill '{skill.name}' has unknown target '{skill.target}'.")

    except KeyError as exc:
        result = ExecResult(ok=False, output=f"Skill '{skill.name}' misconfigured or missing param: {exc}")

    return result.formatted()


def build_tool(skill: SkillDef) -> StructuredTool:
    args_model = _param_model(skill)

    def _tool_fn(**kwargs: Any) -> str:
        return _execute(skill, kwargs)

    return StructuredTool.from_function(
        func=_tool_fn,
        name=skill.name,
        description=skill.description,
        args_schema=args_model,
    )


_skills_cache: dict[str, SkillDef] | None = None


def all_skills() -> dict[str, SkillDef]:
    global _skills_cache
    if _skills_cache is None:
        _skills_cache = load_skills()
    return _skills_cache


def tools_for_agent(agent_name: str) -> list[StructuredTool]:
    return [
        build_tool(skill)
        for skill in all_skills().values()
        if agent_name in skill.agents or "*" in skill.agents
    ]

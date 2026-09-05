"""Minimal `---`-delimited YAML-frontmatter + Markdown-body parser, shared by
the skills and agents loaders. Deliberately dependency-light (just PyYAML) —
this format is a small, fixed subset (see ../SKILLS.md and ../AGENTS.md), not
a general Markdown-metadata library's worth of edge cases.
"""
from __future__ import annotations

import yaml


class FrontmatterError(ValueError):
    pass


def parse(text: str, *, path: str = "<string>") -> tuple[dict, str]:
    """Returns (frontmatter_dict, body). `path` is only used in error messages."""
    if not text.startswith("---"):
        raise FrontmatterError(f"{path}: file must start with a `---` frontmatter block")

    parts = text.split("---", 2)
    if len(parts) < 3:
        raise FrontmatterError(f"{path}: missing closing `---` for the frontmatter block")

    _, raw_frontmatter, body = parts
    try:
        frontmatter = yaml.safe_load(raw_frontmatter) or {}
    except yaml.YAMLError as exc:
        raise FrontmatterError(f"{path}: invalid YAML frontmatter: {exc}") from exc

    if not isinstance(frontmatter, dict):
        raise FrontmatterError(f"{path}: frontmatter must be a YAML mapping")

    return frontmatter, body.strip()

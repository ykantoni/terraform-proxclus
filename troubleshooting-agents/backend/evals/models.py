"""Shared types for the eval harness. See evals/README.md."""
from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class Case:
    id: str
    agent_id: str
    question: str
    # skill name -> canned tool output the mocked executor returns instead
    # of actually running the command. Every tool the agent might plausibly
    # reach for in this scenario should ideally have an entry here — a call
    # to a tool with no entry still "succeeds" (so the agent doesn't crash
    # mid-conversation), but returns a visible [EVAL ERROR] marker, which
    # shows up in the failure printout as a coverage gap to fix.
    mocks: dict[str, str]
    # Tools that MUST be among those called for this case to count as having
    # investigated correctly (subset check — extra calls are fine, order
    # doesn't matter).
    expected_tools: list[str] = field(default_factory=list)
    # Substrings (case-insensitive) that must appear somewhere in the final
    # answer for it to count as factually correct.
    expected_facts: list[str] = field(default_factory=list)
    # Substrings that must NOT appear — false-alarm / scope-creep checks
    # (e.g. a known-quirk case where the agent should NOT call it an
    # incident).
    forbidden_facts: list[str] = field(default_factory=list)
    notes: str = ""


@dataclass
class CaseResult:
    case: Case
    called_tools: list[str]
    final_answer: str
    tool_match: bool
    facts_match: bool
    forbidden_clean: bool
    error: str | None = None
    seconds: float = 0.0

    @property
    def passed(self) -> bool:
        return self.error is None and self.tool_match and self.facts_match and self.forbidden_clean

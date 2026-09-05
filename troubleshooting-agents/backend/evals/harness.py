"""Direct-invocation eval harness.

Runs each Case in evals/cases.py against the REAL LLM (gemma4:26b) with
only the tool-EXECUTION layer mocked out — skills/loader.py's `_execute` is
monkeypatched to return a canned string instead of actually shelling out to
talosctl/kubectl/ssh/http. This tests "does the agent reason correctly given
this evidence", independent of the cluster's actual live state, at the cost
of not catching real command/syntax bugs (see ../README.md's "Extending
this" section for the tradeoff, and evals/README.md for how to run this
against the real cluster too when you want that other half of coverage).

Usage:
    python harness.py                    # run all 20 cases
    python harness.py --case talos-01-healthy
    python harness.py --limit 5          # first N only, for a quick smoke test
    python harness.py --workers 3        # see the --workers help text below

Exit code is 0 if every case passed, 1 otherwise — usable as a CI gate.
"""
from __future__ import annotations

import argparse
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))  # backend/

import skills.loader as skills_loader  # noqa: E402
from agents.loader import compiled_agent  # noqa: E402
from evals.cases import CASES  # noqa: E402
from evals.models import Case, CaseResult  # noqa: E402


def _fake_execute(case: Case, called: list[str]):
    """Replaces skills.loader._execute for the duration of one case. Records
    every tool name the agent actually called, and returns the case's canned
    output for it — or a visible marker if the case didn't anticipate that
    tool, so a coverage gap shows up in the failure printout instead of
    silently passing/failing for the wrong reason.
    """

    def _execute(skill, kwargs):
        called.append(skill.name)
        try:
            return case.mocks[skill.name]
        except KeyError:
            return (
                f"[EVAL ERROR] case '{case.id}' has no mock for tool "
                f"'{skill.name}' (called with {kwargs}) — add one in evals/cases.py"
            )

    return _execute


def run_case(case: Case) -> CaseResult:
    called: list[str] = []
    t0 = time.time()
    final = ""
    error: str | None = None

    try:
        # skills.loader._execute is looked up as a plain global inside the
        # closure build_tool() hands to LangChain, so patching the module
        # attribute here affects every already-built tool too — no need to
        # rebuild the compiled agent per case.
        with patch.object(skills_loader, "_execute", _fake_execute(case, called)):
            agent = compiled_agent(case.agent_id)
            result = agent.invoke(
                {"messages": [("user", case.question)]},
                # unique per case so LangGraph's checkpointer never mixes
                # conversation history between scenarios
                config={"configurable": {"thread_id": f"eval-{case.id}"}},
            )
        final = str(result["messages"][-1].content or "")
    except Exception as exc:  # noqa: BLE001 - a case blowing up is a result, not a harness crash
        error = f"{type(exc).__name__}: {exc}"

    text = final.lower()
    tool_match = all(t in called for t in case.expected_tools)
    facts_match = all(f.lower() in text for f in case.expected_facts)
    forbidden_clean = all(f.lower() not in text for f in case.forbidden_facts)

    return CaseResult(
        case=case,
        called_tools=called,
        final_answer=final,
        tool_match=tool_match,
        facts_match=facts_match,
        forbidden_clean=forbidden_clean,
        error=error,
        seconds=time.time() - t0,
    )


def _print_result(r: CaseResult) -> None:
    status = "PASS" if r.passed else "FAIL"
    print(f"[{status}] {r.case.id:28s} ({r.seconds:5.1f}s)  {r.case.notes}")
    if not r.passed:
        print(f"         tools called: {r.called_tools}")
        if not r.tool_match:
            missing = [t for t in r.case.expected_tools if t not in r.called_tools]
            print(f"         expected tool(s) never called: {missing}")
        if not r.facts_match:
            missing = [f for f in r.case.expected_facts if f.lower() not in r.final_answer.lower()]
            print(f"         expected fact(s) missing from answer: {missing}")
        if not r.forbidden_clean:
            present = [f for f in r.case.forbidden_facts if f.lower() in r.final_answer.lower()]
            print(f"         forbidden fact(s) present in answer: {present}")
        if r.error:
            print(f"         error: {r.error}")
        print(f"         answer: {r.final_answer[:300]!r}")


def run_all(cases: list[Case], workers: int = 1) -> list[CaseResult]:
    results: list[CaseResult] = []
    if workers > 1:
        with ThreadPoolExecutor(max_workers=workers) as pool:
            futures = {pool.submit(run_case, c): c for c in cases}
            for fut in as_completed(futures):
                r = fut.result()
                results.append(r)
                _print_result(r)
    else:
        for c in cases:
            r = run_case(c)
            results.append(r)
            _print_result(r)
    return results


def print_scorecard(results: list[CaseResult]) -> None:
    total = len(results)
    passed = sum(r.passed for r in results)
    tool_rate = sum(r.tool_match for r in results) / total if total else 0
    facts_rate = sum(r.facts_match for r in results) / total if total else 0
    clean_rate = sum(r.forbidden_clean for r in results) / total if total else 0
    errors = sum(1 for r in results if r.error)
    total_seconds = sum(r.seconds for r in results)

    print("\n" + "=" * 64)
    print(f"SCORE: {passed}/{total} passed  ({total_seconds:.0f}s total)")
    print(f"  tool-selection match:  {tool_rate:.0%}")
    print(f"  expected-facts match:  {facts_rate:.0%}")
    print(f"  forbidden-facts clean: {clean_rate:.0%}")
    print(f"  errors/exceptions:     {errors}")
    print("=" * 64)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--case", help="run only this case id")
    parser.add_argument("--limit", type=int, help="run only the first N cases")
    parser.add_argument(
        "--workers",
        type=int,
        default=1,
        help=(
            "run this many cases concurrently. gemma4:26b is one model on one "
            "GPU behind a single Ollama server — concurrent requests likely "
            "serialize there anyway (and risk timeouts under contention), so "
            "this mostly helps if OLLAMA_REQUEST_TIMEOUT has headroom to spare. "
            "Start at 1 and only raise it if you've confirmed the server "
            "handles concurrent requests well."
        ),
    )
    args = parser.parse_args()

    cases = CASES
    if args.case:
        cases = [c for c in cases if c.id == args.case]
        if not cases:
            print(f"No case with id '{args.case}'. Known ids:")
            for c in CASES:
                print(f"  {c.id}")
            sys.exit(2)
    if args.limit:
        cases = cases[: args.limit]

    results = run_all(cases, workers=args.workers)
    print_scorecard(results)
    sys.exit(0 if all(r.passed for r in results) else 1)


if __name__ == "__main__":
    main()

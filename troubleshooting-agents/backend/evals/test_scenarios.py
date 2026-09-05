"""Thin pytest wrapper around the same 20 cases, for `pytest`/CI use.

    pytest evals/ -q                        # all 20, one assertion each
    pytest evals/ -q -k talos-01-healthy     # a single case

For the human-readable scorecard (X/20, per-metric rates) run
`python evals/harness.py` directly instead — pytest's output is optimized
for "which cases failed", not for the aggregate score.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))  # backend/

import pytest  # noqa: E402

from evals.cases import CASES  # noqa: E402
from evals.harness import run_case  # noqa: E402


@pytest.mark.parametrize("case", CASES, ids=[c.id for c in CASES])
def test_scenario(case):
    result = run_case(case)
    assert result.passed, (
        f"tools_called={result.called_tools} "
        f"error={result.error} "
        f"answer={result.final_answer[:300]!r}"
    )

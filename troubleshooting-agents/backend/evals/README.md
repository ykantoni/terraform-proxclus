# Eval harness

20 scripted troubleshooting scenarios (`cases.py`), run directly against
the real LLM (`agents.loader.compiled_agent(...).invoke(...)`, no HTTP
server involved) with only the **tool-execution layer** mocked out —
`skills/loader.py`'s `_execute` is monkeypatched per case to return a
canned string instead of actually running `talosctl`/`kubectl`/`ssh`/HTTP.

This tests one specific thing well: *given this evidence, does the agent
call the right tool and draw the right conclusion* — independent of
whatever state the real cluster happens to be in today. It does **not**
test whether the real commands still work (right flags, right selectors) —
that needs a live-cluster spot check instead; see "What this doesn't cover"
below.

## Running it

```bash
cd ../   # backend/
python evals/harness.py                       # all 20, prints a scorecard
python evals/harness.py --case talos-01-healthy
python evals/harness.py --limit 4             # quick smoke test while iterating
pytest evals/ -q                               # same 20 cases, one assert each, for CI
```

Each case makes 1-3 real round trips to `gemma4:26b`. At this model's
measured speed (see ../../README.md's latency note) expect the full 20-case
run to take **several minutes**, not seconds — use `--limit`/`--case` while
iterating on a prompt or a case definition, and save the full run for
before/after a real change.

Output looks like:

```
[PASS] talos-01-healthy             ( 14.2s)  Baseline: clean bill of health...
[FAIL] ollama-04-vram-handoff       ( 19.8s)  Empty /api/ps + no crash...
         tools called: ['ollama-api-ps', 'k8s-pod-logs']
         expected fact(s) missing from answer: ['nvidia']
         answer: 'The model may be getting evicted due to...'

========================================================================
SCORE: 17/20 passed  (312s total)
  tool-selection match:  95%
  expected-facts match:  90%
  forbidden-facts clean: 100%
  errors/exceptions:     0
========================================================================
```

## Reading a failure

Three independent checks, all of which must pass for a case to count as
`PASS` — the printout tells you which one(s) failed:

- **tool-selection match** — did it call the tool(s) the scenario expects?
  A miss here usually means a skill's `description` in `skills/catalog/`
  isn't distinctive enough, or the agent's system prompt doesn't point at
  it clearly for this kind of question.
- **expected-facts match** — is the specific evidence (an error code, a
  status, a named service) actually present in the final answer, not just
  gestured at? A miss here is the more worrying kind — the right tool ran,
  but the model didn't use its output.
- **forbidden-facts clean** — did it avoid fabricating a problem
  (`proxmox-04-healthy-negative`) or overreacting to a known non-issue
  (`talos-04-known-quirk`)?

A `[EVAL ERROR] no mock for tool 'X'` inside `answer:` means the agent
reached for a tool the case didn't anticipate — not necessarily wrong, but
add a mock for it in `cases.py` so the case actually reflects what the
agent does, instead of scoring against an artifact of incomplete mocking.

## What this doesn't cover

- **Whether the real command syntax still works** — `nvidia-smi.md`'s
  guessed label selector, `pveversion -v`'s exact flags, etc. Only running
  the real skill against the real cluster catches that. The mocked
  `_execute` never touches `skills/executor.py`.
- **Router accuracy** (`agent_id="auto"`) — every case here calls
  `compiled_agent(case.agent_id)` directly with an explicit id, bypassing
  `graph.py`'s router entirely. Worth its own small case set
  (question → expected agent id, no mocking needed since the router makes
  no tool calls) if router quality becomes a concern.
- **Multi-turn conversations** — every case is a single question/answer.
  Real usage often follows up ("what about the other node?"); this harness
  doesn't exercise that.

## Adding a case

Add a `Case(...)` to `CASES` in `cases.py`: an `id`, `agent_id`, `question`,
`mocks` (skill name → canned output for every tool the scenario should
plausibly touch), and at least one of `expected_tools`/`expected_facts`/
`forbidden_facts`. See `models.py` for the full field list, and pick
`expected_facts` that are likely to survive paraphrasing — exact numbers,
error codes, and names the model tends to quote verbatim score much more
reliably than sentiment ("is degraded", "looks fine").

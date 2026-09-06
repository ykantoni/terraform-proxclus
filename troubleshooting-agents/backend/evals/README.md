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
python evals/harness.py --verbose             # live ReAct steps (see a hang)
python evals/harness.py --debug --case ollama-01-version   # full LangChain dumps
pytest evals/ -q                               # same 20 cases, one assert each, for CI
```

Each case makes 1-3 real round trips to `gemma4:26b`. At this model's
measured speed (see ../../README.md's latency note) expect the full 20-case
run to take **several minutes**, not seconds — use `--limit`/`--case` while
iterating on a prompt or a case definition, and save the full run for
before/after a real change.

The default path is `agent.invoke(...)`, which prints nothing until the
case finishes. A long silence after a `[PASS]` is usually the *next* case
already in flight (the harness now prints `running...` when it starts one).
If that next case itself looks hung, re-run it with `--verbose`:

```
       ollama-01-version             running...
         question: Is the ollama server reachable, and what version is it running?
         [  41.2s] agent      tool_call   ollama-api-version({})
         [  41.3s] tools      tool_result ollama-api-version: HTTP 200 {"version":"0.32.15"}
         [  78.9s] agent      message     The ollama server is reachable and running version 0.32.15.
[PASS] ollama-01-version             ( 79.0s)  Baseline reachability check.
```

Silence *after* a printed step is the next Ollama round-trip (prompt eval
on `gemma4:26b` is often 20–60s). Silence with no `running...` line means
the previous `invoke()` is still blocking — Ctrl-C and re-run that id
with `--verbose`. `--debug` is the LangChain firehose (full system prompt
+ raw completions on every LLM call); pair it with `--case`. To see
whether the model is actually generating on the server:

Every line the harness prints now carries a wall-clock `HH:MM:SS` (from
`_clock()`) in addition to the elapsed-seconds counter, and every print
uses `flush=True`. That matters because Python switches stdout to
block-buffered (not line-buffered) the moment it isn't attached directly
to a real console — piping through `| tee`, redirecting to a file, or some
terminal wrappers all trigger this — so without an explicit flush, several
`[PASS]`/`[FAIL]` lines can sit in the buffer and land on screen together,
long after the cases they describe actually finished. The `(Xs)` number
on each line is measured with `time.time()` *inside* that case's own
`run_case()` call, so it's always correct for that case — a burst of
lines appearing at once after a long silence is a buffering artifact, not
proof those cases secretly took longer than reported. The `started_at`/
`finished_at` timestamps in each result line are the fix: they're the
wall-clock times regardless of when the *line itself* got flushed, so you
can tell "case ran 10:20:11→10:21:25" apart from "case's PASS line merely
appeared on screen at 10:21:25." `run_all()` also prints a `run started`/
`run finished` line with the actual wall-clock span of the whole run —
compare it to the scorecard's summed per-case seconds; a big gap points at
buffering or at time spent outside any case (imports, `compiled_agent()`
warmup on the very first case, etc.) rather than a mystery slowdown.

If a run looks hung and you don't want to Ctrl-C it (e.g. it's already
30+ minutes in and you don't want to lose that progress), you can inspect
the *live* process instead of restarting with `--verbose`:

```powershell
Get-Process -Id <pid> | Select-Object Id,StartTime,CPU,Threads
netstat -ano | findstr :11434
```

Low CPU time relative to wall-clock elapsed (e.g. 20s CPU over 30 minutes)
means it's genuinely blocked waiting on I/O, not spinning in a bug — and
an `ESTABLISHED` connection to the Ollama host on port 11434 confirms it's
mid-request to the LLM, not stuck elsewhere in the graph. Pair that with
`curl http://<ollama-host>:11434/api/ps` (below) to see whether the model
is still loaded and its `expires_at` is being refreshed. If you need the
actual Python stack (which node, which library call) without restarting,
`pip install py-spy` and run `py-spy dump --pid <pid>` (may need an
elevated/Administrator shell on Windows) — it attaches to the running
process and prints every thread's current frame, no `--verbose` needed.

```bash
curl http://192.168.1.63:11434/api/ps
```

A loaded `gemma4:26b` with a recent `expires_at` means Ollama is working;
an empty `models` list means the request never arrived (or already
finished). The client will wait up to `OLLAMA_REQUEST_TIMEOUT` (default
300s) *per* LLM call, and LangGraph's ReAct loop can do many of those
before it gives up (default `recursion_limit` is 25).

Output looks like:

```
run started 2026-09-06T10:14:03  (20 case(s), workers=1)
[PASS] talos-01-healthy             ( 14.2s)  10:14:03->10:14:17  Baseline: clean bill of health...
[FAIL] ollama-04-vram-handoff       ( 19.8s)  10:19:41->10:20:01  Empty /api/ps + no crash...
         tools called: ['ollama-api-ps', 'k8s-pod-logs']
         expected fact(s) missing from answer: ['nvidia']
         answer: 'The model may be getting evicted due to...'
run finished 2026-09-06T10:20:01  (wall 358s; sum of per-case seconds is process-internal time only — see above)

========================================================================
SCORE: 17/20 passed  (312s summed per-case)
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

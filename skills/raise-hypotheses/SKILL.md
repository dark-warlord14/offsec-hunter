---
name: raise-hypotheses
description: Step 3 of offsec-hunter. Cheap, wide fan-out — dispatch many shallow subagents on a fast model to generate vulnerability hypotheses tied to the target vuln class and the mapped sinks. Optimizes recall, not precision.
---

# raise-hypotheses — step 3

Generate many candidate vulnerabilities. Optimize for **recall, not precision** — a later
step breaks them. Writes `hunts/<VULN>/hypotheses.jsonl`.

## Gate

Read `surface-map.json` and `hunts/<VULN>/target.md`. If `target.md` is missing or stale,
stop: **"no fresh `target.md` — run scope-target first."**

## Procedure

Dispatch **many shallow subagents on a cheap/fast model** (see the offsec-hunter platform
guide), each chasing **one** hypothesis tied to the target vuln class, a mapped sink, and
the **confirmed delivery vector + attacker position** from `target.md` — e.g. "does any
handler fetch a user-supplied URL without an allowlist?", or "does the file parser trust a
length field from the input file?".

Each subagent returns a **candidate**, not a verdict, and returns it **untagged**: keyed by
`sink`, with the suspected attacker-controlled source, the path/mechanism between them, and
a rationale. Subagents never assign `id` or `family` — under subagent isolation, parallel
subagents can't see each other's ids and would collide. The **orchestrator is the sole id
authority**: it takes each returned candidate and writes the line to
`hunts/<VULN>/hypotheses.jsonl`, assigning the globally-unique `id` (`h-N`) and `family`,
and stamping the current `"round": N`:

```json
{"id": "h-1", "family": "f-ssrf-fetch", "sink": "sink-3", "round": 2, "suspected_source": "body.url", "path": "POST /fetch -> validate() -> http.get()", "rationale": "no allowlist visible"}
```

This step is **round-aware**: on each round the orchestrator tells you which families to
expand and which mapped sinks are still uncovered. Because a dispatched subagent sees only
its prompt, **inject its context** — pass `output_root`, `target_root`, the exact artifact
paths to read (`surface-map.json`, `hunts/<VULN>/target.md`), the assigned `sink-N` id and
family, and a one-line threat-model summary.

Record the step done in `state.json` with the `input_hash` of `target.md`.

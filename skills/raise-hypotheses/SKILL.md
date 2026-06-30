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

Each subagent returns a **candidate**, not a verdict: the sink, the suspected
attacker-controlled source, and the path between them. Append candidates to
`hunts/<VULN>/hypotheses.jsonl`, one JSON object per line:

```json
{"id": "h-1", "sink": "sink-3", "source": "body.url", "path": "POST /fetch -> validate() -> http.get()", "rationale": "no allowlist visible"}
```

Record the step done in `state.json` with the `input_hash` of `target.md`.

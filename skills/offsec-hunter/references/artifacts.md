# Artifacts — layout, roots, gating, state

All run artifacts live under the **output root**. Two roots, resolved once by the
orchestrator and recorded in `state.json`:

- **Target root** — code being hunted; all artifact file paths are relative to it. Never
  assumed to be the current directory.
- **Output root** — where `.offsec-hunter/` is written. Default
  `<target-root>/.offsec-hunter/` (gitignored); override to an explicit dir, or
  `~/.offsec-hunter/<target-id>/` when the target tree is read-only.

## Tree

```
.offsec-hunter/
  state.json                  # roots, mode, per-step status, input hashes, steer log
  surface-map.json            # TARGET-level, commit-stamped, shared across vuln classes
  hunts/
    <VULN>/                   # per-hunt namespace (e.g. SSRF, RCE)
      target.md
      hypotheses.jsonl
      survivors.jsonl
      findings.md
      findings.json
      pocs/
        finding-001.md
```

## state.json

```json
{
  "target_root": "/abs/path/to/target",
  "output_root": "/abs/path/to/target/.offsec-hunter",
  "mode": "interactive",
  "vuln": "SSRF",
  "steps": {
    "map-attack-surface": {"status": "done", "artifact": "surface-map.json", "commit": "<HEAD>", "at": "<iso8601>"},
    "scope-target":       {"status": "done", "artifact": "hunts/SSRF/target.md", "input_hash": "<sha256 of surface-map.json>", "at": "<iso8601>"},
    "raise-hypotheses":   {"status": "pending"},
    "break-hypotheses":   {"status": "pending"},
    "prove-exploit":      {"status": "pending"}
  },
  "steer_log": [
    {"at": "<iso8601>", "feedback": "focus on auth-bypass", "edited": "hunts/SSRF/target.md", "reran_from": "raise-hypotheses"}
  ]
}
```

## Gating & staleness

- A step refuses to run when its input artifact is missing and prints the exact fix
  (e.g. "no `surface-map.json` — run `map-attack-surface` first").
- `surface-map.json` is **fresh** iff its `commit == git rev-parse HEAD`; otherwise rebuild.
- Each downstream artifact records the hash of its inputs (`input_hash` in `state.json`).
  If an input changed since the artifact was written, the artifact is **stale** — re-run
  that step. This is what makes steering re-run exactly the affected steps.

## Round state & family registry

The hunt runs in rounds; all round state lives in `state.json` so a fresh or compacted
orchestrator resumes mid-hunt (a **resumable** loop). Each round starts by reading
`state.json`.

```json
{
  "round": 2,
  "dry_streak": 1,
  "families": [
    {"id":"f-deser","label":"PHP object deserialization","status":"open",
     "agents":2,"hypotheses":["h-1","h-4"],"last_new_round":2,"notes":"..."}
  ],
  "round_log": [
    {"round":1,"raised":12,"survived":2,"new_families":5,"redirects":["blocked f-cache"]},
    {"round":2,"raised":9,"survived":0,"new_families":0,"redirects":["blocked f-deser"]}
  ]
}
```

- `families[].status` ∈ `open | blocked`. A blocked family reopens only on a
  materially-new mechanism.
- A round is **dry** when it yields no new survivor AND no materially-new family. Exit after 2 dry
  rounds in a row; log a loud warning when `round > 6`.

## Stable ids & forward references

Every artifact carries ids so a finding traces back to a mapped sink:

- `surface-map.json` sink: `"id": "sink-3"`.
- `hypotheses.jsonl` line: adds `"family"` and `"sink"`.
- `survivors.jsonl` line: adds `"hypothesis"`, `"sink"`, `"chain": [...]` (ordered hypothesis
  ids for multi-step chains), `"severity"`, `"confidence"`.
- `findings.json`: adds `"survivor"`, `"hypothesis"`, `"sink"`, `"severity"`,
  `"confidence"` — the full trace `finding → survivor → hypothesis → sink`.

`run.md` is a human-readable dashboard written at loop exit (rounds, family registry,
per-round lines, findings with trace ids).

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
        finding-001.sh
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

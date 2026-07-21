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

## state.json (canonical example)

```json
{
  "target_root": "/abs/path/to/target",
  "output_root": "/abs/path/to/target/.offsec-hunter",
  "mode": "interactive",
  "vuln": "RCE",
  "round": 2,
  "dry_streak": 1,
  "families": [
    {"id": "f-deser", "label": "PHP object deserialization", "status": "open",
     "agents": 2, "hypotheses": ["h-1", "h-4"], "last_new_round": 2, "notes": "gadget chain via wp_options autoload"}
  ],
  "steps": {
    "map-attack-surface": {"status": "done", "artifact": "surface-map.json", "commit": "<HEAD>", "at": "<iso8601>"},
    "scope-target":       {"status": "done", "artifact": "hunts/RCE/target.md", "input_hash": "<sha256>", "at": "<iso8601>"},
    "raise-hypotheses":   {"status": "looping", "last_round": 2},
    "break-hypotheses":   {"status": "looping", "last_round": 2},
    "prove-exploit":      {"status": "pending"}
  },
  "round_log": [
    {"round": 1, "raised": 12, "survived": 2, "new_families": 5, "redirects": ["blocked f-cache", "boost f-deser"]},
    {"round": 2, "raised": 9, "survived": 0, "new_families": 0, "redirects": ["blocked f-deser"]}
  ],
  "steer_log": [
    {"at": "<iso8601>", "feedback": "focus on auth-bypass", "edited": "hunts/RCE/target.md", "reran_from": "raise-hypotheses"}
  ]
}
```

## Gating & staleness

- A step refuses to run when its input artifact is missing and prints the exact fix
  (e.g. "no `surface-map.json` — run `map-attack-surface` first").
- `surface-map.json` is **fresh** iff its `commit == git rev-parse HEAD`; otherwise rebuild.
- Each downstream artifact records the hash of its inputs (`input_hash` in `state.json`).
  The `input_hash` staleness gate **governs steering only** (user-driven redirects that
  re-run only the affected steps). Inside the loop, `raise-hypotheses` and
  `break-hypotheses` re-run every round regardless of whether `target.md` changed; this
  keeps the round hypothesis-space diverse and fresh.

## Round state & family registry

The hunt runs in rounds; all round state lives in `state.json` so a fresh or compacted
orchestrator resumes mid-hunt (a **resumable** loop). Each round starts by reading
`state.json`. See the canonical example above for the complete structure including
`round`, `dry_streak`, `families`, `round_log`, and step status fields.

- `families[].status` ∈ `open | blocked`. A blocked family reopens only on a
  materially-new mechanism.
- A round is **dry** when it yields no new survivor AND no materially-new family. Exit after 2 dry
  rounds in a row; log a loud warning when `round > 6`.

## Stable ids & forward references

Every artifact carries ids so a finding traces back to a mapped sink. The **orchestrator is
the sole id authority**: raise/break subagents return untagged candidates keyed by `sink`
(with mechanism/rationale, or `hypothesis`/`chain`/`severity`/`confidence`); the orchestrator
assigns the globally-unique `id` (`h-N` / `s-N`) and `family` only when it writes the line.

- `surface-map.json` sink: `"id": "sink-3"`.
- `hypotheses.jsonl` line: adds `"family"`, `"sink"`, and `"round"` (the round it was
  raised in).
- `survivors.jsonl` line: adds `"hypothesis"`, `"sink"`, `"chain": [...]` (ordered hypothesis
  ids for multi-step chains), `"severity"`, `"confidence"`, and `"round"` (the round it was
  broken in).
- `findings.json`: adds `"survivor"`, `"hypothesis"`, `"sink"`, `"severity"`,
  `"confidence"` — the full trace `finding → survivor → hypothesis → sink`.

Every `hypotheses.jsonl`/`survivors.jsonl` line carries `"round"`. "This round" means
`line.round == state.round` — that is how `break-hypotheses` selects only the hypotheses
just raised, and how synthesis counts only this round's new survivors/families.

**Survivor dedup key**: before appending, `break-hypotheses` dedups on write by
`hypothesis + sink + chain` — a survivor matching an existing line on that key is not
re-appended (e.g. re-confirmed after a redirect, or reached via more than one route).

`run.md` is a human-readable dashboard written at loop exit (rounds, family registry,
per-round lines, findings with trace ids).

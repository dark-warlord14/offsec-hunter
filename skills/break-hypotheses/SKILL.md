---
name: break-hypotheses
description: Step 4 of offsec-hunter. Deep adversarial validation — dispatch stronger-model subagents that try to break each hypothesis, not confirm it. Keeps only candidates that survive every guard and are reachable per the confirmed threat model.
---

# break-hypotheses — step 4

Adversarially validate each candidate. The job is to **try to break the claim**, not to
confirm it. Writes `hunts/<VULN>/survivors.jsonl`.

## Gate

Read `hunts/<VULN>/hypotheses.jsonl`. If it is missing, stop:
**"no `hypotheses.jsonl` — run raise-hypotheses first."**

## Procedure

For each candidate, dispatch a **stronger-model subagent** (see the offsec-hunter platform
guide) to trace it across files and attempt to refute it:

- Is the source **actually** attacker-controlled?
- Does it **survive every guard/gate** between source and sink?
- Is it reachable **per the confirmed threat model** (the attacker position and delivery
  vector in `target.md`)?
- Does the result meet the **confirmed win condition** (so a DoS or memory-safety crash
  counts when the user scoped it in)?
- Can it **chain** with another candidate or a **dependency bug** (when dependency sinks
  exist — see map-attack-surface) to reach the win condition? A survivor may be a
  multi-step chain (e.g. auth-bypass → RCE).

Drop anything that fails any check. Append confirmed-reachable survivors to
`hunts/<VULN>/survivors.jsonl`, carrying the candidate fields plus the guards examined and
why they hold/fail. Each survivor references its `hypothesis` and `sink` ids, an ordered
`chain` (hypothesis ids), and `severity` + `confidence`:

```json
{"id":"s-2","hypothesis":"h-4","sink":"sink-3","chain":["h-7","h-4"],"severity":"high","confidence":"medium","guards":"nonce check bypassed via ..."}
```

Record the step done in `state.json`.

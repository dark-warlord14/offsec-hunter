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

Process only **this round's** hypotheses — lines where `line.round == state.round`; earlier
rounds' hypotheses were already broken (or already survived) in their own round.

For each current-round candidate, dispatch a **stronger-model subagent** (see the offsec-hunter platform
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

Because a break subagent sees only its prompt, **inject its context** — pass `output_root`,
`target_root`, the exact artifact paths to read (`surface-map.json`, `target.md`,
`hypotheses.jsonl`), and the **full fields of the specific candidate** being refuted
(`id`, `sink`, `suspected_source`, `path`, `mechanism`).

Drop anything that fails any check. Each subagent returns its verdict **untagged** — no
`id`: it keys the survivor by `hypothesis` and `sink`, carrying the candidate fields, an
ordered `chain` (hypothesis ids), `severity` + `confidence`, and the guards examined and
why they hold/fail. Subagents never assign `id` — the **orchestrator is the sole id
authority**: it writes the survivor line to `hunts/<VULN>/survivors.jsonl`, assigning the
globally-unique `id` (`s-N`) and stamping the current `"round": N`:

```json
{"id":"s-2","hypothesis":"h-4","sink":"sink-3","chain":["h-7","h-4"],"round":2,"severity":"high","confidence":"medium","guards":"nonce check bypassed via ..."}
```

**Dedup on write**: before appending, the orchestrator checks the survivor key
(`hypothesis` + `sink` + `chain`) against existing lines in `survivors.jsonl`. If a survivor
with the same key already exists (e.g. re-confirmed after a redirect, or reached via more
than one route in the same round), skip the append — de-duplicate rather than write a
second line for the same underlying bug.

Record the step done in `state.json`.

# offsec-hunter — autonomous round-loop design

**Date:** 2026-07-21
**Status:** approved (brainstorming)
**Scope:** Additive upgrade of offsec-hunter from a single-pass pipeline to an
autonomous, round-based hunt. Integration is **Plan A** — the loop bolts onto the
existing flow; single-pass behaviour is preserved (rounds = 1).

## Motivation

offsec-hunter today is a linear five-step pass (map → scope → raise → break → prove).
Steering exists but is user-driven *after* a run. We want the flow to hunt the way a
strong human red-teamer does: launch a diverse portfolio of ideas, synthesize, redirect
away from crowded/stalled ideas, keep incompatible routes alive, and **not stop after the
first wave fails** — while chaining bugs across the target and its dependencies.

This doctrine is drawn from an autonomous pre-auth-RCE hunting prompt. The transferable
ideas: a round loop with synthesis/redirect, an approach-family registry, anti-domination
+ diversity, blocked-route tracking, dependency auditing + bug-chaining, and explicit
persistence.

## Non-goals

- **No skill renames.** Directory/skill names stay (`map-attack-surface`, `scope-target`,
  `raise-hypotheses`, `break-hypotheses`, `prove-exploit`). Renaming breaks `plugin.json`,
  tests, and every cross-reference for no functional gain.
- **No new step / no new skill.** Plan A keeps the five steps; the loop lives in the
  orchestrator.
- **No gate-error-format change** this pass.
- **No budget-cap / max-round / found-enough stop rule.** The only stop rule is dry-rounds
  (below), with a soft backstop warning.

## Architecture — Plan A

Steps 1 (map) and 2 (scope) run once. Steps 3 (raise) and 4 (break) become the body of a
**round loop** owned by the orchestrator. Step 5 (prove) runs once at loop exit.

```
1 map     (once)
2 scope   (once)
 +----------------- ROUND LOOP -----------------+
 | read state.json (resume point)               |
 | 3 raise  -> hypotheses.jsonl (this round)     |
 | 4 break  -> survivors.jsonl (this round)      |
 | SYNTH: update family registry, mark blocked,  |
 |        redirect, write round summary          |
 | 2 dry rounds in a row?  --no--> round++       |
 +------------------- yes ----------------------+
5 prove   -> findings.{md,json} + pocs/ (additive)
run.md    (dashboard, written at loop exit)
```

**Stop rule:** exit the loop after **2 consecutive dry rounds**. A round is *dry* when it
produces **no new survivor AND no materially-new family**. Soft backstop: if `round > 6`,
log a loud warning (the loop still obeys the dry-round rule; the warning is auditability,
not a hard cap).

## Family registry

The registry groups hypotheses by **research idea**, not by wording, and lives in
`state.json` (orchestrator-managed only). Each family:

```json
{
  "id": "f-deser",
  "label": "PHP object deserialization",
  "status": "open",
  "agents": 2,
  "hypotheses": ["h-1", "h-4"],
  "last_new_round": 2,
  "notes": "gadget chain via wp_options autoload"
}
```

- `status`: `open | blocked`. **Blocked** = the family produced nothing new and is stalled.
- Reopen a blocked family **only** when a subagent proposes a *materially-new mechanism* —
  not a reworded version of an already-tried idea.

### Synthesis + redirect (orchestrator, end of each round)

1. Read compact summaries only (counts + this round's jsonl), never full subagent
   transcripts.
2. Count new survivors and new families this round.
3. Any family with nothing new → mark **blocked**.
4. Plan the next round's assignments (anti-domination + diversity):
   - Pull agents off crowded and blocked families.
   - Point freed agents at **mapped sinks no family covers yet** (uncovered `sink-N`).
   - Keep at least one agent on each still-productive incompatible route so routes stay
     alive across rounds.
5. Cross-pollinate only after independent families have developed far enough to expose
   real strengths/gaps.
6. Write a one-line round summary to `state.json.round_log` and to `run.md`.
7. Update `dry_streak`; exit if it reaches 2.

## Dependency chaining

Dependency auditing is **conditional** — vendored dependencies are not always present.
Only index them when the target actually ships them.

- **map-attack-surface**: **if** the target vendors dependencies (common layouts:
  `third_party/`, `vendor/`, `node_modules/`, `deps/`, or a lockfile-declared tree), index
  high-risk code in them as sinks (dependency sinks get `sink-N` ids like any other), so
  dep bugs are reachable candidates. If no vendored deps are present, skip this — no dep
  sinks, no error.
- **break-hypotheses** gains a chaining check: "can this candidate chain with another
  candidate or a dependency bug (when dep sinks exist) to reach the win condition?" A
  survivor may therefore be a **multi-step chain** (e.g. auth-bypass → RCE), recorded as an
  ordered `chain`.

## Traceable IDs + references

Every artifact carries stable ids and forward references so a finding traces back to a
mapped sink.

- `surface-map.json`: each sink has a stable `id` (`sink-3`).
- `hypotheses.jsonl`: each line carries `family` and `sink` ids.
- `survivors.jsonl`: carries its `hypothesis` id, `sink` id, and `chain: [...]` (ordered
  step ids for multi-step chains).
- `findings.json`: carries the full trace `finding → survivor → hypothesis → sink`.
- Shared field set everywhere a candidate/finding appears: `severity`, `confidence`.

Example survivor:

```json
{"id":"s-2","hypothesis":"h-4","sink":"sink-3","chain":["h-7","h-4"],
 "severity":"high","confidence":"medium","guards":"nonce check bypassed via ..."}
```

## run.md dashboard

Written by the orchestrator at loop exit — one human-readable summary of the whole run:
rounds executed, family registry (open/blocked + counts), per-round line
(`R2: 12 raised → 2 survived, blocked f-cache, boosting f-deser`), and the final findings
with their trace ids. Steered re-runs append, matching `prove-exploit`'s additive merge.

## Modes

- **interactive** — the orchestrator prints the per-round synth line as it goes; it does
  **not** block between rounds (the hunt stays autonomous). Post-run steering is unchanged.
- **headless** — the orchestrator logs the same per-round line. Loop runs autonomously.

## Research-driven robustness fixes

Validated against the Agent Skills open standard and Anthropic's long-running-agent
harness guidance.

### 1. Subagent context-injection contract (critical)

A subagent sees **only** its delegation prompt plus CLAUDE.md — not the orchestrator's
invoked skills, conversation, or files already read. It cannot "just read `target.md`"
unless told the path.

Therefore every raise/break delegation prompt MUST inject:

- `output_root` and `target_root` (absolute paths from `state.json`),
- the exact artifact paths the subagent should read (e.g. `<output_root>/surface-map.json`,
  `<output_root>/hunts/<VULN>/target.md`),
- the assigned `sink-N` id and its family,
- a one-line threat-model summary (attacker position + delivery vector + win condition).

The family registry stays orchestrator-only; a subagent receives only its slice in-prompt.

### 2. Resumable loop (critical)

Long loops fill the orchestrator's window. All round state lives in `state.json`
(`round`, `dry_streak`, `families`, `round_log`). **Each round starts by reading
`state.json`**, so a fresh or compacted orchestrator resumes mid-hunt rather than
restarting. `state.json` is the coordination substrate — the analogue of Anthropic's
`claude-progress.txt`.

### 3. Orchestrator context hygiene

Between rounds the orchestrator reads compact summaries (counts + the round's jsonl),
never full subagent transcripts, and writes a one-line round summary. The per-round agent
cap stays. This avoids the "tried to do too much per window" failure mode.

### 4. Frontmatter hygiene

Keep all SKILL.md frontmatter portable and safe: no angle brackets (`<` / `>`) anywhere in
frontmatter, `description` ≤ 1024 chars, `name` kebab-case matching the folder, and no
`model` / `allowed-tools` keys unless deliberately intended (they trigger approval prompts
and reduce portability).

## state.json — new shape

```json
{
  "target_root": "/abs/path/to/target",
  "output_root": "/abs/path/to/target/.offsec-hunter",
  "mode": "interactive",
  "vuln": "RCE",
  "round": 2,
  "dry_streak": 1,
  "families": [
    {"id":"f-deser","label":"PHP object deserialization","status":"open",
     "agents":2,"hypotheses":["h-1","h-4"],"last_new_round":2,"notes":"..."}
  ],
  "steps": {
    "map-attack-surface": {"status":"done","artifact":"surface-map.json","commit":"<HEAD>","at":"<iso8601>"},
    "scope-target":       {"status":"done","artifact":"hunts/RCE/target.md","input_hash":"<sha256>","at":"<iso8601>"},
    "raise-hypotheses":   {"status":"looping","last_round":2},
    "break-hypotheses":   {"status":"looping","last_round":2},
    "prove-exploit":      {"status":"pending"}
  },
  "round_log": [
    {"round":1,"raised":12,"survived":2,"new_families":5,"redirects":["blocked f-cache","boost f-deser"]},
    {"round":2,"raised":9,"survived":0,"new_families":0,"redirects":["blocked f-deser"]}
  ],
  "steer_log": []
}
```

## Files touched

| File | Change |
|---|---|
| `skills/offsec-hunter/SKILL.md` | +++ round loop, synth/redirect, stop rule, context-injection + resumability rules, run.md |
| `skills/offsec-hunter/references/artifacts.md` | +++ family registry, round state, traceable-id conventions, resumable-loop note |
| `skills/map-attack-surface/SKILL.md` | + stable sink ids, index `third_party/` deps as sinks |
| `skills/raise-hypotheses/SKILL.md` | + round-aware, family + sink ids on each line, context-injection contract |
| `skills/break-hypotheses/SKILL.md` | + chaining check, `chain`/trace fields, emits stall signal for synthesis |
| `skills/prove-exploit/SKILL.md` | ~ carry trace ids + severity/confidence; contribute to run.md |
| `skills/scope-target/SKILL.md` | ~ nearly untouched |
| `tests/` | + contract assertions for new state.json fields + traceable ids |

## Testing

- Static-contract tests assert the new `state.json` fields (`round`, `dry_streak`,
  `families`, `round_log`) and the id/ref conventions across artifacts.
- Behavioral-recall test covers the loop doctrine (dry-round exit, blocked/reopen,
  redirect) at instruction level.
- A `rounds = 1` path must reproduce today's single-pass behaviour (regression guard).

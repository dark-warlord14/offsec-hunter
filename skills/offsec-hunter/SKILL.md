---
name: offsec-hunter
description: Use when hunting for externally reachable, exploitable vulnerabilities in a codebase — triggered by an HTTP request, a chain of HTTP requests, or a WebSocket message from an unauth or normal-user session (the default threat model, with non-web targets scoped in at the scope-target checkpoint). Covers SSRF, RCE, SQLi, SSTI, auth-bypass, IDOR and other high-impact classes. Triggered by /offsec-hunter with a vuln-type argument.
---

# offsec-hunter — orchestrator

This is part of an **authorized** security task: identify vulnerabilities that are
**externally reachable and exploitable** per the target model confirmed in `scope-target`.

**The goal is not code review. The goal is to break the target.**

This skill is the **orchestrator**. It runs six artifact-gated steps, each defined in a
reference file, each gated on the previous one's file artifact:

1. **Map attack surface** → `references/step-1-map-attack-surface.md` → `surface-map.json`
   — **comprehension only: no vuln classes, no risk verdicts, no guard analysis, no sink hunting.**
2. **Scope target** → `references/step-2-scope-target.md` → `hunts/<VULN>/target.md`
   — confirm the vuln class and threat model; interactive asks, headless logs.
3. **Locate sinks** → `references/step-3-locate-sinks.md` → `hunts/<VULN>/sinks.json`
   — **security judgment begins here**; sole assigner of `sink-N` ids.
4. **Raise hypotheses** → `references/step-4-raise-hypotheses.md` → `hypotheses.jsonl`
   — cheap wide fan-out, optimise recall not precision.
5. **Break hypotheses** → `references/step-5-break-hypotheses.md` → `survivors.jsonl`
   — adversarial: try to refute each claim, not confirm it.
6. **Prove exploit** → `references/step-6-prove-exploit.md` → `findings.{md,json}` + `pocs/`
   — no PoC, no finding.

User-facing mental model: **understand → goal → hunt → exploit**.

Steps 1–2 carry no security verdicts. **Security judgment begins at step 3.**

## How this skill runs

Instruction-driven and platform-neutral. Map every action ("dispatch a subagent",
"cheap model for breadth, strong model for validation") to your platform's tools per the
**offsec-hunter platform guide** (`references/platform-tools.md`). Artifact layout, the
two roots, `state.json`, and the gating/staleness rules are defined in the **offsec-hunter
artifacts guide** (`references/artifacts.md`).

### Enforcement — read this first

Reliability comes from **artifact-gating**, not trust:

1. **Before step 1**, resolve the two roots and the run mode, then write `state.json`.
   Every later step reads them from there. Do this before any other action.
2. **Before executing step N, read its reference file** (`references/step-N-<name>.md`)
   and follow it. Do not execute a step from the one-line summary above — the summary
   names the step and its single hardest constraint; the reference file carries the
   procedure, the gate, and the schema.
3. Create one task/todo per step and complete them in order.
4. Each step writes a file artifact; the next step begins by reading it. Never start a
   step whose input artifact is missing or stale.

### Roots — resolve once

Resolve two roots and record them in `state.json`; every step reads them from there:

- **Target root** — the code being hunted. All artifact paths are relative to it. Never
  assume it equals the current directory — confirm it.
- **Output root** — where `.offsec-hunter/` is written. Default
  `<target-root>/.offsec-hunter/` (gitignored). Override with an explicit out-dir, or fall
  back to `~/.offsec-hunter/<target-id>/` when the target tree is read-only.

### Mode — interactive or headless

Declare the run mode and record it in `state.json`:

- **interactive** (a human is present): `scope-target` stops and asks the user to
  confirm/edit the target model.
- **headless** (autonomous/agent run): `scope-target` accepts its proposed model and logs
  the assumption loudly. No step blocks on input.

### Progress

Print a compact progress line read from `state.json` (e.g. `✅ 1–2  ▶ 3`) so a returning
human or a resuming agent knows the next action.

## Round loop (steps 4–5)

Steps 1 (map), 2 (scope) and 3 (locate) run once. Steps 4 (raise) and 5 (break) are the
body of a **round loop**. Step 6 (prove) runs once at loop exit. With a single productive
round this is exactly the old single-pass flow.

**Initialization:** Before the first `raise-hypotheses` run, the orchestrator initializes
`round=1`, `dry_streak=0`, `families=[]`, and `round_log=[]` in `state.json`.

The loop **drives raise/break by round**, independent of staleness. They re-run every
round regardless of whether `target.md` changed; the staleness gate applies only to
steering (user-driven redirects).

Each round:

1. **Read `state.json`** for the resume point (`round`, `dry_streak`, `families`). This is
   what makes the loop **resumable** — a fresh or compacted orchestrator continues instead
   of restarting. Each step tracks its completion in `state.json` with a `status` field
   and `last_round`; re-running a step for a round it already recorded is a **no-op**
   (already recorded in `last_round`), so crashes and resume never double-append.
2. Run `raise-hypotheses` then `break-hypotheses` for this round.
3. **Synthesize** (orchestrator, reading only compact summaries + this round's jsonl —
   never full subagent transcripts):
   - Count new survivors and new families.
   - **Assemble chains** from the round's candidate set: for each chainable survivor, the
     orchestrator constructs the ordered `chain` field (a list of hypothesis ids) by
     matching it with other survivors that can chain together. Break subagents only flag
     chainability; the orchestrator assembles the multi-step chain.
   - Mark any family that produced nothing new as **blocked** (materially-new means a
     **distinct sink** or a **distinct guard-bypass mechanism**, not a distinct label). A
     blocked family reopens **only when** a hypothesis names a guard or step absent from
     that family's recorded mechanisms — synthesis makes this determination by comparing
     the `mechanism` field machine-to-machine, never by comparing prose or labels.
   - **Redirect**: pull agents off crowded/blocked families and point them at sinks in
     `sinks.json` no family covers yet; keep at least one agent on each still-productive incompatible
     route so routes stay alive across rounds.
   - Append a one-line entry to `state.json.round_log`. Increment
     `dry_streak` on a dry round; reset it to 0 on a productive round (one that produced a
     new survivor or a materially-new family).
4. **Stop rule**: exit after **2 consecutive dry rounds** (a dry round = no new survivor
   AND no materially-new family). Soft backstop: log a loud warning when `round > 6` (the dry-round
   rule still governs; the warning is auditability, not a hard cap).

### Context-injection contract (critical)

A subagent sees only its delegation prompt plus whatever always-on project context the
platform auto-loads (`CLAUDE.md` on Claude Code, `AGENTS.md` on Codex) — not the orchestrator's
conversation or reference files, or files already read. Every raise/break delegation prompt MUST
**inject**: `output_root` and `target_root`, the exact artifact paths to read, the assigned
`sink-N` id + its family, and a one-line threat-model summary. The family registry stays
orchestrator-only; a subagent receives only its slice in-prompt.

**The orchestrator is the sole id authority.** Under subagent isolation, parallel raise/break
subagents cannot see each other's ids and would collide if left to invent their own. So
subagents never assign `h-N`, `family`, or `chain`: they return untagged judgments keyed
by `sink` — `mechanism`/`rationale` (raise) or `severity`/`confidence` + a chainability
flag (break), never a built chain. Only the orchestrator assigns globally-unique `h-N`
ids and `family` ids, assembles the ordered `chain` from the round's full candidate set,
dedups, and writes the line to `hypotheses.jsonl` or `survivors.jsonl`.

### run.md dashboard

The orchestrator **regenerates** `run.md` from `state.json` + `findings.json` on **any** step-6
completion (loop exit or steered re-run). The dashboard shows: rounds executed, the family
registry (open/blocked + counts), the per-round lines, and the final findings with their
trace ids. This single-owner regenerate ensures consistency across steered re-runs (idempotent,
no appending).

## Vuln class

Hunt for: **the vuln class the user provided when invoking this skill (or `broad` if none)**

The chosen class is confirmed inside `scope-target` and written into `target.md`. If no
class was provided: interactive → `scope-target` asks; headless → default to `broad` and
log it.

## Scope — the default threat model (a proposal, not a fixed rule)

The default `scope-target` starts from; confirmed or overridden per target there, never
assumed silently:

- Default attacker position: **unauthenticated or normal-user**.
- Default delivery vector: an external request — **HTTP, a chain of HTTP requests, or a
  WebSocket message**.
- Default impact: high-impact classes (RCE / SSRF / SQLi / SSTI / auth-bypass / IDOR / …).

Held regardless of target and **not** softened at the checkpoint:

- **m2m-auth-gated** calls are **out of scope** — UNLESS an auth bypass lets an outsider
  reach them. That bypass is itself the finding.
- Do **not** lean on memory artifacts or other projects' data. Build the model from, and
  validate against, this target's actual current code.

## Budget orchestration

Cap concurrent subagents. Cheap/fast model for breadth (`raise-hypotheses`); escalate to a
stronger model only on survivors (`break-hypotheses`); reserve the orchestrator (strongest
model) for `prove-exploit`. The biggest saving is reusing a fresh map
(`map-attack-surface` skip).

## Steering — redirecting a run

A completed run is not the end. If the user is unsatisfied, redirect by editing the
artifact at the right level and re-running only the steps that go stale:

| Dissatisfaction | Edit | Re-runs |
|---|---|---|
| Missed an entry point or flow | `surface-map.json` | 1 → 2–6 |
| Wrong goal / class / attacker position | `target.md` | 3–6 |
| Missed a sink | `sinks.json` | 4–6 |
| Add or restore a lead | `hypotheses.jsonl` | 5–6 |
| Wrongly killed a candidate | annotate the dropped candidate | 5–6 (that one) |
| PoC doesn't fire | the finding | 6 (that finding) |

After step 6: interactive → offer "not satisfied? tell me how to redirect"; headless →
accept a feedback string. Map the feedback to the artifact level above, edit/annotate that
artifact (so the staleness check fires), append the steer to the `state.json` steer log,
and re-run from there. Steered re-runs **merge additively** (see `prove-exploit`); they
never overwrite a confirmed finding.

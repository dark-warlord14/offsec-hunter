---
name: offsec-hunter
description: Use when hunting for externally reachable, exploitable vulnerabilities in a codebase — triggered by an HTTP request, a chain of HTTP requests, or a WebSocket message from an unauth or normal-user session (the default threat model, with non-web targets scoped in at the scope-target checkpoint). Covers SSRF, RCE, SQLi, SSTI, auth-bypass, IDOR and other high-impact classes. Triggered by /offsec-hunter with a vuln-type argument.
---

# offsec-hunter — orchestrator

This is part of an **authorized** security task: identify vulnerabilities that are
**externally reachable and exploitable** per the target model confirmed in `scope-target`.

**The goal is not code review. The goal is to break the target.**

This skill is the **orchestrator**. It runs five composable skills, each gated on the
previous one's file artifact:

1. `map-attack-surface` — recon → `surface-map.json`
2. `scope-target` — confirm the hunting goal → `hunts/<VULN>/target.md`
3. `raise-hypotheses` — cheap fan-out, recall → `hunts/<VULN>/hypotheses.jsonl`
4. `break-hypotheses` — strong adversarial validation → `hunts/<VULN>/survivors.jsonl`
5. `prove-exploit` — confirmed findings + working PoC → `hunts/<VULN>/findings.{md,json}` + `pocs/`

User-facing mental model: **recon → goal → exploit**.

## How this skill runs

Instruction-driven and platform-neutral. Map every action ("dispatch a subagent",
"cheap model for breadth, strong model for validation") to your platform's tools per the
**offsec-hunter platform guide** (`references/platform-tools.md`). Artifact layout, the
two roots, `state.json`, and the gating/staleness rules are defined in the **offsec-hunter
artifacts guide** (`references/artifacts.md`).

### Enforcement — read this first

Reliability comes from **artifact-gating**, not trust:

1. Create one task/todo per step and complete them in order.
2. Each step writes a file artifact; the next step begins by reading it. Never start a
   step whose input artifact is missing or stale.
3. Invoke each step **by name** (e.g. "invoke the `scope-target` skill"). Never reach into
   another skill's directory.

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

## Vuln class

Hunt for: **$ARGUMENTS**

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
| Missed an entry point | `surface-map.json` | 1 → 2–5 |
| Wrong goal / class / attacker position | `target.md` | 3–5 |
| Add or restore a lead | `hypotheses.jsonl` | 4–5 |
| Wrongly killed a candidate | annotate the dropped candidate | 4–5 (that one) |
| PoC doesn't fire | the finding | 5 (that finding) |

After step 5: interactive → offer "not satisfied? tell me how to redirect"; headless →
accept a feedback string. Map the feedback to the artifact level above, edit/annotate that
artifact (so the staleness check fires), append the steer to the `state.json` steer log,
and re-run from there. Steered re-runs **merge additively** (see `prove-exploit`); they
never overwrite a confirmed finding.

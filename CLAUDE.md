# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

There is no application code here. This repo **is** a set of seven markdown skills
(`skills/*/SKILL.md`) that instruct an agent how to hunt externally reachable, exploitable
vulnerabilities: an `offsec-hunter` orchestrator plus one skill per step. "Editing the
product" means editing prose in `SKILL.md` / `references/*.md` files. The only executable
code is the bash test harness in `tests/`.

Consequence: the tests are *contract tests over markdown*. Adding, renaming, or rewording a
documented field, filename, or rule will usually break a `grep` assertion in
`tests/test-static-contracts.sh` — update the assertion in the same change, deliberately.

## Commands

```bash
bash tests/run-skill-tests.sh                    # Tier 1: static contract tests (no LLM)
bash tests/test-static-contracts.sh              # same, directly
RUN_BEHAVIORAL=1 bash tests/run-skill-tests.sh   # + Tier 2 behavioral recall (spawns `claude -p`)
CLAUDE_PROMPT_TIMEOUT=240 RUN_BEHAVIORAL=1 bash tests/run-skill-tests.sh
```

There is no build or lint step. Tier 2 is opt-in because it makes real LLM calls; it asserts
that an agent, given the installed skills, *describes* the workflow correctly.

To try a change end-to-end you must install the skills, since a repo checkout is not on the
skill path: `cp -R skills/* ~/.claude/skills/` (use `cp -R`, not a symlink — Codex's scanner
does not follow symlinks), then `/offsec-hunter <VULN>`.

## Architecture

Six sequential steps plus an orchestrator, each gated on the previous step's **file
artifact** — reliability comes from artifact-gating, not from trusting the model:

| Step | Skill | Reads | Writes |
|---|---|---|---|
| 1 | `map-attack-surface` | target code | `surface-map.json` (commit-stamped, comprehension only) |
| 2 | `scope-target` | `surface-map.json` | `hunts/<VULN>/target.md` |
| 3 | `locate-sinks` | `surface-map.json` + `target.md` | `hunts/<VULN>/sinks.json` |
| 4 | `raise-hypotheses` | `sinks.json` | `hypotheses.jsonl` (cheap model, recall) |
| 5 | `break-hypotheses` | `hypotheses.jsonl` | `survivors.jsonl` (strong model, precision) |
| 6 | `prove-exploit` | `survivors.jsonl` | `findings.{md,json}` + `pocs/finding-NNN.md` |

`skills/offsec-hunter/SKILL.md` is the orchestrator; steps 4–5 are the body of an autonomous
round loop that exits after 2 consecutive dry rounds. All round state (`round`, `dry_streak`,
`families`, `round_log`, per-step `status`/`last_round`) lives in `state.json` so a compacted
or crashed orchestrator resumes rather than restarts.

### Invariants to preserve when editing skills

- **Comprehension and security judgment are separate steps.** Steps 1–2 describe how the
  target works and what is being hunted; they carry no vuln classes and no risk verdicts.
  Security judgment begins at `locate-sinks`, which is the sole assigner of `sink-N` ids.
  Do not reintroduce sink or vuln-class labelling into `map-attack-surface`.
- **Reachability is step 1's bound.** `map-attack-surface` records only what external input
  can plausibly reach. This is a factual property, not a verdict, so it survives the
  comprehension-only rule — and it is the only thing keeping that step from becoming an
  unbounded read of the whole codebase. Do not remove it while stripping security framing.
- **Language- and ecosystem-neutral target prose.** Steps 1 and 3 describe the target by
  behaviour ("issues an outbound network request", "starts a subprocess"), never by a
  concrete API name. Paths and extensions in schemas are illustrative placeholders;
  vendored-dependency layouts are examples of a pattern, never an exhaustive list
  (asserted). This is the target-side counterpart to platform-neutral skill bodies.
- **Orchestrator is the sole id authority.** Subagents are isolated and cannot see each
  other's ids, so they return untagged judgments keyed by `sink`. Only the orchestrator
  assigns `h-N`/`s-N` and `family`, assembles the ordered `chain`, dedups, and appends the
  jsonl line. Break subagents only *flag* chainability.
- **Context-injection contract.** A subagent sees only its delegation prompt plus always-on
  project context (`CLAUDE.md` / `AGENTS.md`) — never the orchestrator's conversation or
  invoked skills. Every delegation prompt must inject `output_root`, `target_root`, exact
  artifact paths, the assigned `sink-N` + family, and a one-line threat model.
- **Platform-neutral skill bodies.** Skill prose speaks in actions ("dispatch a subagent on
  a cheap model"); concrete tool names belong only in
  `skills/offsec-hunter/references/platform-tools.md`. Do not put `$ARGUMENTS` in skill
  bodies (asserted).
- **Steps are peer skills, invoked by name.** The orchestrator uses each step with
  `**REQUIRED SUB-SKILL:** Use the \`<name>\` skill` — the idiom superpowers uses, and the
  one thing that reliably gets a sibling skill loaded (asserted). Reaching a sibling's
  directory is **allowed** as a fallback when the platform does not surface it by name. The
  old "no cross-skill relative paths" rule caused a live failure: it read at runtime as
  "do not open sibling files", so no step skill ever loaded and the orchestrator did step
  1's work itself.
- **The orchestrator is the only body guaranteed to be in context.** Its step list carries
  each step's single hardest constraint, so the constraint binds even if the step skill
  never loads. Doing a step's work inline from that summary is never acceptable.
- **Two roots, resolved once.** Target root (code under test) and output root (default
  `<target>/.offsec-hunter/`, or `~/.offsec-hunter/<target-id>/` when the target is
  read-only). Never assume target root == cwd.
- **Staleness vs. rounds.** `input_hash` staleness governs *steering* only. Inside the loop,
  raise/break re-run every round regardless of whether `target.md` changed. `sinks.json` is
  stale when **either** `surface-map.json` or `target.md` changes — a rebuilt map with an
  unchanged threat model must still re-run `locate-sinks`, or the hunt fans out over sinks
  derived from the old map.
- **Additive merge.** Steered re-runs merge; they never overwrite a confirmed finding.

### Where the reasoning lives

`skills/offsec-hunter/references/artifacts.md` is the canonical spec for the artifact tree,
`state.json`, gating/staleness, and the id/dedup rules — read it before changing any schema.
Design rationale is in `docs/superpowers/specs/` (`2026-06-26-offsec-hunter-design.md` for
the overall design, `2026-07-21-autonomous-round-loop-design.md` for the loop,
`2026-08-06-comprehension-first-recon-design.md` for the comprehension/security split and
the prior-art survey behind it, `2026-08-06-skill-invocation-idiom-design.md` for why steps
are peer skills and how the orchestrator invokes them), with task-level plans in
`docs/superpowers/plans/`.
Dated specs and plans are historical records of what was decided when — do not rewrite them
to match later changes.

⚠️ `2026-08-06-single-skill-consolidation-design.md` and its plan are **superseded and
wrong**. They argue that neither platform supports skill-to-skill invocation and collapse
the seven skills into one. That was implemented and reverted the same day — superpowers
demonstrates the opposite. They are kept as a record of the wrong turn; read the invocation
idiom spec instead.

## Conventions

- Bump `version` in `.claude-plugin/plugin.json` for behavioral changes to the skills.
- `.offsec-hunter/` is gitignored — run artifacts are never source.

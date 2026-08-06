# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

There is no application code here. This repo **is** a single markdown skill
(`skills/offsec-hunter/SKILL.md`) whose six steps are reference files under
`skills/offsec-hunter/references/` that instruct an agent how to hunt externally reachable,
exploitable vulnerabilities. "Editing the product" means editing prose in `SKILL.md` /
`references/*.md` files. The only executable code is the bash test harness in `tests/`.

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

| Step | Reference | Reads | Writes |
|---|---|---|---|
| 1 | `references/step-1-map-attack-surface.md` | target code | `surface-map.json` (commit-stamped, comprehension only) |
| 2 | `references/step-2-scope-target.md` | `surface-map.json` | `hunts/<VULN>/target.md` |
| 3 | `references/step-3-locate-sinks.md` | `surface-map.json` + `target.md` | `hunts/<VULN>/sinks.json` |
| 4 | `references/step-4-raise-hypotheses.md` | `sinks.json` | `hypotheses.jsonl` (cheap model, recall) |
| 5 | `references/step-5-break-hypotheses.md` | `hypotheses.jsonl` | `survivors.jsonl` (strong model, precision) |
| 6 | `references/step-6-prove-exploit.md` | `survivors.jsonl` | `findings.{md,json}` + `pocs/finding-NNN.md` |

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
- **One skill, flat references.** `offsec-hunter` is the only `SKILL.md`; the six step
  bodies are `references/step-N-*.md`. Neither platform supports skill-to-skill
  invocation, and Claude Code has no frontmatter for a skill only the orchestrator may
  invoke — so steps must not be skills (both asserted). References are **flat and one
  level deep**: a reference file must never point at another file to read, or Claude may
  read it only partially.
- **`SKILL.md` is the only guaranteed context.** Anything that must hold even if a
  reference is never read belongs in `SKILL.md` — which is why each step line there
  carries its one binding constraint.
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
the prior-art survey behind it, `2026-08-06-single-skill-consolidation-design.md` for the
single-skill consolidation and the platform research behind it), with task-level plans in
`docs/superpowers/plans/`.
Dated specs and plans are historical records of what was decided when — do not rewrite them
to match later changes.

## Conventions

- Bump `version` in `.claude-plugin/plugin.json` for behavioral changes to the skills.
- `.offsec-hunter/` is gitignored — run artifacts are never source.

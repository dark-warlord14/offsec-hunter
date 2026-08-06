# Skill invocation idiom — design

**Date:** 2026-08-06
**Status:** implemented
**Supersedes:** `2026-08-06-single-skill-consolidation-design.md` (reverted; its premise was false)

## Problem

A live Codex run of `$offsec-hunter` executed step 1 by hunting RCE sinks, adjudicating
guards ("this is a hard guard"), and forming verdicts ("critical finding forming") — all of
which step 1 forbids. The session log showed exactly one `<skill>` block loaded
(`offsec-hunter`). No step skill body ever entered context, so the comprehension-only rule
that lives in `map-attack-surface/SKILL.md` was never seen. The agent built a correct
six-step plan from the orchestrator's step list and then did step 1's work inline from a
five-word summary.

## Root cause

The orchestrator's enforcement section said:

> 3. Invoke each step **by name** (e.g. "invoke the `scope-target` skill"). Never reach into
>    another skill's directory.

Two defects in one sentence:

1. **No requirement marker.** "Invoke each step by name" is a description buried as item 3
   in a list. Nothing marks it as mandatory or names the mechanism.
2. **A self-contradiction.** "Never reach into another skill's directory" was authored as a
   *portability* rule (don't hardcode sibling paths in skill prose). At runtime an agent
   reads it as "do not open sibling skill files" — which forbids the fallback that makes
   invocation robust when a platform does not surface a sibling by name.

Result: the agent could not invoke, was told not to read, and so inlined the work.

## Prior art: the superpowers plugin

Verified on disk at
`~/.claude/plugins/cache/claude-plugins-official/superpowers/6.0.3/`.

Superpowers is 13 flat sibling skills that chain into each other constantly, using one
idiom:

```
**REQUIRED SUB-SKILL:** Use superpowers:subagent-driven-development
```

Its own `writing-skills` skill states the rule:

> Use skill name only, with explicit requirement markers:
> ✅ `**REQUIRED SUB-SKILL:** Use superpowers:test-driven-development`
> ❌ `See skills/testing/test-driven-development` (unclear if required)
> ❌ `@skills/testing/test-driven-development/SKILL.md` (force-loads, burns context)

It also reaches sibling directories freely where a *file* is genuinely needed —
`../requesting-code-review/code-reviewer.md`, `../using-superpowers/references/` — and it
carries **no** standalone-trigger guards. Every skill is independently usable.

**Skill-to-skill invocation works.** An earlier investigation concluded the opposite from
the absence of a documented API, while a working implementation was in use in the same
session. That conclusion produced the reverted single-skill consolidation.

## Design

### Steps are peer skills, invoked by name

The orchestrator's step list is the invocation site. Each line carries the requirement
marker, the skill name, its output artifact, **and its single hardest constraint**:

```
1. **REQUIRED SUB-SKILL:** Use the `map-attack-surface` skill → `surface-map.json`
   — comprehension only: no vuln classes, no risk verdicts, no guard analysis, no sink hunting.
```

Bare names, not `offsec-hunter:map-attack-surface`, because namespacing exists only for
plugin-installed skills and this project installs with `cp -R` into the runtime's skills
directory, where skills surface as bare names.

### Reaching a sibling is allowed

The prohibition is deleted and its absence is asserted. `platform-tools.md` maps the action:

| Action | Claude Code | Codex |
|---|---|---|
| "Use the `<name>` skill" | `Skill` tool with that skill's name | available by name; if it does not load, read its `SKILL.md` in the sibling skill directory |

The one thing that is never acceptable is doing a step's work inline from the orchestrator's
summary line.

### Defence in depth

The orchestrator is the only body guaranteed to be in context, so its step list carries each
step's hardest constraint. If a step skill still fails to load, the constraint binds anyway —
step 1 is told, in the orchestrator itself, not to hunt sinks.

## Retained from the reverted consolidation

- Codex subagents **inherit the orchestrator's model**, so model tiering is Claude Code
  only; Codex advises delegation concurrency 1 by default. Both corrected in
  `platform-tools.md` and reflected in the orchestrator's budget section.
- The orchestrator writes `state.json` and reads `artifacts.md` + `platform-tools.md`
  before step 1.
- Per-step binding constraints in the orchestrator step list.

## Retired invariants

- **"No cross-skill relative paths."** Superpowers violates it routinely and correctly. It
  caused a live failure by reading as a runtime prohibition. Replaced by: invoke siblings by
  name, reach their files as a fallback.
- **The one-level-deep reference rule** and the single-skill assertions, which existed only
  to support the reverted layout.

## Known risk

Bare-name invocation from inside a skill body is less certain on Codex than namespaced
plugin invocation, since Codex documents explicit invocation as a user action (`$skill`) and
implicit invocation as description-matching. Mitigations are the requirement marker, the
removed contradiction, the read-the-file fallback, and the per-step binding constraints. If
step skills still fail to load on Codex, the next lever is packaging as a real plugin
(`.claude-plugin/marketplace.json` + `.codex-plugin/plugin.json`, as superpowers does) for
true namespacing — which would change the install path.

## Verification

Tier 1 asserts the orchestrator contains `REQUIRED SUB-SKILL`, forbids inlining a step,
announces each step, and does **not** contain `Never reach into`. Tier 2 asks "does the
orchestrator do each step's work itself?" and checks the agent says the steps are skills,
that it uses them, and that it does not inline them.

Neither tier proves a live agent loads a sibling skill mid-run. Only a real Codex run does:
check the session log for more than one `<skill>` block.

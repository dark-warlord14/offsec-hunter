# Single-skill consolidation — design

**Date:** 2026-08-06
**Status:** ❌ **SUPERSEDED — implemented, then reverted the same day. Its central premise is false.**
**Supersedes:** the "minimal fix" (add an invoke-a-skill row to `platform-tools.md`) proposed and rejected during investigation.

> **Why this was wrong.** This spec claims "there is no skill-to-skill invocation on either
> platform". That is false. The superpowers plugin does it as its core pattern:
> `**REQUIRED SUB-SKILL:** Use superpowers:subagent-driven-development`, and its skills
> reach sibling directories freely (`../requesting-code-review/code-reviewer.md`). The
> conclusion was drawn from the absence of a *documented API* while ignoring a working
> implementation in the same session. The real defect was weak, self-contradicted
> invocation prose in the orchestrator — "Invoke each step by name" with no requirement
> marker, immediately undercut by "Never reach into another skill's directory".
>
> Retained from this work: the Codex model-tiering and fan-out corrections, per-step binding
> constraints in the orchestrator step list, and writing `state.json` before step 1. The
> layout change was reverted. Kept as a record of the wrong turn.

## Problem

A live Codex run of `$offsec-hunter` performed RCE sink-hunting, guard analysis, and
verdict-forming ("Critical finding forming", "This is a hard guard") **inside step 1**,
whose skill body says comprehension only. It then intended to write the class-agnostic
`surface-map.json` from an RCE-shaped search.

Diagnosis from the session log: exactly one `<skill>` block was ever loaded
(`offsec-hunter`). No step skill body entered context. No `state.json` or
`surface-map.json` was written. The agent built a correct six-step plan from the
orchestrator's step list, then executed step 1 from its five-word summary, because the
binding constraints live in `skills/map-attack-surface/SKILL.md`, which never loaded.

Two root causes:

1. The orchestrator instructs: *"Invoke each step **by name** (e.g. 'invoke the
   `scope-target` skill'). Never reach into another skill's directory."* Skill-to-skill
   invocation **does not exist on either platform**, and the second sentence forbids the
   only mechanism that does work — reading the file.
2. Every step skill carries a standalone-trigger guard ("run the `offsec-hunter`
   orchestrator first"). Six skills that refuse to run standalone are not skills; they are
   reference material that the platform has been told to treat as independently
   triggerable.

## Platform research

Sources: [Claude Code skills](https://code.claude.com/docs/en/skills),
[Agent Skills overview](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview),
[skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices),
[Codex build-skills](https://learn.chatgpt.com/docs/build-skills.md),
[Codex subagents](https://developers.openai.com/codex/subagents).

### There is no skill-to-skill invocation on either platform

Both platforms invoke a skill from the **user's** turn — explicitly (`/name`, `$name`) or
implicitly by matching the user's request against the description. Neither documents a
skill calling another skill. The OpenAI docs, for multi-skill workflows, point to
packaging as a plugin rather than inter-skill calls.

On both platforms a skill body enters context exactly one way: something reads the file.
Claude's docs: *"When a Skill is triggered, Claude uses bash to read SKILL.md from the
filesystem... If those instructions reference other files, Claude reads those files too."*

### Claude Code cannot express an orchestrator-only skill

| Frontmatter | User can invoke | Claude can invoke | Description in context |
|---|---|---|---|
| (default) | Yes | Yes | Always |
| `disable-model-invocation: true` | Yes | **No** | No |
| `user-invocable: false` | No | Yes | Always |

Hiding a step skill from implicit matching requires `disable-model-invocation: true`,
which also blocks the orchestrator — the orchestrator *is* Claude. The docs state Claude
Code blocks the call outright. So a step skill is either discoverable and implicitly
triggerable, or unreachable by the orchestrator. **"Only the orchestrator knows about it"
is not expressible as a skill on Claude Code.**

Codex is more capable — `allow_implicit_invocation: false` in `agents/openai.yaml`
suppresses implicit matching while keeping explicit `$skill` — but it does not rescue
Claude Code, and it lives outside `SKILL.md` (Codex `SKILL.md` frontmatter supports only
`name` and `description`), so it is not portable.

### Bundled references are supported on both

Codex: *"A skill is a directory with a `SKILL.md` file plus optional scripts and
references"* — `scripts/`, `references/`, `assets/`. Claude Code documents the same,
including a multi-domain example where `SKILL.md` is a table of contents over
`reference/*.md`, each loaded only when needed.

### Constraint: references must be one level deep

Claude's best practices: *"Keep references one level deep from SKILL.md."* With nested
references Claude may preview with `head -100` and act on partial content. This dictates a
flat `references/` tree — a step file may not point at a further file.

### Compaction favours one skill

Claude Code re-attaches invoked skills after auto-compaction keeping only the first 5,000
tokens each, within a 25,000-token combined budget, filled most-recent-first: *"older
skills can be dropped entirely after compaction if you have invoked many in one session."*
Across a long hunt with seven skills invoked, the orchestrator is precisely the one at risk
of being dropped. With one skill it always survives — this directly protects the
resumability invariant.

## Design

### Layout

```
skills/
└── offsec-hunter/
    ├── SKILL.md                              # the only skill
    └── references/                           # flat, one level deep
        ├── platform-tools.md
        ├── artifacts.md
        ├── step-1-map-attack-surface.md
        ├── step-2-scope-target.md
        ├── step-3-locate-sinks.md
        ├── step-4-raise-hypotheses.md
        ├── step-5-break-hypotheses.md
        └── step-6-prove-exploit.md
```

The six step directories are deleted. `surface-map.md` folds into
`step-1-map-attack-surface.md` and `sinks.md` into `step-3-locate-sinks.md`, because the
one-level rule forbids a step file pointing at a schema file.

### What SKILL.md owns

`SKILL.md` is the only content guaranteed to be in context, so it carries everything that
must hold even if a reference is never read:

- The step list, each line naming its reference file **and its one binding constraint**
  (e.g. step 1: "comprehension only — no vuln classes, no risk verdicts, no guard
  analysis"). This is the direct fix for the observed failure.
- An explicit load instruction: **before executing step N, read
  `references/step-N-<name>.md`**. Not "invoke the skill".
- Roots, mode, the round loop, steering, and the id-authority contract, as today.
- A first action, before step 1: resolve roots and write `state.json`.

### What changes in the step bodies

Mechanical, plus three deletions:

- The standalone-trigger guard ("run the `offsec-hunter` orchestrator first") — no longer
  reachable standalone, so nothing to guard.
- YAML frontmatter (`name` / `description` / "Use when") — reference files have none.
- Gate errors keep naming the upstream step ("run `locate-sinks` first"); that is a
  human-readable message, not a cross-skill reach.

Step content is otherwise preserved verbatim, including the comprehension-only rule, the
reachability bound, and the language-neutrality rules.

### Invariants that change

- **"No cross-skill relative paths"** is retired and replaced by **"references are flat and
  one level deep from SKILL.md"**. The old rule was authoring guidance that an agent read
  at runtime as "do not open sibling files" — the direct cause of the failure.
- **"Every step skill needs a Use-when clause and a standalone-trigger guard"** is retired;
  it only ever existed to paper over the discoverability leak.

### Invariants that hold unchanged

Runtime subagent isolation and the context-injection contract are untouched — they never
depended on file layout. A subagent still sees only its delegation prompt plus always-on
project context, and the orchestrator still injects `output_root`, `target_root`, exact
artifact paths, the assigned `sink-N` + family, and a one-line threat model. Orchestrator
remains sole id authority. Artifact-gating, the round loop, staleness rules, and additive
merge are unchanged.

## Collateral fixes (same change)

Both are pre-existing false claims in `platform-tools.md`, surfaced by the research:

1. **Model tiering is not achievable on Codex.** The guide says "select a fast/cheap model
   for the task", but Codex subagents **inherit the orchestrator's model**; task-level model
   config is an open request. The budget story (cheap for `raise-hypotheses`, strong for
   `break-hypotheses`) is Claude-Code-only and must be stated as such.
2. **Wide fan-out contradicts Codex guidance.** Codex docs warn broad delegation causes
   repeated fan-out and advise concurrency 1 absent a specific reason. The design still
   works, but the guide must say so rather than implying parity.

Also correct: Codex spawns subagents "after a direct request or applicable project or
**skill instruction**", so the prose can trigger delegation — it must do so imperatively.

## Rejected alternatives

- **Minimal fix** (add an invoke-a-step-skill row; keep seven skills). Hardens a layout that
  contradicts both platforms' model, leaves the implicit-triggering hole open, and leaves
  the orchestrator exposed to compaction eviction.
- **`disable-model-invocation: true` on step skills.** Blocks the orchestrator on Claude
  Code. Non-functional.
- **`allow_implicit_invocation: false` on step skills.** Codex-only, not portable, and moot
  once the step skills cease to exist. (Noted because it was floated during discussion; it
  does not apply to `offsec-hunter` itself, which *should* stay discoverable.)
- **Plugin packaging** as the fix. Solves distribution, not runtime loading.

## Migration

Breaking layout change → bump to `2.0.0`.

Installed copies must have the six step directories **removed**, not merely overwritten: a
`cp -R` leaves them in place, where they stay implicitly triggerable and now contradict the
consolidated orchestrator. README install instructions need an explicit removal step for
upgraders, covering both `~/.claude/skills/` and `~/.codex/skills/`.

## Out of scope

Unchanged from the comprehension-first spec and still deferred: scope-before-map
reordering, a dedicated Trace stage, cross-repo reasoning, and a deterministic success
oracle.

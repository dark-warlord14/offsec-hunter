# offsec-hunter — decomposition into composable skills

**Date:** 2026-06-30
**Status:** approved design, pending implementation plan

## Problem

`offsec-hunter` is a single monolithic `SKILL.md` running an internal 4-phase
pipeline (Map → Threat-model → Fan-out → Validate → Synthesis). We want it to
follow the **superpowers framework**: discrete, composable skills that each do
one thing, announce themselves, and hand off — chained by an orchestrator — so
both **humans and agents** experience the hunt as a clear, resumable sequence.

User-facing mental model (3 stages): **recon → goal → exploit**. Under the hood
these are **5 flat, peer skills** plus an orchestrator.

## Decision summary

- Split the monolith into **6 skills**: one orchestrator + 5 flat peer steps.
- Steps **compose by name**, never by cross-directory file path.
- Each step is **independently invocable**, gated on reading its predecessor's
  artifact.
- Support **interactive (human)** and **headless (agent)** modes.
- The hunting *logic* is unchanged — same recon → recall → precision → PoC
  engine, just decomposed.

## Skill set (flat, 5 steps)

| Skill | Step | Reads | Writes |
|-------|------|-------|--------|
| `offsec-hunter` | orchestrator (`/offsec-hunter <vuln>` entry) | — | `state.json` |
| `map-attack-surface` | 1 | target code @ `git HEAD` | `surface-map.json` |
| `scope-target` | 2 | `surface-map.json` | `hunts/<vuln>/target.md` |
| `raise-hypotheses` | 3 | `surface-map.json` + `target.md` | `hunts/<vuln>/hypotheses.jsonl` |
| `break-hypotheses` | 4 | `hypotheses.jsonl` | `hunts/<vuln>/survivors.jsonl` |
| `prove-exploit` | 5 | `survivors.jsonl` | `hunts/<vuln>/findings.{md,json}` + `pocs/` |

### Per-skill responsibilities

- **`offsec-hunter` (orchestrator).** Owns the canonical
  `references/platform-tools.md` and `references/artifacts.md`, the scope
  defaults, the enforcement/artifact-gating rules, budget orchestration (cheap
  model for breadth in step 3, strong model for precision in step 4, strongest
  for step 5). Resolves **target root** and **output root** (see below), maps the
  `<vuln>` argument, writes `state.json`, then invokes the five steps in order
  **by name**.
- **`map-attack-surface`.** Builds/refreshes the attack-surface map (entry points,
  trust boundaries, high-risk sinks, input flow). Reuses a fresh map when
  `surface-map.json.commit == HEAD`. Owns `references/surface-map.md` (schema).
- **`scope-target`.** Folds in **both** vuln-class selection (formerly in the
  orchestrator) **and** the threat-model checkpoint: proposes attacker position,
  delivery vector, win condition, in/out-of-scope notes inferred from the map.
  **Interactive mode:** stop and ask the user to confirm/edit. **Headless mode:**
  accept the proposed target, write it, and log the assumption loudly. Writes
  `target.md`.
- **`raise-hypotheses`.** Many cheap/fast subagents, one hypothesis each, tied to
  the target vuln class + a mapped sink + confirmed delivery vector. Optimize
  recall. Append candidates to `hypotheses.jsonl`.
- **`break-hypotheses`.** Stronger-model subagents adversarially try to **break**
  each candidate (source really attacker-controlled? survives every guard?
  reachable per the confirmed model? meets the win condition?). Survivors to
  `survivors.jsonl`.
- **`prove-exploit`.** Keep only confirmed-exploitable findings; write vuln, entry
  point, trust boundary, full reachability path, and a working PoC. No PoC, no
  report.

## Dual-mode + UX requirements (gaps closed)

1. **Interactive vs headless mode.** Orchestrator detects/declares mode and
   records it in `state.json`. Interactive = `scope-target` waits for human
   confirm/edit. Headless = accept proposed target, log the assumption. No other
   step blocks on input.
2. **Cross-artifact staleness.** Every per-hunt artifact records the
   `surface-map` commit + `target.md` hash it was built from. A step refuses (or
   warns, with the exact re-run command) when its input changed since the
   downstream artifact was written. Only `surface-map.json` uses commit-hash
   freshness; everything downstream chains off recorded input hashes.
3. **Resumability / "where am I".** `state.json` records per-step status
   (`pending|done`, artifact path, timestamp). The orchestrator prints a compact
   progress line (e.g. `✅ 1–2 ▶ 3`) so humans returning later and agents
   resuming after context loss both know the next action.
4. **Machine-readable output.** `prove-exploit` emits `findings.json` (vuln class,
   entry point, path, severity, PoC ref) **alongside** `findings.md`. Same
   content, two views — humans read the markdown, agents/CI consume the JSON.
5. **Empty / negative results + coverage.** If a step yields nothing (0
   hypotheses, or all broken), `prove-exploit` still writes a clean
   "**no exploitable findings**" report listing what was examined (entry points,
   sinks, coverage notes) so both audiences trust the run completed.
6. **Actionable errors.** A step invoked without its prerequisite fails loud with
   the **exact next command** (e.g. "no `surface-map.json` — run
   `map-attack-surface` first"); the orchestrator offers to run the missing
   prerequisite.
7. **Steering loop.** A completed run is not the end — the user can redirect it.
   See the dedicated section below.

## Steering — redirecting a run

The pipeline is **not one-shot**. "I ran it, I'm not satisfied, redirect it" is a
first-class flow for both humans and supervising agents, and it reuses the
artifact-gating + staleness substrate: **steering = edit an upstream artifact,
then re-run only the steps that went stale.**

Each kind of dissatisfaction maps to exactly one artifact level; re-running
propagates *down* from there — never a full restart:

| Dissatisfaction | Steer by editing | Re-runs |
|---|---|---|
| Missed an entry point ("you skipped the GraphQL route") | `surface-map.json` (patch) | 1→ 2–5 |
| Wrong goal ("focus on auth-bypass, attacker is normal-user") | `target.md` | 3–5 |
| Add / restore a lead ("chase this too", "you dropped a good one") | `hypotheses.jsonl` | 4–5 |
| Wrongly killed a candidate ("that guard *is* bypassable via X") | annotate the dropped candidate | 4–5 (that one) |
| PoC doesn't fire | the finding | 5 (that finding) |

**Mechanics:**

- **Entry point.** After step 5 the orchestrator offers *"not satisfied? tell me
  how to redirect"* (interactive) or accepts a feedback string (headless). It
  maps the fuzzy feedback → the correct artifact level above.
- **Feedback lands in artifacts, not chat.** The steer edits/annotates the
  artifact (e.g. appends `re-examine: guard bypassable via X` to a dropped
  hypothesis), so the re-run is deterministic and the staleness check (gap #2)
  fires automatically. State lives in files.
- **Targeted re-run** from the steered level, driven by the existing staleness
  detection — the map and a full fan-out are not re-paid when only the PoC needs
  redoing.
- **Steer log** in `state.json` — an append-only audit trail of how the hunt was
  redirected (for review and for agent resumption).

**Result merge semantics (additive).** A steered re-run **merges** into the
existing per-hunt results rather than overwriting: new findings/survivors are
added, prior still-valid ones are preserved, and entries are **deduped by
`entry-point + sink`**. So a steer can only *add or refine* findings, never
silently drop a previously-confirmed one. Each merged entry records the steer/run
that produced it.

## File structure (repo)

```
.claude-plugin/plugin.json        # installs the 6 skills as one unit
skills/
  offsec-hunter/                  # orchestrator
    SKILL.md
    references/
      platform-tools.md           # action → platform-tool mapping (shared)
      artifacts.md                # artifact tree + path-resolution rules (shared)
  map-attack-surface/
    SKILL.md
    references/surface-map.md      # surface-map schema (skill-local)
  scope-target/SKILL.md
  raise-hypotheses/SKILL.md
  break-hypotheses/SKILL.md
  prove-exploit/SKILL.md
docs/superpowers/specs/...
README.md
```

Shared cross-cutting docs (`platform-tools.md`, `artifacts.md`) live **only** in
the orchestrator and are referenced **by name**; skill-specific docs stay local.

## Artifact structure

Two tiers — **target-level** (reusable across vuln classes) and **per-hunt**
(namespaced by vuln class, so SSRF and RCE runs never clobber each other):

```
.offsec-hunter/
  state.json                  # registry: target root, output root, mode,
                              # per-step status, recorded input hashes, steer log
  surface-map.json            # TARGET-level, commit-stamped — shared by all hunts
  hunts/
    SSRF/                      # PER-HUNT namespace
      target.md
      hypotheses.jsonl
      survivors.jsonl
      findings.md
      findings.json
      pocs/
        finding-001.sh         # runnable PoC, referenced from findings.*
```

## Path resolution — inside vs outside the target

Two roots, resolved **once** by the orchestrator and recorded in `state.json`;
every step reads them from there so they never disagree:

- **Target root** — the code being hunted. All artifact paths are relative to
  this. Resolved explicitly — **never assumed to equal `cwd`**.
- **Output root** — where `.offsec-hunter/` is written.

**Default:** in-tree — `<target-root>/.offsec-hunter/`, gitignored. Zero-config
for the common "I'm working inside the repo" case.

**Override:** an explicit out-dir, **or** automatic fallback to a central dir
(`~/.offsec-hunter/<target-id>/`, keyed by target path + commit) when the target
tree is read-only. This keeps foreign/read-only audits from mutating the target.

## Packaging

- Add `.claude-plugin/plugin.json` so the 6 skills install as one unit.
- Each `SKILL.md` gets `name` + `description` frontmatter. Only the orchestrator's
  description carries the `/offsec-hunter` trigger.
- Keep the existing light multi-platform story (copy the skills set into Claude
  Code and Codex). **No** full `.codex-plugin` packaging in this change.

## Renames

- Artifact `threat-model.md` → `hunts/<vuln>/target.md`.
- Phases → flat skills: Map→`map-attack-surface`, Threat-model→`scope-target`,
  Fan-out→`raise-hypotheses`, Validate→`break-hypotheses`,
  Synthesis→`prove-exploit`.

## Testing

Follows the superpowers model — test the **instructions**, keep skills as pure
markdown. Two tiers in scope for this change; full evals are future work.

**Tier 1 — static contract tests (deterministic, no LLM).** `grep` over the 6
`SKILL.md` files, run in CI. Assert the decomposition's contracts hold:

- each step names its input artifact and the exact re-run command on missing
  input (gap #6);
- `scope-target` documents both **interactive** and **headless** branches
  (gap #1);
- `prove-exploit` emits `findings.json` and an empty-results/coverage report
  (gaps #4, #5);
- the steering table and the additive-merge dedup key (`entry-point + sink`) are
  present (gap #7);
- **compose-by-name**: no `../` cross-skill paths anywhere; `platform-tools.md`
  and `artifacts.md` appear only under the orchestrator.

**Tier 2 — behavioral recall (LLM, cheap).** Headless `claude -p` prompts assert
the agent describes the workflow correctly: the 5 steps in order, artifact-gating,
and headless mode. Mirrors superpowers' `run_claude` recall tests.

Tests live in `tests/` at the repo root (per superpowers layout), with a
`run-skill-tests.sh` entry point.

**Out of scope here (future work):** Tier 3 evals/drills — planted-vuln fixtures
with ground truth, per-skill evals, recall/precision/cost metrics, and
PoC-execution scoring against a running fixture. Tracked as future work; a tiny
mechanical helper script is factored out **only if** a contract proves flaky
under those evals, not pre-emptively.

## Non-goals (YAGNI — explicit future work)

- No change to hunting logic, vuln classes, or detection coverage.
- No full Codex/multi-platform plugin packaging yet.
- Per-skill slash triggers (e.g. `/map-attack-surface` standalone) — deferred.
- Sub-target scoping ("only hunt `src/api/`") — deferred.
- Cost/size preview + cap before a large fan-out — deferred.
- Parallel-run isolation of `.offsec-hunter/` — deferred.

## Documentation impact

- README: new layout, skill list, plugin-style install, updated pipeline diagram,
  inside-vs-outside usage.
- This spec supersedes the structure (not the rationale) of
  `2026-06-26-offsec-hunter-design.md`.

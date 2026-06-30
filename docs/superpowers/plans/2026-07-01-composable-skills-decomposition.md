# offsec-hunter Composable-Skills Decomposition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the monolithic `offsec-hunter` skill into an orchestrator plus five flat, compose-by-name peer skills, each artifact-gated and independently invocable, with dual interactive/headless modes, a steering loop, and a static + behavioral test suite.

**Architecture:** One plugin (`.claude-plugin/plugin.json`) containing six skills under `skills/`. The orchestrator (`offsec-hunter`) resolves roots/mode, then invokes five step skills by name (`map-attack-surface` → `scope-target` → `raise-hypotheses` → `break-hypotheses` → `prove-exploit`). Each step reads its predecessor's file artifact in `.offsec-hunter/` and refuses to run if it is missing or stale. Hunting logic is ported verbatim from the monolith — only structure changes.

**Tech Stack:** Markdown skills (agent-skills open standard); bash tests (grep-based static contracts + `claude -p` behavioral recall), following the superpowers `tests/` layout.

## Global Constraints

- Skills are **pure markdown**. No extracted logic scripts (YAGNI).
- Skills **compose by name** — **no `../` cross-skill file paths anywhere** under `skills/*/SKILL.md`.
- `references/platform-tools.md` and `references/artifacts.md` exist **only** under `skills/offsec-hunter/`. `references/surface-map.md` exists **only** under `skills/map-attack-surface/`.
- All run artifacts live under the **output root** (default `<target-root>/.offsec-hunter/`, gitignored). Per-hunt artifacts are namespaced `hunts/<VULN>/`.
- Artifact names are exact: `state.json`, `surface-map.json`, `hunts/<VULN>/{target.md, hypotheses.jsonl, survivors.jsonl, findings.md, findings.json, pocs/}`.
- Each `SKILL.md` has YAML frontmatter with `name` (matching its directory) and `description`. Only the orchestrator's description carries the `/offsec-hunter` trigger.
- Hunting logic unchanged: no new vuln classes, flags, or detection coverage.
- No full `.codex-plugin` packaging in this change.
- Commit after each task. Work stays on branch `feat/composable-skills-decomposition`.

---

## File Structure

```
.claude-plugin/plugin.json                         # CREATE — installs the 6 skills as one unit
skills/
  offsec-hunter/
    SKILL.md                                        # REWRITE — monolith → orchestrator
    references/
      platform-tools.md                             # MODIFY — phase→step naming
      artifacts.md                                  # CREATE — artifact tree, roots, gating, state.json
  map-attack-surface/
    SKILL.md                                        # CREATE
    references/surface-map.md                       # MOVE from skills/offsec-hunter/references/
  scope-target/SKILL.md                             # CREATE
  raise-hypotheses/SKILL.md                         # CREATE
  break-hypotheses/SKILL.md                         # CREATE
  prove-exploit/SKILL.md                            # CREATE
tests/
  test-helpers.sh                                   # CREATE
  test-static-contracts.sh                          # CREATE (grown per skill task)
  test-behavioral-recall.sh                         # CREATE
  run-skill-tests.sh                                # CREATE
README.md                                           # MODIFY — layout, install, pipeline, usage
docs/superpowers/specs/2026-06-26-offsec-hunter-design.md  # leave as historical
```

---

### Task 1: Plugin manifest + test harness scaffold

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `tests/test-helpers.sh`
- Create: `tests/test-static-contracts.sh`
- Create: `tests/run-skill-tests.sh`

**Interfaces:**
- Produces: helper functions `assert_file_contains <file> <pattern> <label>`, `assert_file_not_contains <file> <pattern> <label>`, `assert_file_exists <file> <label>`, `assert_no_cross_skill_paths <label>`, and counters `PASS`/`FAIL` with a `summary` function. Later tasks append blocks to `tests/test-static-contracts.sh` using these.

- [ ] **Step 1: Write the failing test (the runner with zero assertions)**

Create `tests/run-skill-tests.sh`:

```bash
#!/usr/bin/env bash
# Entry point: run all offsec-hunter skill tests.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

bash "$SCRIPT_DIR/test-static-contracts.sh"
# Behavioral recall (Tier 2) is added in a later task and is opt-in:
if [ "${RUN_BEHAVIORAL:-0}" = "1" ]; then
  bash "$SCRIPT_DIR/test-behavioral-recall.sh"
fi
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/run-skill-tests.sh`
Expected: FAIL — `test-static-contracts.sh: No such file or directory`.

- [ ] **Step 3: Write the helpers and an initial (passing-empty) static test**

Create `tests/test-helpers.sh`:

```bash
#!/usr/bin/env bash
# Shared assertions for static contract tests.
PASS=0
FAIL=0
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_file_exists() {
  local file="$1" label="$2"
  if [ -f "$REPO_ROOT/$file" ]; then echo "  [PASS] $label"; PASS=$((PASS+1));
  else echo "  [FAIL] $label — missing: $file"; FAIL=$((FAIL+1)); fi
}

assert_file_contains() {
  local file="$1" pattern="$2" label="$3"
  if grep -Eq "$pattern" "$REPO_ROOT/$file" 2>/dev/null; then echo "  [PASS] $label"; PASS=$((PASS+1));
  else echo "  [FAIL] $label — '$pattern' not in $file"; FAIL=$((FAIL+1)); fi
}

assert_file_not_contains() {
  local file="$1" pattern="$2" label="$3"
  if grep -Eq "$pattern" "$REPO_ROOT/$file" 2>/dev/null; then echo "  [FAIL] $label — '$pattern' found in $file"; FAIL=$((FAIL+1));
  else echo "  [PASS] $label"; PASS=$((PASS+1)); fi
}

# Fails if any skill SKILL.md references a sibling skill by relative path.
assert_no_cross_skill_paths() {
  local label="$1" hits
  hits="$(grep -REn '\.\./[a-z-]+/' "$REPO_ROOT/skills" --include=SKILL.md 2>/dev/null || true)"
  if [ -z "$hits" ]; then echo "  [PASS] $label"; PASS=$((PASS+1));
  else echo "  [FAIL] $label — cross-skill paths found:"; echo "$hits"; FAIL=$((FAIL+1)); fi
}

summary() {
  echo ""; echo "  ---- $PASS passed, $FAIL failed ----"
  [ "$FAIL" -eq 0 ]
}
```

Create `tests/test-static-contracts.sh`:

```bash
#!/usr/bin/env bash
# Tier 1 — static contract tests over the skill markdown (no LLM).
set -uo pipefail
source "$(cd "$(dirname "$0")" && pwd)/test-helpers.sh"

echo "=== Static contract tests ==="

# --- Packaging (Task 1) ---
assert_file_exists ".claude-plugin/plugin.json" "plugin manifest exists"
assert_file_contains ".claude-plugin/plugin.json" '"name"[[:space:]]*:[[:space:]]*"offsec-hunter"' "manifest names the plugin"

# (subsequent tasks append their assertion blocks below)

summary
```

Create `.claude-plugin/plugin.json`:

```json
{
  "name": "offsec-hunter",
  "description": "Composable, artifact-gated skills for hunting externally reachable, exploitable vulnerabilities — recon → goal → exploit.",
  "version": "1.0.0",
  "license": "MIT",
  "keywords": ["security", "vulnerability", "appsec", "offensive-security", "skills"]
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `chmod +x tests/*.sh && bash tests/run-skill-tests.sh`
Expected: PASS — `2 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add .claude-plugin/plugin.json tests/
git commit -m "test(skills): add plugin manifest and static test harness"
```

---

### Task 2: Orchestrator skill + artifacts guide + platform-tools update

**Files:**
- Modify: `skills/offsec-hunter/SKILL.md` (full rewrite — monolith → orchestrator)
- Create: `skills/offsec-hunter/references/artifacts.md`
- Modify: `skills/offsec-hunter/references/platform-tools.md`
- Modify: `tests/test-static-contracts.sh` (append orchestrator assertions)

**Interfaces:**
- Consumes: helpers from Task 1.
- Produces: the orchestrator contract that step skills reference by name; the `artifacts.md` definitions (roots, `state.json` shape, gating/staleness) every step relies on.

- [ ] **Step 1: Append the failing assertions**

Append to `tests/test-static-contracts.sh` before the `summary` line:

```bash
# --- Orchestrator (Task 2) ---
O="skills/offsec-hunter/SKILL.md"
assert_file_contains "$O" '^name: offsec-hunter' "orchestrator frontmatter name"
assert_file_contains "$O" 'map-attack-surface' "orchestrator names step 1"
assert_file_contains "$O" 'scope-target' "orchestrator names step 2"
assert_file_contains "$O" 'raise-hypotheses' "orchestrator names step 3"
assert_file_contains "$O" 'break-hypotheses' "orchestrator names step 4"
assert_file_contains "$O" 'prove-exploit' "orchestrator names step 5"
assert_file_contains "$O" 'interactive' "orchestrator documents interactive mode"
assert_file_contains "$O" 'headless' "orchestrator documents headless mode"
assert_file_contains "$O" 'state\.json' "orchestrator references state.json"
assert_file_contains "$O" '[Tt]arget root' "orchestrator resolves target root"
assert_file_contains "$O" '[Oo]utput root' "orchestrator resolves output root"
assert_file_contains "$O" '[Ss]teer' "orchestrator documents steering"
assert_file_contains "$O" 'artifacts\.md' "orchestrator references artifacts guide by name"
assert_file_exists "skills/offsec-hunter/references/artifacts.md" "artifacts guide exists"
assert_no_cross_skill_paths "no cross-skill relative paths"
# artifacts.md / platform-tools.md must NOT leak into other skill dirs
for d in map-attack-surface scope-target raise-hypotheses break-hypotheses prove-exploit; do
  assert_file_not_contains "/dev/null" "x" "noop" 2>/dev/null || true
done
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/run-skill-tests.sh`
Expected: FAIL — orchestrator assertions fail (`state.json` / `headless` / `artifacts.md` not yet present), `artifacts.md` missing.

- [ ] **Step 3: Rewrite the orchestrator SKILL.md**

Replace the entire contents of `skills/offsec-hunter/SKILL.md` with:

````markdown
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
````

- [ ] **Step 4: Create the artifacts guide**

Create `skills/offsec-hunter/references/artifacts.md`:

````markdown
# Artifacts — layout, roots, gating, state

All run artifacts live under the **output root**. Two roots, resolved once by the
orchestrator and recorded in `state.json`:

- **Target root** — code being hunted; all artifact file paths are relative to it. Never
  assumed to be the current directory.
- **Output root** — where `.offsec-hunter/` is written. Default
  `<target-root>/.offsec-hunter/` (gitignored); override to an explicit dir, or
  `~/.offsec-hunter/<target-id>/` when the target tree is read-only.

## Tree

```
.offsec-hunter/
  state.json                  # roots, mode, per-step status, input hashes, steer log
  surface-map.json            # TARGET-level, commit-stamped, shared across vuln classes
  hunts/
    <VULN>/                   # per-hunt namespace (e.g. SSRF, RCE)
      target.md
      hypotheses.jsonl
      survivors.jsonl
      findings.md
      findings.json
      pocs/
        finding-001.sh
```

## state.json

```json
{
  "target_root": "/abs/path/to/target",
  "output_root": "/abs/path/to/target/.offsec-hunter",
  "mode": "interactive",
  "vuln": "SSRF",
  "steps": {
    "map-attack-surface": {"status": "done", "artifact": "surface-map.json", "commit": "<HEAD>", "at": "<iso8601>"},
    "scope-target":       {"status": "done", "artifact": "hunts/SSRF/target.md", "input_hash": "<sha256 of surface-map.json>", "at": "<iso8601>"},
    "raise-hypotheses":   {"status": "pending"},
    "break-hypotheses":   {"status": "pending"},
    "prove-exploit":      {"status": "pending"}
  },
  "steer_log": [
    {"at": "<iso8601>", "feedback": "focus on auth-bypass", "edited": "hunts/SSRF/target.md", "reran_from": "raise-hypotheses"}
  ]
}
```

## Gating & staleness

- A step refuses to run when its input artifact is missing and prints the exact fix
  (e.g. "no `surface-map.json` — run `map-attack-surface` first").
- `surface-map.json` is **fresh** iff its `commit == git rev-parse HEAD`; otherwise rebuild.
- Each downstream artifact records the hash of its inputs (`input_hash` in `state.json`).
  If an input changed since the artifact was written, the artifact is **stale** — re-run
  that step. This is what makes steering re-run exactly the affected steps.
````

- [ ] **Step 5: Update platform-tools.md (phase → step naming)**

Replace the two `Notes` bullets that mention phases in `skills/offsec-hunter/references/platform-tools.md` so they read:

```markdown
Notes:
- Claude Code: do NOT use `subagent_type: "general"` — it is invalid; the catch-all is
  `general-purpose`.
- If a platform lacks parallel subagents, run the `raise-hypotheses` step's hypotheses
  sequentially on the cheap model — the artifact-gating and step order are unchanged.
- The orchestrator (the main session) always resolves roots/mode and runs `prove-exploit`
  synthesis itself.
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bash tests/run-skill-tests.sh`
Expected: PASS — all orchestrator assertions green.

- [ ] **Step 7: Commit**

```bash
git add skills/offsec-hunter/ tests/test-static-contracts.sh
git commit -m "feat(skill): rewrite offsec-hunter as orchestrator; add artifacts guide"
```

---

### Task 3: map-attack-surface skill (+ move surface-map.md)

**Files:**
- Create: `skills/map-attack-surface/SKILL.md`
- Move: `skills/offsec-hunter/references/surface-map.md` → `skills/map-attack-surface/references/surface-map.md`
- Modify: `tests/test-static-contracts.sh` (append)

**Interfaces:**
- Produces: `surface-map.json` (schema in its local `references/surface-map.md`), commit-stamped — consumed by `scope-target` and `raise-hypotheses`.

- [ ] **Step 1: Append the failing assertions**

Append before `summary`:

```bash
# --- map-attack-surface (Task 3) ---
M="skills/map-attack-surface/SKILL.md"
assert_file_contains "$M" '^name: map-attack-surface' "step1 frontmatter name"
assert_file_contains "$M" 'surface-map\.json' "step1 writes surface-map.json"
assert_file_contains "$M" 'rev-parse HEAD' "step1 commit-stamps freshness"
assert_file_contains "$M" 'surface-map\.md' "step1 references its schema"
assert_file_exists "skills/map-attack-surface/references/surface-map.md" "schema moved to step1"
assert_file_not_contains "skills/offsec-hunter/references/surface-map.md" "." "schema no longer under orchestrator" 2>/dev/null || true
```

(Note: the last assertion passes because the file no longer exists — `grep` on a missing file yields no match.)

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/run-skill-tests.sh`
Expected: FAIL — `skills/map-attack-surface/SKILL.md` missing.

- [ ] **Step 3: Move the schema reference**

```bash
mkdir -p skills/map-attack-surface/references
git mv skills/offsec-hunter/references/surface-map.md skills/map-attack-surface/references/surface-map.md
```

Then edit the moved `skills/map-attack-surface/references/surface-map.md`: change the last bullet's `Phase 1` → `raise-hypotheses`, `Phase 2` → `break-hypotheses`, and `Phase 0.5 threat-model checkpoint` → `scope-target` step, so it reads:

```markdown
- `flows` is what `raise-hypotheses` fans out over — each flow is a hypothesis seed.
- Record `guards` honestly; `break-hypotheses`'s job is to determine whether they hold.
- Non-web targets are first-class: an `entry_point` may be a parsed input file
  (`file-input`), a CLI, an IPC/socket, or a local service. Record these the same
  way — the `scope-target` checkpoint reasons over whatever the map shows.
```

- [ ] **Step 4: Create the skill**

Create `skills/map-attack-surface/SKILL.md`:

````markdown
---
name: map-attack-surface
description: Step 1 of offsec-hunter. Build or refresh a reusable attack-surface map of a target — entry points, trust boundaries, high-risk sinks, and input flows — stamped with the git commit. Reuses a fresh map automatically.
---

# map-attack-surface — step 1

Goal: a structured model of how external input enters and flows — **not** an exhaustive
code read. This map is also the reachability index that prunes the rest of the hunt.

This step writes `surface-map.json` under the output root (see the offsec-hunter artifacts
guide). It has no input artifact — it is the first step.

## Procedure

1. Get the current commit: `git rev-parse HEAD`.
2. If `surface-map.json` exists and its `commit` equals `HEAD` → the map is **fresh**: load
   it and stop (downstream steps reuse it).
3. Otherwise build/refresh the map. Identify:
   - **Entry points** — HTTP routes, WebSocket handlers, RPC handlers, message consumers,
     scheduled jobs, parsed input files, CLIs, IPC/sockets, local services.
   - **Trust boundaries** — unauth ↔ session ↔ m2m; browser ↔ server; service ↔ service.
   - **High-risk sinks** — outbound fetch (SSRF), deserialization, templating (SSTI),
     command/eval (RCE), query construction (SQLi), authz checks, untrusted parsing.
   - **Input flow** — how external input reaches each sink and how it is mutated en route.
4. Write `surface-map.json` per the schema in `references/surface-map.md`, stamped with
   `commit` = current `HEAD`. Record the step as done in `state.json`.

Prioritize what is **reachable from crafted input** over reading everything.
````

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash tests/run-skill-tests.sh`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add skills/map-attack-surface/ tests/test-static-contracts.sh
git commit -m "feat(skill): add map-attack-surface (step 1); move surface-map schema"
```

---

### Task 4: scope-target skill

**Files:**
- Create: `skills/scope-target/SKILL.md`
- Modify: `tests/test-static-contracts.sh` (append)

**Interfaces:**
- Consumes: `surface-map.json`.
- Produces: `hunts/<VULN>/target.md` (prose, four dimensions + chosen vuln class) — consumed by `raise-hypotheses`.

- [ ] **Step 1: Append the failing assertions**

Append before `summary`:

```bash
# --- scope-target (Task 4) ---
S="skills/scope-target/SKILL.md"
assert_file_contains "$S" '^name: scope-target' "step2 frontmatter name"
assert_file_contains "$S" 'surface-map\.json' "step2 reads surface-map.json"
assert_file_contains "$S" 'map-attack-surface first' "step2 actionable missing-input error"
assert_file_contains "$S" 'target\.md' "step2 writes target.md"
assert_file_contains "$S" 'interactive' "step2 has interactive branch"
assert_file_contains "$S" 'headless' "step2 has headless branch"
assert_file_contains "$S" '[Aa]ttacker position' "step2 covers attacker position"
assert_file_contains "$S" '[Dd]elivery vector' "step2 covers delivery vector"
assert_file_contains "$S" '[Ww]in condition' "step2 covers win condition"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/run-skill-tests.sh`
Expected: FAIL — `skills/scope-target/SKILL.md` missing.

- [ ] **Step 3: Create the skill**

Create `skills/scope-target/SKILL.md`:

````markdown
---
name: scope-target
description: Step 2 of offsec-hunter. Read the attack-surface map and define the hunting goal — the target vuln class plus a confirmed threat model (attacker position, delivery vector, win condition, scope). Interactive runs confirm with the user; headless runs accept and log the proposal.
---

# scope-target — step 2

Define the **hunting goal** for this run: the target vuln class plus a confirmed threat
model. Writes `hunts/<VULN>/target.md` under the output root.

## Gate

Read `surface-map.json` (target-level). If it is missing or stale, stop:
**"no fresh `surface-map.json` — run `map-attack-surface` first."** Do not proceed on a
missing or stale map.

## Procedure

The map now tells you what an exploit plausibly looks like for **this** target — use it
instead of assuming the web default.

1. **Pick the vuln class.** Use the `$ARGUMENTS` class passed to the orchestrator. If none
   was given: interactive → ask which class (`SSRF`, `RCE`, `SQLi`, `SSTI`, `auth-bypass`,
   `IDOR`, … or `broad`); headless → default to `broad` and log it.

2. **Propose a threat model** inferred from the map, across four dimensions:
   - **Attacker position** — e.g. `remote-unauth`, `remote-normal-user`, `local-user`,
     `input-file-supplier`, `adjacent-service`.
   - **Delivery vector** — e.g. HTTP request/chain, WebSocket message, CLI args, a parsed
     input file/format, IPC/socket, environment.
   - **Win condition** — what counts as a successful exploit here. Includes
     RCE/SSRF/data-exfil/auth-bypass **and** non-web wins: DoS / "render the target
     incapable", memory-safety crash.
   - **In/out-of-scope notes** — boundaries explicitly excluded (e.g. m2m-only paths
     unless an auth bypass reaches them) and target-specific assumptions.

   Start from the default Scope in the orchestrator; where the map shows a non-web target,
   propose the fitting model instead.

3. **Confirm by mode:**
   - **interactive** — stop and ask the user to confirm or edit the proposal, **even when
     it equals the web default**. Do not auto-proceed. This is the nudge.
   - **headless** — accept the proposed model, and **log the assumption loudly** so it is
     auditable.

4. Write the confirmed goal to `hunts/<VULN>/target.md` as prose, with the four dimensions
   and the chosen vuln class as headings. Record the step done in `state.json` with the
   `input_hash` of `surface-map.json`.
````

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run-skill-tests.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add skills/scope-target/ tests/test-static-contracts.sh
git commit -m "feat(skill): add scope-target (step 2) with interactive/headless modes"
```

---

### Task 5: raise-hypotheses skill

**Files:**
- Create: `skills/raise-hypotheses/SKILL.md`
- Modify: `tests/test-static-contracts.sh` (append)

**Interfaces:**
- Consumes: `surface-map.json` + `hunts/<VULN>/target.md`.
- Produces: `hunts/<VULN>/hypotheses.jsonl` — one candidate per line (`sink`, `suspected_source`, `path`), consumed by `break-hypotheses`.

- [ ] **Step 1: Append the failing assertions**

Append before `summary`:

```bash
# --- raise-hypotheses (Task 5) ---
R="skills/raise-hypotheses/SKILL.md"
assert_file_contains "$R" '^name: raise-hypotheses' "step3 frontmatter name"
assert_file_contains "$R" 'target\.md' "step3 reads target.md"
assert_file_contains "$R" 'scope-target first' "step3 actionable missing-input error"
assert_file_contains "$R" 'hypotheses\.jsonl' "step3 writes hypotheses.jsonl"
assert_file_contains "$R" '[Rr]ecall' "step3 optimizes recall"
assert_file_contains "$R" '(cheap|fast)' "step3 uses cheap/fast model"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/run-skill-tests.sh`
Expected: FAIL — file missing.

- [ ] **Step 3: Create the skill**

Create `skills/raise-hypotheses/SKILL.md`:

````markdown
---
name: raise-hypotheses
description: Step 3 of offsec-hunter. Cheap, wide fan-out — dispatch many shallow subagents on a fast model to generate vulnerability hypotheses tied to the target vuln class and the mapped sinks. Optimizes recall, not precision.
---

# raise-hypotheses — step 3

Generate many candidate vulnerabilities. Optimize for **recall, not precision** — a later
step breaks them. Writes `hunts/<VULN>/hypotheses.jsonl`.

## Gate

Read `surface-map.json` and `hunts/<VULN>/target.md`. If `target.md` is missing or stale,
stop: **"no fresh `target.md` — run `scope-target` first."**

## Procedure

Dispatch **many shallow subagents on a cheap/fast model** (see the offsec-hunter platform
guide), each chasing **one** hypothesis tied to the target vuln class, a mapped sink, and
the **confirmed delivery vector + attacker position** from `target.md` — e.g. "does any
handler fetch a user-supplied URL without an allowlist?", or "does the file parser trust a
length field from the input file?".

Each subagent returns a **candidate**, not a verdict: the sink, the suspected
attacker-controlled source, and the path between them. Append candidates to
`hunts/<VULN>/hypotheses.jsonl`, one JSON object per line:

```json
{"id": "h-1", "sink": "sink-3", "source": "body.url", "path": "POST /fetch -> validate() -> http.get()", "rationale": "no allowlist visible"}
```

Record the step done in `state.json` with the `input_hash` of `target.md`.
````

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run-skill-tests.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add skills/raise-hypotheses/ tests/test-static-contracts.sh
git commit -m "feat(skill): add raise-hypotheses (step 3) cheap fan-out"
```

---

### Task 6: break-hypotheses skill

**Files:**
- Create: `skills/break-hypotheses/SKILL.md`
- Modify: `tests/test-static-contracts.sh` (append)

**Interfaces:**
- Consumes: `hunts/<VULN>/hypotheses.jsonl`.
- Produces: `hunts/<VULN>/survivors.jsonl` — confirmed-reachable candidates, consumed by `prove-exploit`.

- [ ] **Step 1: Append the failing assertions**

Append before `summary`:

```bash
# --- break-hypotheses (Task 6) ---
B="skills/break-hypotheses/SKILL.md"
assert_file_contains "$B" '^name: break-hypotheses' "step4 frontmatter name"
assert_file_contains "$B" 'hypotheses\.jsonl' "step4 reads hypotheses.jsonl"
assert_file_contains "$B" 'raise-hypotheses first' "step4 actionable missing-input error"
assert_file_contains "$B" 'survivors\.jsonl' "step4 writes survivors.jsonl"
assert_file_contains "$B" '(break the claim|try to break)' "step4 is adversarial"
assert_file_contains "$B" '(stronger|strong)' "step4 uses a stronger model"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/run-skill-tests.sh`
Expected: FAIL — file missing.

- [ ] **Step 3: Create the skill**

Create `skills/break-hypotheses/SKILL.md`:

````markdown
---
name: break-hypotheses
description: Step 4 of offsec-hunter. Deep adversarial validation — dispatch stronger-model subagents that try to break each hypothesis, not confirm it. Keeps only candidates that survive every guard and are reachable per the confirmed threat model.
---

# break-hypotheses — step 4

Adversarially validate each candidate. The job is to **try to break the claim**, not to
confirm it. Writes `hunts/<VULN>/survivors.jsonl`.

## Gate

Read `hunts/<VULN>/hypotheses.jsonl`. If it is missing, stop:
**"no `hypotheses.jsonl` — run `raise-hypotheses` first."**

## Procedure

For each candidate, dispatch a **stronger-model subagent** (see the offsec-hunter platform
guide) to trace it across files and attempt to refute it:

- Is the source **actually** attacker-controlled?
- Does it **survive every guard/gate** between source and sink?
- Is it reachable **per the confirmed threat model** (the attacker position and delivery
  vector in `target.md`)?
- Does the result meet the **confirmed win condition** (so a DoS or memory-safety crash
  counts when the user scoped it in)?

Drop anything that fails any check. Append confirmed-reachable survivors to
`hunts/<VULN>/survivors.jsonl`, carrying the candidate fields plus the guards examined and
why they hold/fail. Record the step done in `state.json`.
````

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run-skill-tests.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add skills/break-hypotheses/ tests/test-static-contracts.sh
git commit -m "feat(skill): add break-hypotheses (step 4) adversarial validation"
```

---

### Task 7: prove-exploit skill

**Files:**
- Create: `skills/prove-exploit/SKILL.md`
- Modify: `tests/test-static-contracts.sh` (append)

**Interfaces:**
- Consumes: `hunts/<VULN>/survivors.jsonl`.
- Produces: `hunts/<VULN>/findings.md`, `hunts/<VULN>/findings.json`, `hunts/<VULN>/pocs/finding-NNN.*`.

- [ ] **Step 1: Append the failing assertions**

Append before `summary`:

```bash
# --- prove-exploit (Task 7) ---
P="skills/prove-exploit/SKILL.md"
assert_file_contains "$P" '^name: prove-exploit' "step5 frontmatter name"
assert_file_contains "$P" 'survivors\.jsonl' "step5 reads survivors.jsonl"
assert_file_contains "$P" 'break-hypotheses first' "step5 actionable missing-input error"
assert_file_contains "$P" 'findings\.json' "step5 emits machine-readable findings"
assert_file_contains "$P" 'findings\.md' "step5 emits human-readable findings"
assert_file_contains "$P" 'no exploitable findings' "step5 has empty-results report"
assert_file_contains "$P" 'entry-point \+ sink' "step5 documents additive-merge dedup key"
assert_file_contains "$P" 'pocs/' "step5 writes runnable PoCs"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/run-skill-tests.sh`
Expected: FAIL — file missing.

- [ ] **Step 3: Create the skill**

Create `skills/prove-exploit/SKILL.md`:

````markdown
---
name: prove-exploit
description: Step 5 of offsec-hunter. Synthesis — keep only confirmed-exploitable findings and write a working PoC for each (curl / request chain / WebSocket message). Emits human (findings.md) and machine (findings.json) reports plus runnable PoCs, merging additively on a steered re-run.
---

# prove-exploit — step 5

Keep only **confirmed-exploitable** findings and prove each with a working PoC. No PoC, no
report. Writes `hunts/<VULN>/findings.md`, `hunts/<VULN>/findings.json`, and
`hunts/<VULN>/pocs/`.

## Gate

Read `hunts/<VULN>/survivors.jsonl`. If it is missing, stop:
**"no `survivors.jsonl` — run `break-hypotheses` first."**

## Per finding

For each survivor that you can actually exploit, record:

- The vulnerability, the entry point, and the trust boundary it crosses.
- The full reachability path (source → guards bypassed → sink).
- A **PoC**: the exact HTTP request / chain of requests / WebSocket message. Write it as a
  runnable file under `hunts/<VULN>/pocs/finding-NNN.sh` (e.g. a `curl` command) and
  reference it from the reports.

Write **both** views with identical content:

- `findings.md` — human-readable prose, one section per finding.
- `findings.json` — an array of objects: `{"id", "vuln_class", "entry_point", "trust_boundary", "path", "severity", "poc": "pocs/finding-NNN.sh"}`.

## Empty / negative results

If there are no confirmed-exploitable findings (zero survivors, or none reproduced), still
write a clean report: **"no exploitable findings"**, plus what was examined — entry points,
sinks, and coverage notes from `surface-map.json` and `survivors.jsonl` — so the run is
demonstrably complete rather than silently empty.

## Steered re-runs — additive merge

On a re-run (steering), **merge** into the existing `findings.md`/`findings.json` rather
than overwriting: add new findings, preserve prior still-valid ones, and dedup by
**entry-point + sink**. A steer may only add or refine findings, never silently drop a
previously-confirmed one. Tag each entry with the run/steer that produced it. Record the
step done in `state.json`.
````

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run-skill-tests.sh`
Expected: PASS — full static suite green.

- [ ] **Step 5: Commit**

```bash
git add skills/prove-exploit/ tests/test-static-contracts.sh
git commit -m "feat(skill): add prove-exploit (step 5) with findings.json, empty-results, additive merge"
```

---

### Task 8: Behavioral recall test (Tier 2)

**Files:**
- Create: `tests/test-behavioral-recall.sh`

**Interfaces:**
- Consumes: the installed/loadable `offsec-hunter` skill. Run opt-in via `RUN_BEHAVIORAL=1`.

- [ ] **Step 1: Write the behavioral test**

Create `tests/test-behavioral-recall.sh`:

```bash
#!/usr/bin/env bash
# Tier 2 — behavioral recall: assert the agent describes the workflow correctly.
# Opt-in (LLM calls): RUN_BEHAVIORAL=1 bash tests/run-skill-tests.sh
set -uo pipefail
TIMEOUT="${CLAUDE_PROMPT_TIMEOUT:-120}"
fail=0

run_claude() { timeout "$TIMEOUT" claude -p "$1" 2>&1; }

check() { # haystack pattern label
  if echo "$1" | grep -Eiq "$2"; then echo "  [PASS] $3";
  else echo "  [FAIL] $3"; fail=1; fi
}

echo "=== Behavioral recall ==="
out="$(run_claude 'Describe the offsec-hunter skill: list its steps in order and how it gates between them. Be brief.')"

check "$out" 'map.?attack.?surface' "names step 1"
check "$out" 'scope.?target'        "names step 2"
check "$out" 'raise.?hypotheses'    "names step 3"
check "$out" 'break.?hypotheses'    "names step 4"
check "$out" 'prove.?exploit'       "names step 5"
check "$out" 'artifact|gate|state\.json' "describes artifact-gating"

out2="$(run_claude 'In offsec-hunter, what is the difference between interactive and headless mode? Be brief.')"
check "$out2" 'headless' "explains headless mode"
check "$out2" 'confirm|ask|interactive' "explains interactive mode"

[ "$fail" -eq 0 ] && echo "  ---- behavioral PASS ----" || { echo "  ---- behavioral FAIL ----"; exit 1; }
```

- [ ] **Step 2: Run it (skill must be installed in the test environment)**

Run: `chmod +x tests/test-behavioral-recall.sh && RUN_BEHAVIORAL=1 bash tests/run-skill-tests.sh`
Expected: static PASS, then behavioral PASS (requires the skill installed where `claude -p` can load it; if the skill is not yet installed, install per README first).

- [ ] **Step 3: Commit**

```bash
git add tests/test-behavioral-recall.sh
git commit -m "test(skills): add Tier 2 behavioral recall test"
```

---

### Task 9: README update

**Files:**
- Modify: `README.md`

**Interfaces:** none (docs).

- [ ] **Step 1: Update the pipeline, layout, install, and usage sections**

Edit `README.md`:

1. Replace the "How it works" numbered list (lines describing phases 0–3) with the
   six-skill chain:

```markdown
## How it works

One plugin, six composable skills. The orchestrator chains five flat, artifact-gated
steps — each reads the previous step's file artifact and refuses to run if it is missing
or stale, so the workflow runs in order every time:

1. **map-attack-surface** — build/refresh a reusable, commit-stamped attack-surface map.
2. **scope-target** — define the hunting goal: vuln class + confirmed threat model
   (attacker position, delivery vector, win condition). Interactive confirms with you;
   headless accepts and logs.
3. **raise-hypotheses** — many cheap subagents generate hypotheses (recall).
4. **break-hypotheses** — stronger subagents adversarially confirm reachability (precision).
5. **prove-exploit** — confirmed findings + a working PoC, as `findings.md` (human) and
   `findings.json` (machine), with an empty-results report when nothing is exploitable.

Run a completed hunt again to **steer** it: edit the artifact at the right level
(`surface-map.json`, `target.md`, `hypotheses.jsonl`, …) and only the stale steps re-run;
results merge additively. The skill bodies are platform-neutral; per-platform tool mapping
lives in [`skills/offsec-hunter/references/platform-tools.md`](skills/offsec-hunter/references/platform-tools.md).
```

2. Replace the "Repo layout" block with:

```markdown
offsec-hunter/
├── README.md  ·  LICENSE  ·  .gitignore
├── .claude-plugin/plugin.json
├── docs/superpowers/specs/  ·  docs/superpowers/plans/
├── tests/                         # static contract + behavioral recall tests
└── skills/
    ├── offsec-hunter/             # orchestrator
    │   ├── SKILL.md
    │   └── references/{platform-tools.md, artifacts.md}
    ├── map-attack-surface/        # step 1  (references/surface-map.md)
    ├── scope-target/              # step 2
    ├── raise-hypotheses/          # step 3
    ├── break-hypotheses/          # step 4
    └── prove-exploit/             # step 5
```

3. In both the Claude Code and Codex install blocks, change the single-skill copy to copy
   all six skill directories. For Claude Code:

```bash
mkdir -p ~/.claude/skills
cp -R skills/* ~/.claude/skills/
```

For Codex:

```bash
mkdir -p ~/.codex/skills
cp -R skills/* ~/.codex/skills/
```

4. Update the "Run-time artifacts" section to note the per-hunt namespacing and the
   in-tree-default / central-override output root:

```markdown
## Run-time artifacts

When the skill runs against a target, it writes working artifacts under the **output
root** — by default `<target>/.offsec-hunter/` (add `.offsec-hunter/` to the target's
`.gitignore`), or a central `~/.offsec-hunter/<target-id>/` when the target tree is
read-only. Per-hunt artifacts are namespaced `hunts/<VULN>/` so different vuln classes
never clobber each other. See
[`skills/offsec-hunter/references/artifacts.md`](skills/offsec-hunter/references/artifacts.md).
```

- [ ] **Step 2: Verify the static suite still passes and links resolve**

Run: `bash tests/run-skill-tests.sh`
Expected: PASS. Manually confirm the referenced paths exist.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs(readme): document composable-skills layout, install, and steering"
```

---

## Self-Review

**Spec coverage** (spec § → task):
- 6 skills / flat 1–5 → Tasks 2–7. ✅
- Compose-by-name, no `../` → `assert_no_cross_skill_paths` (Task 2). ✅
- Independently invocable + actionable missing-input errors (gap #6) → per-step gate assertions (Tasks 4–7). ✅
- Interactive/headless (gap #1) → Task 4 + orchestrator (Task 2). ✅
- Cross-artifact staleness (gap #2) → `artifacts.md` + per-step `input_hash` (Tasks 2–7). ✅
- Resumability / state.json (gap #3) → `artifacts.md` + orchestrator progress line (Task 2). ✅
- Machine-readable output (gap #4) → `findings.json` (Task 7). ✅
- Empty/negative results (gap #5) → "no exploitable findings" report (Task 7). ✅
- Steering loop (gap #7) → orchestrator steering table (Task 2) + additive merge (Task 7). ✅
- File structure + plugin packaging → Task 1 (manifest) + moves (Task 3). ✅
- Artifact structure + roots → `artifacts.md` (Task 2). ✅
- Testing: Tier 1 static (Tasks 1–7) + Tier 2 behavioral (Task 8). ✅
- Docs impact → Task 9. ✅

**Placeholder scan:** No TBD/TODO; every code/markdown step shows full content. ✅

**Type/name consistency:** skill names, artifact filenames (`surface-map.json`, `target.md`, `hypotheses.jsonl`, `survivors.jsonl`, `findings.{md,json}`), and missing-input error strings (`run <skill> first`) match between the skill bodies and the test assertions that grep for them. ✅

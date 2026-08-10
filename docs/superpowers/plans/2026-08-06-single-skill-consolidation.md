# Single-skill consolidation Implementation Plan

> ❌ **SUPERSEDED — DO NOT EXECUTE.** This plan was implemented and reverted the same day.
> Its premise — that neither Claude Code nor Codex supports skill-to-skill invocation — is
> false; the superpowers plugin does it as its core pattern. See
> [`../specs/2026-08-06-skill-invocation-idiom-design.md`](../specs/2026-08-06-skill-invocation-idiom-design.md)
> for the architecture that replaced it. Kept as a record of the wrong turn.

**Goal:** Collapse seven skills into one discoverable skill (`offsec-hunter`) whose six step bodies live as flat `references/` files, so the orchestrator is the only thing the platform can trigger and the only thing that knows about the steps.

**Architecture:** `skills/offsec-hunter/SKILL.md` is the sole skill. The six step directories are deleted and their bodies become `references/step-N-<name>.md`, loaded by the orchestrator with an explicit read instruction. Schemas fold into their step file because Claude Code's best practices require references to be one level deep from SKILL.md. Runtime subagent isolation and the context-injection contract are untouched — they never depended on file layout.

**Tech Stack:** Markdown skills, bash contract tests (`tests/`).

**Spec:** [`docs/superpowers/specs/2026-08-06-single-skill-consolidation-design.md`](../specs/2026-08-06-single-skill-consolidation-design.md)

## Global Constraints

- No application code. Tests are `grep` contract assertions over markdown in `tests/test-static-contracts.sh`. Every wording change pairs with its assertion change **in the same task**. Run `bash tests/run-skill-tests.sh` after every edit; it must end green (0 failed) at the end of every task.
- **References are flat and one level deep from `SKILL.md`.** A file in `references/` must never point at another file to be read. This replaces the retired "no cross-skill relative paths" rule.
- **`SKILL.md` is the only file guaranteed to load.** Anything that must hold even if a reference is never read belongs in `SKILL.md`.
- **Platform-neutral skill prose.** Concrete agent-tool names belong only in `references/platform-tools.md`. No `$ARGUMENTS` token.
- **Language- and ecosystem-neutral target prose.** Operations described by behaviour ("issues an outbound network request", "starts a subprocess"), never by a concrete API name. Paths in schemas are illustrative placeholders. Vendored-dependency layouts are examples of a pattern, not an exhaustive list.
- **Orchestrator is sole id authority**; subagents return untagged judgments keyed by `sink`; break subagents only *flag* chainability.
- Preserve verbatim, in whichever file they end up: the step-1 comprehension-only rule, the step-1 reachability bound, the 2-consecutive-dry-round stop rule, the `round > 6` backstop, the family registry, resumability via `state.json`, additive merge, and single-owner `run.md` regeneration.
- Work on a branch off the current one: `git checkout -b feat/single-skill-consolidation`. Never commit to `master`.

---

### Task 1: Move the six step bodies into references/

**Files:**
- Create: `skills/offsec-hunter/references/step-1-map-attack-surface.md`, `step-2-scope-target.md`, `step-3-locate-sinks.md`, `step-4-raise-hypotheses.md`, `step-5-break-hypotheses.md`, `step-6-prove-exploit.md`
- Delete: `skills/map-attack-surface/`, `skills/scope-target/`, `skills/locate-sinks/`, `skills/raise-hypotheses/`, `skills/break-hypotheses/`, `skills/prove-exploit/` (whole directories)
- Modify: `tests/test-static-contracts.sh`

**Why this task is large and atomic:** the suite cannot be green with the bodies half-moved — any split leaves assertions pointing at files that no longer exist. The work is mechanical: a `git mv` plus three deletions per file.

**Interfaces:**
- Produces: six reference files whose *content* is otherwise byte-identical to the old step bodies. Later tasks reference them by these exact paths.

- [ ] **Step 1: Move the files with git mv**

```bash
cd "$(git rev-parse --show-toplevel)"
git mv skills/map-attack-surface/SKILL.md   skills/offsec-hunter/references/step-1-map-attack-surface.md
git mv skills/scope-target/SKILL.md         skills/offsec-hunter/references/step-2-scope-target.md
git mv skills/locate-sinks/SKILL.md         skills/offsec-hunter/references/step-3-locate-sinks.md
git mv skills/raise-hypotheses/SKILL.md     skills/offsec-hunter/references/step-4-raise-hypotheses.md
git mv skills/break-hypotheses/SKILL.md     skills/offsec-hunter/references/step-5-break-hypotheses.md
git mv skills/prove-exploit/SKILL.md        skills/offsec-hunter/references/step-6-prove-exploit.md
```

- [ ] **Step 2: Fold the two schema files into their step file, then remove the old dirs**

Append the **body** of `skills/map-attack-surface/references/surface-map.md` (everything after its `# Attack-surface map — schema & freshness` H1) to `references/step-1-map-attack-surface.md` under a new `## surface-map.json — schema & freshness` H2. Do the same for `skills/locate-sinks/references/sinks.md` (its H1 is `# sinks.json — schema`) into `references/step-3-locate-sinks.md` under `## sinks.json — schema`.

Then:

```bash
git rm -r skills/map-attack-surface skills/scope-target skills/locate-sinks \
          skills/raise-hypotheses skills/break-hypotheses skills/prove-exploit
```

Verify only one skill remains:

```bash
ls skills/
```

Expected: `offsec-hunter` only.

- [ ] **Step 3: Apply the three deletions to each of the six reference files**

For **every** `references/step-*.md`, make exactly these changes and nothing else:

1. Delete the YAML frontmatter block (the `---` … `---` at the top, including both fences).
2. Delete the standalone-trigger guard line: **`**Guard:** If `state.json` is absent, stop with "run the `offsec-hunter` orchestrator first".`** and the blank line after it.
3. Change the H1 from `# <name> — step N` to `# Step N — <name>`.

Everything else — the Gate sections, procedures, schemas, JSON examples, and the gate errors that name upstream steps ("run `locate-sinks` first") — is preserved verbatim. Gate errors are human-readable messages, not cross-skill reaches.

- [ ] **Step 4: Repoint the test variables**

In `tests/test-static-contracts.sh`, replace the seven step-path variable assignments (at lines ~34, 43, 55, 65, 74, 84, and the duplicate at ~200) so that each points at its reference file. Define each exactly once, all together, immediately after the `O=` line:

```bash
O="skills/offsec-hunter/SKILL.md"
M="skills/offsec-hunter/references/step-1-map-attack-surface.md"
S="skills/offsec-hunter/references/step-2-scope-target.md"
L="skills/offsec-hunter/references/step-3-locate-sinks.md"
R="skills/offsec-hunter/references/step-4-raise-hypotheses.md"
B="skills/offsec-hunter/references/step-5-break-hypotheses.md"
P="skills/offsec-hunter/references/step-6-prove-exploit.md"
```

Delete the now-duplicate `L=` assignment further down the file.

- [ ] **Step 5: Retire the assertions the move invalidates**

Delete these assertions, which test properties that no longer exist:

- `assert_file_contains "$M" '^name: map-attack-surface'` and the five sibling `^name: …` frontmatter assertions for `$S`, `$L`, `$R`, `$B`, `$P`.
- The whole `for V in "$M" "$S" "$L" "$R" "$B" "$P"; do` loop asserting `[Uu]se when` and the standalone-trigger guard.
- The `for d in map-attack-surface scope-target locate-sinks …; do` loop asserting each step dir has no `platform-tools.md` / `artifacts.md`.
- `assert_no_cross_skill_paths "no cross-skill relative paths"`.
- `assert_file_absent "skills/offsec-hunter/references/surface-map.md" …` if present.

Update these path-bearing assertions to the new locations:

- `assert_file_exists "skills/map-attack-surface/references/surface-map.md" …` → delete (folded into `$M`); replace with `assert_file_contains "$M" 'surface-map\.json — schema' "step1 carries its schema inline"`.
- `assert_file_exists "skills/locate-sinks/references/sinks.md" …` → delete; replace with `assert_file_contains "$L" 'sinks\.json — schema' "step3 carries its schema inline"`.
- Any remaining `assert_file_contains "skills/map-attack-surface/references/surface-map.md" …` or `"skills/locate-sinks/references/sinks.md" …` → repoint to `"$M"` / `"$L"`.
- `assert_file_contains "$M" 'surface-map\.md' "step1 references its schema"` → delete (schema is now inline).
- `assert_file_contains "$L" 'sinks\.md' "step3 references its schema"` → delete.

- [ ] **Step 6: Run the tests**

```bash
bash tests/run-skill-tests.sh
```

Expected: 0 failed. The orchestrator still describes the old "invoke by name" flow — that is Task 2's scope and is not asserted against yet.

- [ ] **Step 7: Commit**

```bash
git add -A skills tests && git commit -m "refactor(skills): move six step bodies into offsec-hunter/references"
```

---

### Task 2: Rewrite the orchestrator

**Files:**
- Modify: `skills/offsec-hunter/SKILL.md`
- Modify: `tests/test-static-contracts.sh`

**Interfaces:**
- Consumes: the six reference paths from Task 1.
- Produces: the load instruction and per-step binding constraints that every later task and reader depends on.

- [ ] **Step 1: Write the failing assertions**

Add to the orchestrator block in `tests/test-static-contracts.sh`:

```bash
assert_file_contains "$O" 'references/step-1-map-attack-surface\.md' "orchestrator names step 1 reference"
assert_file_contains "$O" 'references/step-6-prove-exploit\.md' "orchestrator names step 6 reference"
assert_file_contains "$O" '[Rr]ead .references/step' "orchestrator instructs reading the step file"
assert_file_contains "$O" 'comprehension only' "orchestrator carries step 1 binding constraint"
assert_file_contains "$O" 'write .?state\.json.? .*before|before .*step 1' "orchestrator writes state.json before step 1"
assert_file_not_contains "$O" 'invoke the .[a-z-]+. skill' "orchestrator no longer says invoke-by-name"
assert_file_not_contains "$O" 'Never reach into' "orchestrator drops the reach-into prohibition"
```

- [ ] **Step 2: Run to verify they fail**

```bash
bash tests/run-skill-tests.sh
```

Expected: FAIL on the seven new assertions.

- [ ] **Step 3: Replace the step list in `skills/offsec-hunter/SKILL.md`**

Each line names its reference file and its one binding constraint, so the constraint holds even if the reference is never read:

```markdown
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
```

- [ ] **Step 4: Replace the Enforcement section**

Replace the existing `### Enforcement — read this first` list with:

```markdown
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
```

- [ ] **Step 5: Update the two remaining stale references**

In the "How this skill runs" paragraph, the phrase "It runs six composable skills" becomes "It runs six artifact-gated steps, each defined in a reference file". In the context-injection section, the phrase "not the orchestrator's invoked skills" becomes "not the orchestrator's conversation or reference files".

- [ ] **Step 6: Run the tests**

```bash
bash tests/run-skill-tests.sh
```

Expected: 0 failed.

- [ ] **Step 7: Commit**

```bash
git add skills tests && git commit -m "refactor(orchestrator): load step references explicitly, carry binding constraints"
```

---

### Task 3: Enforce the new structural invariants

**Files:**
- Modify: `tests/test-helpers.sh`
- Modify: `tests/test-static-contracts.sh`

**Interfaces:**
- Consumes: the layout produced by Tasks 1–2.
- Produces: two helpers that lock the layout so it cannot silently regress.

- [ ] **Step 1: Replace the retired helper in `tests/test-helpers.sh`**

Delete `assert_no_cross_skill_paths` entirely and add these two:

```bash
# Fails if more than one SKILL.md exists — offsec-hunter must be the only skill.
assert_single_skill() {
  local label="$1" count
  count="$(find "$REPO_ROOT/skills" -name SKILL.md | wc -l | tr -d ' ')"
  if [ "$count" = "1" ]; then echo "  [PASS] $label"; PASS=$((PASS+1));
  else echo "  [FAIL] $label — found $count SKILL.md files, expected 1"; FAIL=$((FAIL+1)); fi
}

# Fails if a reference file points at another file to read (references must be
# one level deep from SKILL.md, or Claude may only partially read them).
assert_references_one_level() {
  local label="$1" hits
  hits="$(grep -REn '\]\([^)]*\.md\)|read [`"'"'"']?references/' \
    "$REPO_ROOT/skills/offsec-hunter/references" 2>/dev/null || true)"
  if [ -z "$hits" ]; then echo "  [PASS] $label"; PASS=$((PASS+1));
  else echo "  [FAIL] $label — nested reference found:"; echo "$hits"; FAIL=$((FAIL+1)); fi
}
```

- [ ] **Step 2: Add the assertions and run to verify they fail if violated**

Add near the top of `tests/test-static-contracts.sh`, after the `O=`…`P=` block:

```bash
assert_single_skill "offsec-hunter is the only skill"
assert_references_one_level "references are one level deep"
```

Prove both actually bite. Create a decoy skill and a nested reference, run the suite, confirm 2 failures, then remove them and confirm green:

```bash
mkdir -p skills/decoy && printf -- '---\nname: decoy\ndescription: x\n---\n' > skills/decoy/SKILL.md
printf '\nSee [other.md](other.md)\n' >> skills/offsec-hunter/references/step-2-scope-target.md
bash tests/run-skill-tests.sh   # expect exactly 2 failures
rm -rf skills/decoy
git checkout skills/offsec-hunter/references/step-2-scope-target.md
bash tests/run-skill-tests.sh   # expect 0 failures
```

- [ ] **Step 3: Commit**

```bash
git add tests && git commit -m "test: lock single-skill layout and one-level references"
```

---

### Task 4: Correct the platform guide

**Files:**
- Modify: `skills/offsec-hunter/references/platform-tools.md`
- Modify: `tests/test-static-contracts.sh`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: the honest platform mapping the orchestrator defers to.

- [ ] **Step 1: Write the failing assertions**

```bash
PT="skills/offsec-hunter/references/platform-tools.md"
assert_file_contains "$PT" 'inherit' "platform guide states Codex subagents inherit the model"
assert_file_contains "$PT" 'read the reference file|Read tool|cat' "platform guide maps loading a step reference"
assert_file_not_contains "$PT" 'select a fast/cheap model for the task' "platform guide drops the false Codex model-tiering claim"
```

- [ ] **Step 2: Run to verify they fail**

```bash
bash tests/run-skill-tests.sh
```

Expected: FAIL on all three.

- [ ] **Step 3: Fix the three claims**

Replace the "...on a cheap/fast model" and "...stronger model for validation" rows' Codex column with `inherits the orchestrator's model — see note` and add these notes at the bottom of the file:

```markdown
- **Model tiering is Claude Code only.** Codex subagents **inherit the orchestrator's
  model**; per-task model selection is not currently available. On Codex the cheap/strong
  split does not apply — run every step on the session model and rely on the artifact
  gating, not on cost tiering, for control.
- **Fan-out width differs.** Codex guidance is to keep delegation concurrency at 1 unless
  there is a specific reason, and warns that broad delegation instructions cause repeated
  fan-out. On Codex, run the per-item steps (`step-4-raise-hypotheses`,
  `step-5-break-hypotheses`) with a small fixed concurrency or sequentially. Artifact
  gating and step order are unchanged either way.
- **Codex delegates on an explicit instruction.** Codex spawns subagents after a direct
  request or an applicable skill instruction, so phrase delegation imperatively
  ("spawn one agent per sink"), not as a description.
```

Replace the `"Dispatch a subagent"` row's Codex cell with `spawn agents explicitly ("spawn one agent per sink")`, and add a new first row:

| Action in SKILL.md | Claude Code | Codex |
|---|---|---|
| "read the step reference file" | `Read` tool on `references/step-N-*.md` | read the file at `references/step-N-*.md` |

- [ ] **Step 4: Run the tests**

```bash
bash tests/run-skill-tests.sh
```

Expected: 0 failed.

- [ ] **Step 5: Commit**

```bash
git add skills tests && git commit -m "fix(platform-tools): correct Codex model-tiering and fan-out claims"
```

---

### Task 5: Docs, migration, behavioral test, version

**Files:**
- Modify: `README.md`, `CLAUDE.md`, `tests/test-behavioral-recall.sh`, `.claude-plugin/plugin.json`

**Interfaces:**
- Consumes: the final layout from Tasks 1–4.
- Produces: nothing downstream.

- [ ] **Step 1: Update `tests/test-behavioral-recall.sh`**

The step-name checks stay as they are (the workflow still has six named steps). Add one check that the agent describes the single-skill structure:

```bash
check "$out" 'reference|references/' "describes step references"
```

- [ ] **Step 2: Update `README.md`**

- "The plugin is made of seven composable skills" → "The plugin is **one skill** — `offsec-hunter` — whose six steps live as reference files it loads on demand".
- "`offsec-hunter` ships as seven composable" → "`offsec-hunter` ships as a single".
- Replace the repo-layout skills tree with:

```
└── skills/
    └── offsec-hunter/             # the only skill
        ├── SKILL.md               # orchestrator
        └── references/
            ├── platform-tools.md  ·  artifacts.md
            └── step-1-map-attack-surface.md … step-6-prove-exploit.md
```

- Add a **Upgrading from 1.x** subsection under Install, immediately after the Codex block:

```markdown
### Upgrading from 1.x

1.x installed seven separate skills. Overwriting with `cp -R` leaves the six old step
directories in place, where they stay independently triggerable and contradict the
consolidated orchestrator. Remove them first:

```bash
rm -rf ~/.claude/skills/{map-attack-surface,scope-target,locate-sinks,raise-hypotheses,break-hypotheses,prove-exploit}
rm -rf ~/.codex/skills/{map-attack-surface,scope-target,locate-sinks,raise-hypotheses,break-hypotheses,prove-exploit}
```

Then re-run the `cp -R` for your tool.
```

- Add to the design-rationale paragraph: `the single-skill consolidation is designed in [`docs/superpowers/specs/2026-08-06-single-skill-consolidation-design.md`](docs/superpowers/specs/2026-08-06-single-skill-consolidation-design.md).`

- [ ] **Step 3: Update `CLAUDE.md`**

- "a set of seven markdown skills (`skills/*/SKILL.md`)" → "a single markdown skill (`skills/offsec-hunter/SKILL.md`) whose six steps are reference files under `skills/offsec-hunter/references/`".
- In the architecture table, change the Step column entries to name the reference file rather than a skill (e.g. `references/step-1-map-attack-surface.md`).
- Replace the **No cross-skill relative paths** invariant with:

```markdown
- **One skill, flat references.** `offsec-hunter` is the only `SKILL.md`; the six step
  bodies are `references/step-N-*.md`. Neither platform supports skill-to-skill
  invocation, and Claude Code has no frontmatter for a skill only the orchestrator may
  invoke — so steps must not be skills (both asserted). References are **flat and one
  level deep**: a reference file must never point at another file to read, or Claude may
  read it only partially.
- **`SKILL.md` is the only guaranteed context.** Anything that must hold even if a
  reference is never read belongs in `SKILL.md` — which is why each step line there
  carries its one binding constraint.
```

- Delete the final Conventions bullet about "Use when" clauses and standalone-trigger guards.

- [ ] **Step 4: Bump the version**

In `.claude-plugin/plugin.json`, change `"version": "1.2.0"` to `"version": "2.0.0"` (breaking layout change).

- [ ] **Step 5: Run Tier 1 and verify the docs**

```bash
bash tests/run-skill-tests.sh
```

Expected: 0 failed.

```bash
grep -rn "seven composable\|skills/\*/SKILL.md\|map-attack-surface/" README.md CLAUDE.md
```

Expected: no hits (no stale layout references remain).

Do **not** run Tier 2 or `cp -R` into `~/.claude/skills` or `~/.codex/skills` — installing is the controller's call, and the migration needs the removal step above run first.

- [ ] **Step 6: Commit**

```bash
git add README.md CLAUDE.md tests .claude-plugin && git commit -m "docs: single-skill layout, 1.x migration, bump to 2.0.0"
```

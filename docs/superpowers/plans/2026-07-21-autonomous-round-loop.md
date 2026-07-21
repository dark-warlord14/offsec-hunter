# Autonomous Round-Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade offsec-hunter from a single-pass pipeline into an autonomous, round-based hunt (raise→break loop with synthesis/redirect), while preserving single-pass behaviour.

**Architecture:** Plan A — the round loop lives in the orchestrator SKILL.md; steps 1/2/5 run once, steps 3/4 iterate. All round state and the approach-family registry live in `state.json` so the loop is resumable. Every artifact gains stable ids so a finding traces back to a mapped sink. Changes are documentation/skill-markdown only; there is no runtime code.

**Tech Stack:** Markdown skills (Agent Skills open standard), JSON/JSONL artifacts, bash static-contract tests (`tests/test-static-contracts.sh` + `tests/test-helpers.sh`).

## Global Constraints

- **No skill renames.** Directory + frontmatter `name` stay: `map-attack-surface`, `scope-target`, `raise-hypotheses`, `break-hypotheses`, `prove-exploit`, `offsec-hunter`.
- **No new step and no new skill.** The loop lives in the orchestrator only.
- **Stop rule = 2 consecutive dry rounds** (no new survivor AND no materially-new family). Soft backstop: log a loud warning when `round > 6`. No budget-cap / max-round / found-enough rule.
- **Frontmatter hygiene:** no angle brackets (`<`/`>`) anywhere in frontmatter; `description` ≤ 1024 chars; `name` kebab-case matching the folder; no `model` / `allowed-tools` keys.
- **`rounds = 1` must reproduce today's single-pass behaviour** (regression guard).
- **Tests are non-LLM static-contract bash** unless noted. Run with `bash tests/run-skill-tests.sh`. Add assertions by appending blocks to `tests/test-static-contracts.sh`; reuse the existing `assert_file_contains` / `assert_file_absent` helpers.

---

## Shared vocabulary (used across tasks)

These names are the interface contract every task must match verbatim.

**`state.json` new top-level fields:** `round` (int), `dry_streak` (int), `families` (array), `round_log` (array).

**Family object:** `{"id","label","status","agents","hypotheses","last_new_round","notes"}` where `status` ∈ `open | blocked`.

**Round-log entry:** `{"round","raised","survived","new_families","redirects"}`.

**Stable ids + forward refs:**
- `surface-map.json` sink: `"id": "sink-3"`.
- `hypotheses.jsonl` line adds: `"family"`, `"sink"`.
- `survivors.jsonl` line adds: `"hypothesis"`, `"sink"`, `"chain"` (array), `"severity"`, `"confidence"`.
- `findings.json` object adds: `"survivor"`, `"hypothesis"`, `"sink"`, `"severity"`, `"confidence"`.

**Context-injection contract (raise/break subagent prompts):** each prompt carries `output_root`, `target_root`, exact artifact paths to read, the assigned `sink-N` id + family, and a one-line threat-model summary.

**Dashboard:** `run.md` written by the orchestrator at loop exit.

---

## Task 1: Artifacts guide — round state, family registry, traceable ids

**Files:**
- Modify: `skills/offsec-hunter/references/artifacts.md`
- Test: `tests/test-static-contracts.sh` (append block)

**Interfaces:**
- Consumes: nothing (defines the contract).
- Produces: the `state.json` shape and id/ref conventions every later task references.

- [ ] **Step 1: Write the failing assertions**

Append to `tests/test-static-contracts.sh` immediately above the final `summary` line:

```bash
# --- Round-loop artifacts (Task 1) ---
A="skills/offsec-hunter/references/artifacts.md"
assert_file_contains "$A" '"round"' "artifacts documents round field"
assert_file_contains "$A" '"dry_streak"' "artifacts documents dry_streak field"
assert_file_contains "$A" '"families"' "artifacts documents family registry"
assert_file_contains "$A" '"round_log"' "artifacts documents round_log"
assert_file_contains "$A" 'sink-[0-9]' "artifacts documents stable sink ids"
assert_file_contains "$A" '[Rr]esumable' "artifacts documents resumable loop"
assert_file_contains "$A" '"chain"' "artifacts documents chain field"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/run-skill-tests.sh`
Expected: FAIL lines for the seven new assertions ("not in skills/offsec-hunter/references/artifacts.md").

- [ ] **Step 3: Add the round-state + registry section**

Append this section to `skills/offsec-hunter/references/artifacts.md` (after the existing `## Gating & staleness` section):

````markdown
## Round state & family registry

The hunt runs in rounds; all round state lives in `state.json` so a fresh or compacted
orchestrator resumes mid-hunt (a **resumable** loop). Each round starts by reading
`state.json`.

```json
{
  "round": 2,
  "dry_streak": 1,
  "families": [
    {"id":"f-deser","label":"PHP object deserialization","status":"open",
     "agents":2,"hypotheses":["h-1","h-4"],"last_new_round":2,"notes":"..."}
  ],
  "round_log": [
    {"round":1,"raised":12,"survived":2,"new_families":5,"redirects":["blocked f-cache"]},
    {"round":2,"raised":9,"survived":0,"new_families":0,"redirects":["blocked f-deser"]}
  ]
}
```

- `families[].status` ∈ `open | blocked`. A blocked family reopens only on a
  materially-new mechanism.
- A round is **dry** when it yields no new survivor AND no new family. Exit after 2 dry
  rounds in a row; log a loud warning when `round > 6`.

## Stable ids & forward references

Every artifact carries ids so a finding traces back to a mapped sink:

- `surface-map.json` sink: `"id": "sink-3"`.
- `hypotheses.jsonl` line: adds `"family"` and `"sink"`.
- `survivors.jsonl` line: adds `"hypothesis"`, `"sink"`, `"chain": [...]` (ordered step
  ids for multi-step chains), `"severity"`, `"confidence"`.
- `findings.json`: adds `"survivor"`, `"hypothesis"`, `"sink"`, `"severity"`,
  `"confidence"` — the full trace `finding → survivor → hypothesis → sink`.

`run.md` is a human-readable dashboard written at loop exit (rounds, family registry,
per-round lines, findings with trace ids).
````

- [ ] **Step 4: Run to verify it passes**

Run: `bash tests/run-skill-tests.sh`
Expected: PASS for all seven Task 1 assertions; overall `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add skills/offsec-hunter/references/artifacts.md tests/test-static-contracts.sh
git commit -m "feat(artifacts): document round state, family registry, traceable ids"
```

---

## Task 2: Orchestrator — round loop, stop rule, synth/redirect, resumability

**Files:**
- Modify: `skills/offsec-hunter/SKILL.md`
- Test: `tests/test-static-contracts.sh` (append block)

**Interfaces:**
- Consumes: `state.json` shape + registry from Task 1.
- Produces: the loop contract (stop rule, synth/redirect, context-injection, run.md) that steps 3–6 obey.

- [ ] **Step 1: Write the failing assertions**

Append to `tests/test-static-contracts.sh` above `summary`:

```bash
# --- Orchestrator round loop (Task 2) ---
assert_file_contains "$O" '[Rr]ound loop' "orchestrator documents the round loop"
assert_file_contains "$O" '2 (consecutive |)dry rounds' "orchestrator states the dry-round stop rule"
assert_file_contains "$O" 'round > 6|round &gt; 6' "orchestrator has soft backstop"
assert_file_contains "$O" '[Ff]amily registry' "orchestrator manages the family registry"
assert_file_contains "$O" '[Bb]locked' "orchestrator documents blocked families"
assert_file_contains "$O" '[Rr]edirect' "orchestrator documents redirect"
assert_file_contains "$O" '[Rr]esumable|reads state\.json' "orchestrator documents resumable loop"
assert_file_contains "$O" '[Cc]ontext-injection|inject' "orchestrator documents context-injection contract"
assert_file_contains "$O" 'run\.md' "orchestrator writes run.md dashboard"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/run-skill-tests.sh`
Expected: FAIL for the nine new Task 2 assertions.

- [ ] **Step 3: Add the round-loop section to the orchestrator**

Insert this section into `skills/offsec-hunter/SKILL.md` after the `### Progress` subsection and before `## Vuln class`:

````markdown
## Round loop (steps 3–4)

Steps 1 (map) and 2 (scope) run once. Steps 3 (raise) and 4 (break) are the body of a
**round loop**. Step 5 (prove) runs once at loop exit. With a single productive round this
is exactly the old single-pass flow.

Each round:

1. **Read `state.json`** for the resume point (`round`, `dry_streak`, `families`). This is
   what makes the loop **resumable** — a fresh or compacted orchestrator continues instead
   of restarting.
2. Run `raise-hypotheses` then `break-hypotheses` for this round.
3. **Synthesize** (orchestrator, reading only compact summaries + this round's jsonl —
   never full subagent transcripts):
   - Count new survivors and new families.
   - Mark any family that produced nothing new as **blocked** (reopen only on a
     materially-new mechanism).
   - **Redirect**: pull agents off crowded/blocked families and point them at mapped sinks
     no family covers yet; keep at least one agent on each still-productive incompatible
     route so routes stay alive across rounds.
   - Append a one-line entry to `state.json.round_log` and to `run.md`.
4. **Stop rule**: exit after **2 consecutive dry rounds** (a dry round = no new survivor
   AND no new family). Soft backstop: log a loud warning when `round > 6` (the dry-round
   rule still governs; the warning is auditability, not a hard cap).

### Context-injection contract (critical)

A subagent sees only its delegation prompt plus CLAUDE.md — not the orchestrator's invoked
skills, conversation, or files already read. Every raise/break delegation prompt MUST
**inject**: `output_root` and `target_root`, the exact artifact paths to read, the assigned
`sink-N` id + its family, and a one-line threat-model summary. The family registry stays
orchestrator-only; a subagent receives only its slice in-prompt.

### run.md dashboard

At loop exit the orchestrator writes `run.md`: rounds executed, the family registry
(open/blocked + counts), the per-round lines, and the final findings with their trace ids.
Steered re-runs append (matching `prove-exploit`'s additive merge).
````

- [ ] **Step 4: Run to verify it passes**

Run: `bash tests/run-skill-tests.sh`
Expected: PASS for all nine Task 2 assertions; overall `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add skills/offsec-hunter/SKILL.md tests/test-static-contracts.sh
git commit -m "feat(orchestrator): add resumable round loop, stop rule, synth/redirect"
```

---

## Task 3: map-attack-surface — stable sink ids + third_party indexing

**Files:**
- Modify: `skills/map-attack-surface/SKILL.md`
- Test: `tests/test-static-contracts.sh` (append block)

**Interfaces:**
- Consumes: sink-id convention from Task 1.
- Produces: `sink-N` ids and dependency sinks consumed by raise/break.

- [ ] **Step 1: Write the failing assertions**

Append to `tests/test-static-contracts.sh` above `summary`:

```bash
# --- map dependency sinks + ids (Task 3) ---
assert_file_contains "$M" 'sink-[0-9]|stable id' "step1 assigns stable sink ids"
assert_file_contains "$M" '[Dd]ependenc' "step1 conditionally indexes vendored dependencies"
assert_file_contains "$M" '[Ii]f|when|present' "step1 makes dependency indexing conditional"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/run-skill-tests.sh`
Expected: FAIL for the two Task 3 assertions.

- [ ] **Step 3: Edit the map skill**

In `skills/map-attack-surface/SKILL.md`, in the `## Procedure` list under **High-risk sinks**, append this sentence to that bullet:

```markdown
     Assign each sink a **stable id** (`sink-1`, `sink-2`, …) so downstream artifacts can
     reference it.
```

Then add a new bullet to the same numbered list, after **Input flow**:

```markdown
   - **Dependency sinks (conditional)** — **if** the target vendors its dependencies
     (common layouts: `third_party/`, `vendor/`, `node_modules/`, `deps/`, or a
     lockfile-declared tree), index high-risk code in them as sinks too, with their own
     `sink-N` ids. RCE may require chaining a target bug with a dependency bug. If no
     vendored deps are present, skip this — emit no dependency sinks and no error.
```

- [ ] **Step 4: Run to verify it passes**

Run: `bash tests/run-skill-tests.sh`
Expected: PASS for both Task 3 assertions; overall `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add skills/map-attack-surface/SKILL.md tests/test-static-contracts.sh
git commit -m "feat(map): stable sink ids and third_party dependency sinks"
```

---

## Task 4: raise-hypotheses — round-aware, family + sink ids, context-injection

**Files:**
- Modify: `skills/raise-hypotheses/SKILL.md`
- Test: `tests/test-static-contracts.sh` (append block)

**Interfaces:**
- Consumes: `sink-N` ids (Task 3); context-injection contract (Task 2).
- Produces: `hypotheses.jsonl` lines carrying `family` + `sink`, consumed by break (Task 5).

- [ ] **Step 1: Write the failing assertions**

Append to `tests/test-static-contracts.sh` above `summary`:

```bash
# --- raise round-aware + ids (Task 4) ---
assert_file_contains "$R" '"family"' "step3 tags hypotheses with a family"
assert_file_contains "$R" '"sink"' "step3 references the sink id"
assert_file_contains "$R" '[Rr]ound' "step3 is round-aware"
assert_file_contains "$R" 'output_root|inject' "step3 injects context into subagents"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/run-skill-tests.sh`
Expected: FAIL for the four Task 4 assertions.

- [ ] **Step 3: Edit the raise skill**

In `skills/raise-hypotheses/SKILL.md`, replace the JSON example line with one that carries the new ids:

```json
{"id": "h-1", "family": "f-ssrf-fetch", "sink": "sink-3", "suspected_source": "body.url", "path": "POST /fetch -> validate() -> http.get()", "rationale": "no allowlist visible"}
```

Then append this paragraph after the JSON block, before the final "Record the step done" line:

```markdown
This step is **round-aware**: on each round the orchestrator tells you which families to
expand and which mapped sinks are still uncovered. Because a dispatched subagent sees only
its prompt, **inject its context** — pass `output_root`, `target_root`, the exact artifact
paths to read (`surface-map.json`, `hunts/<VULN>/target.md`), the assigned `sink-N` id and
family, and a one-line threat-model summary. Tag every hypothesis line with its `family`
and `sink`.
```

- [ ] **Step 4: Run to verify it passes**

Run: `bash tests/run-skill-tests.sh`
Expected: PASS for all four Task 4 assertions; overall `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add skills/raise-hypotheses/SKILL.md tests/test-static-contracts.sh
git commit -m "feat(raise): round-aware fan-out with family/sink ids and context injection"
```

---

## Task 5: break-hypotheses — chaining, trace fields, stall signal

**Files:**
- Modify: `skills/break-hypotheses/SKILL.md`
- Test: `tests/test-static-contracts.sh` (append block)

**Interfaces:**
- Consumes: `hypotheses.jsonl` with `family`/`sink` (Task 4).
- Produces: `survivors.jsonl` lines with `hypothesis`, `sink`, `chain`, `severity`, `confidence`, consumed by prove (Task 6).

- [ ] **Step 1: Write the failing assertions**

Append to `tests/test-static-contracts.sh` above `summary`:

```bash
# --- break chaining + trace (Task 5) ---
assert_file_contains "$B" '[Cc]hain' "step4 documents bug-chaining"
assert_file_contains "$B" '"chain"' "step4 records chain field on survivors"
assert_file_contains "$B" '"severity"' "step4 carries severity"
assert_file_contains "$B" '"confidence"' "step4 carries confidence"
assert_file_contains "$B" '[Dd]ependenc' "step4 chains dependency bugs when present"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/run-skill-tests.sh`
Expected: FAIL for the five Task 5 assertions.

- [ ] **Step 3: Edit the break skill**

In `skills/break-hypotheses/SKILL.md`, add a bullet to the refute checklist (after the win-condition bullet):

```markdown
- Can it **chain** with another candidate or a **dependency bug** (when dependency sinks
  exist — see map-attack-surface) to reach the win condition? A survivor may be a
  multi-step chain (e.g. auth-bypass → RCE).
```

Then replace the "Append confirmed-reachable survivors" sentence with one that specifies the traced record, and add the example line:

```markdown
Drop anything that fails any check. Append confirmed-reachable survivors to
`hunts/<VULN>/survivors.jsonl`, carrying the candidate fields plus the guards examined and
why they hold/fail. Each survivor references its `hypothesis` and `sink` ids, an ordered
`chain` (step ids), and `severity` + `confidence`:

```json
{"id":"s-2","hypothesis":"h-4","sink":"sink-3","chain":["h-7","h-4"],"severity":"high","confidence":"medium","guards":"nonce check bypassed via ..."}
```
```

- [ ] **Step 4: Run to verify it passes**

Run: `bash tests/run-skill-tests.sh`
Expected: PASS for all five Task 5 assertions; overall `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add skills/break-hypotheses/SKILL.md tests/test-static-contracts.sh
git commit -m "feat(break): bug-chaining across deps and traced survivor records"
```

---

## Task 6: prove-exploit — trace ids, severity/confidence, run.md contribution

**Files:**
- Modify: `skills/prove-exploit/SKILL.md`
- Test: `tests/test-static-contracts.sh` (append block)

**Interfaces:**
- Consumes: `survivors.jsonl` with trace fields (Task 5); `run.md` (Task 2).
- Produces: `findings.json` objects carrying the full trace.

- [ ] **Step 1: Write the failing assertions**

Append to `tests/test-static-contracts.sh` above `summary`:

```bash
# --- prove trace + dashboard (Task 6) ---
assert_file_contains "$P" '"survivor"' "step5 traces finding to survivor"
assert_file_contains "$P" '"sink"' "step5 traces finding to sink"
assert_file_contains "$P" '"confidence"' "step5 carries confidence"
assert_file_contains "$P" 'run\.md' "step5 contributes to run.md dashboard"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/run-skill-tests.sh`
Expected: FAIL for the four Task 6 assertions.

- [ ] **Step 3: Edit the prove skill**

In `skills/prove-exploit/SKILL.md`, replace the `findings.json` example object with the traced version:

```json
{"id": "finding-001", "vuln_class": "SSRF", "entry_point": "POST /fetch", "trust_boundary": "unauth→server", "path": "body.url → http.get()", "survivor": "s-2", "hypothesis": "h-4", "sink": "sink-3", "severity": "high", "confidence": "high", "poc": "pocs/finding-001.sh"}
```

Then add this sentence to the end of the `## Steered re-runs — additive merge` section:

```markdown
Also update `run.md` (the run dashboard, written at loop exit): append this run's findings
with their trace ids (`finding → survivor → hypothesis → sink`) so the whole hunt is
auditable in one human-readable place.
```

- [ ] **Step 4: Run to verify it passes**

Run: `bash tests/run-skill-tests.sh`
Expected: PASS for all four Task 6 assertions; overall `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add skills/prove-exploit/SKILL.md tests/test-static-contracts.sh
git commit -m "feat(prove): full finding trace ids and run.md dashboard contribution"
```

---

## Task 7: Behavioral-recall test — loop doctrine

**Files:**
- Modify: `tests/test-behavioral-recall.sh`

**Interfaces:**
- Consumes: orchestrator loop doctrine (Task 2). LLM-gated (`RUN_BEHAVIORAL=1`).
- Produces: nothing downstream.

- [ ] **Step 1: Add the failing behavioral checks**

In `tests/test-behavioral-recall.sh`, after the existing `out2` checks (before the final `[ "$fail" -eq 0 ]` line), append:

```bash
out3="$(run_claude 'In offsec-hunter, when does the hunt stop launching new rounds, and what is a family registry? Be brief.')"
check "$out3" 'dry|two rounds|2 rounds' "explains the dry-round stop rule"
check "$out3" 'famil' "explains the family registry"
check "$out3" 'block|redirect' "explains blocked/redirect behaviour"
```

- [ ] **Step 2: Run to verify (opt-in, needs LLM)**

Run: `RUN_BEHAVIORAL=1 bash tests/run-skill-tests.sh`
Expected: the three new checks PASS (given Task 2 is implemented). If no LLM/`claude` binary is available, this task is skipped; note that in the commit.

- [ ] **Step 3: Commit**

```bash
git add tests/test-behavioral-recall.sh
git commit -m "test(skills): behavioral recall for the round-loop doctrine"
```

---

## Task 8: README — document the round loop

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: everything above. Docs only.

- [ ] **Step 1: Update the "How it works" section**

In `README.md`, under the numbered steps, replace the steering paragraph's first sentence with text that mentions the loop. Add this line after the numbered list (before the "Run a completed hunt again" paragraph):

```markdown
Steps 3–4 run as an **autonomous round loop**: the orchestrator raises hypotheses, breaks
them, then synthesizes and redirects — grouping ideas into a family registry, blocking
stalled routes, and launching new rounds until two rounds in a row are dry. All round
state lives in `state.json`, so the loop is resumable.
```

- [ ] **Step 2: Verify the static tests still pass**

Run: `bash tests/run-skill-tests.sh`
Expected: overall `0 failed` (README is not asserted, but confirm nothing regressed).

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs(readme): document the autonomous round loop"
```

---

## Self-review notes

- **Spec coverage:** round loop + stop rule (Task 2), family registry + synth/redirect/blocked (Tasks 1–2), dependency chaining (Tasks 3, 5), traceable ids (Tasks 1, 3–6), run.md (Tasks 2, 6), modes (unchanged — existing tests cover; loop is non-blocking in both), context-injection contract (Tasks 2, 4), resumable loop (Tasks 1–2), orchestrator context hygiene (Task 2), frontmatter hygiene (Global Constraints — no frontmatter is edited, so it holds by construction).
- **`rounds = 1` regression:** no test file or step removed; the orchestrator explicitly states a single productive round equals the old flow.
- **Type/name consistency:** `sink-N`, `family`, `hypothesis`, `chain`, `severity`, `confidence`, `round`, `dry_streak`, `round_log` are used identically across Tasks 1–6.

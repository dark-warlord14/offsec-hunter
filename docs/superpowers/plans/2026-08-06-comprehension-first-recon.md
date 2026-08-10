# Comprehension-first recon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `map-attack-surface` comprehension-only (no vuln classes, no risk verdicts) and move all sink identification into a new `locate-sinks` step that runs after `scope-target`.

**Architecture:** Six sequential artifact-gated steps become seven skills. Everything security-flavoured is stripped from `surface-map.json` and relocated to a new per-hunt `hunts/<VULN>/sinks.json` owned by `locate-sinks`. `sink-N` ids keep their meaning and global uniqueness, so the `finding → survivor → hypothesis → sink` trace and the round-loop redirect are unchanged. Reachability-driven pruning stays in step 1 as its bounding rule.

**Tech Stack:** Markdown skills (`skills/*/SKILL.md`), bash contract tests (`tests/`).

**Spec:** [`docs/superpowers/specs/2026-08-06-comprehension-first-recon-design.md`](../specs/2026-08-06-comprehension-first-recon-design.md)

## Global Constraints

- This repo has **no application code**. The tests are contract tests over markdown: `grep` assertions in `tests/test-static-contracts.sh`. Every wording change must be paired with its assertion change in the same task.
- Run `bash tests/run-skill-tests.sh` after every edit. Tier 2 (`RUN_BEHAVIORAL=1`) makes real LLM calls — run it once at the end, not per task.
- **Platform-neutral skill bodies.** Speak in actions ("dispatch a subagent on a cheap model"). Concrete tool names belong only in `skills/offsec-hunter/references/platform-tools.md`. No `$ARGUMENTS` in skill bodies (asserted).
- **No cross-skill relative paths.** A skill invokes a sibling by name, never by path. Shared references live only under `skills/offsec-hunter/references/` (asserted).
- **Orchestrator is the sole id authority.** `locate-sinks` is orchestrator-run, not a subagent-assigned id space.
- **Language- and ecosystem-neutral target prose.** Never assume the target's language, framework, or runtime. Record operations as behaviour ("issues an outbound network request", "constructs a query from concatenated input", "starts a subprocess") — never as a concrete API name like `http.get()` or `subprocess.run()`. Every path, extension, and directory in a schema example is an illustrative placeholder (`path/to/file.ext:LINE`); the agent infers the target's real conventions from the target. Vendored-dependency layouts are examples of a pattern, never an exhaustive list. This extends the existing platform-neutrality invariant from the *agent's* runtime to the *target's* runtime.
- Every step skill's frontmatter description needs a "Use when" clause and its body a standalone-trigger guard pointing back at the orchestrator (both asserted).
- Work on a branch: `git checkout -b feat/comprehension-first-recon` before Task 1. Never commit to `master`.

---

### Task 1: Strip security judgment from step 1

**Files:**
- Modify: `skills/map-attack-surface/SKILL.md` (full rewrite)
- Modify: `skills/map-attack-surface/references/surface-map.md` (schema section + guidance)
- Test: `tests/test-static-contracts.sh:88-91`, `tests/test-static-contracts.sh:182`

**Interfaces:**
- Consumes: nothing (first step).
- Produces: `surface-map.json` with top-level keys `commit`, `target`, `entry_points[]` (`ep-N`), `trust_boundaries[]` (`tb-N`), `flows[]`, `assumptions[]` (`asm-N`). No `sinks[]` key. `flows[]` entries use `reaches` and `validation` (not `to_sink` / `guards`).

- [ ] **Step 1: Change the failing assertions first**

In `tests/test-static-contracts.sh`, replace the block at lines 88-91:

```bash
# --- map dependency sinks + ids (Task 3) ---
assert_file_contains "$M" 'sink-[0-9]|stable id' "step1 assigns stable sink ids"
assert_file_contains "$M" '[Dd]ependenc' "step1 conditionally indexes vendored dependencies"
assert_file_contains "$M" 'skip this|no.*dependency sinks' "step1 dependency indexing is conditional"
```

with:

```bash
# --- map is comprehension-only (2026-08-06) ---
assert_file_not_contains "$M" 'sink-[0-9]|high-risk sink|[Ss]inks —' "step1 emits no sinks"
assert_file_contains "$M" '[Cc]omprehension only' "step1 declares comprehension-only"
assert_file_contains "$M" 'asm-[0-9]|[Aa]ssumption' "step1 records assumptions"
assert_file_contains "$M" 'reachab' "step1 keeps reachability pruning as its bound"
assert_file_contains "$M" 'language|ecosystem' "step1 is language-agnostic"
assert_file_contains "skills/map-attack-surface/references/surface-map.md" 'asm-[0-9]' "surface-map schema has assumption ids"
assert_file_contains "skills/map-attack-surface/references/surface-map.md" 'language|ecosystem' "surface-map schema is language-agnostic"
assert_file_not_contains "skills/map-attack-surface/references/surface-map.md" '"sinks"' "surface-map schema has no sinks array"
```

And at line 182, replace:

```bash
assert_file_contains "skills/map-attack-surface/references/surface-map.md" 'origin' "surface-map schema includes origin field"
```

with:

```bash
assert_file_contains "skills/locate-sinks/references/sinks.md" 'origin' "sinks schema includes origin field"
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
bash tests/run-skill-tests.sh
```

Expected: FAIL on "step1 emits no sinks", "step1 declares comprehension-only", "step1 records assumptions", "step1 is language-agnostic", "surface-map schema has assumption ids", "surface-map schema is language-agnostic", "surface-map schema has no sinks array", and "sinks schema includes origin field" (that file does not exist until Task 2).

- [ ] **Step 3: Rewrite `skills/map-attack-surface/SKILL.md`**

Replace the whole file with:

```markdown
---
name: map-attack-surface
description: Step 1 of offsec-hunter. Build or refresh a reusable, commit-stamped model of how a target works — entry points, trust boundaries, input flows, and the assumptions the code makes. Comprehension only — no vulnerability classes and no risk verdicts. Reuses a fresh map automatically. Use when starting an offsec-hunter run or refreshing a target's map.
---

# map-attack-surface — step 1

**Guard:** If `state.json` is absent, stop with "run the `offsec-hunter` orchestrator first".

Goal: a structured model of **how the target works** — how external input enters, where
it flows, what boundaries it crosses, and what the code assumes.

**Comprehension only.** Do not assign vulnerability classes, do not rank risk, and do
not judge whether a check can be bypassed. Record what the code *does* and what it
*assumes*. The security lens is applied by `locate-sinks` once a vuln class is
confirmed — forming verdicts here is premature, because the class is not chosen until
step 2.

**Bound the stage by reachability.** Record only what external input can plausibly
reach, and stop there. Reachability is a factual property of the code, not a security
verdict, and it is what keeps this step from becoming an unbounded read of the whole
codebase.

**Assume nothing about the target's language, framework, or ecosystem.** Describe
operations by what they *do* — "issues an outbound network request", "constructs a query
from concatenated input", "starts a subprocess", "renders a template" — never by a
concrete API name. Paths and extensions in the schema are illustrative placeholders;
infer the target's real conventions from the target itself.

This step writes `surface-map.json` under the output root (see the offsec-hunter
artifacts guide). It has no input artifact — it is the first step. The map is
target-level and class-agnostic, so every vuln-class hunt against this commit reuses it.

## Procedure

1. Get the current commit: `git rev-parse HEAD`.
2. If `surface-map.json` exists and its `commit` equals `HEAD` → the map is **fresh**: load
   it and stop (downstream steps reuse it).
3. Otherwise build/refresh the map. Identify:
   - **Entry points** — HTTP routes, WebSocket handlers, RPC handlers, message consumers,
     scheduled jobs, parsed input files, CLIs, IPC/sockets, local services. Assign stable
     `ep-N` ids.
   - **Trust boundaries** — unauth ↔ session ↔ m2m; browser ↔ server; service ↔ service.
     Describe **how each gate works** and where it is enforced. Assign stable `tb-N` ids.
     Do not speculate about whether it can be bypassed.
   - **Input flows** — from an entry point: where external input travels, how it is
     transformed en route, and what validation is applied. Record where the flow ends as
     a `file:LINE` plus a factual one-line description of the operation there (e.g.
     "issues an outbound HTTP request with the supplied URL", "builds a SQL string by
     concatenation", "spawns a process"). Describe the operation; do not classify it.
   - **Assumptions** — preconditions and invariants the code relies on but does not
     itself enforce (e.g. "assumes `url` was already validated by its caller", "trusts
     the length field in the parsed header"). Assign stable `asm-N` ids; `locate-sinks`
     consumes them when deriving sinks.
4. Write `surface-map.json` per the schema in `references/surface-map.md`, stamped with
   `commit` = current `HEAD`. Record the step as done in `state.json`.

Prioritize what is **reachable from crafted input** over reading everything.
```

- [ ] **Step 4: Rewrite the schema in `skills/map-attack-surface/references/surface-map.md`**

Replace the `## Schema` section's JSON block with:

```json
{
  "commit": "<git HEAD the map was built from>",
  "target": "<repo name or path>",
  "entry_points": [
    {
      "id": "ep-1",
      "kind": "http | websocket | rpc | consumer | job | cli | file-input | ipc | local-service",
      "route": "POST /api/fetch",
      "auth": "unauth | session | m2m | local-user | input-supplier",
      "handler": "path/to/handler.ext:LINE"
    }
  ],
  "trust_boundaries": [
    {
      "id": "tb-1",
      "from": "unauth",
      "to": "session",
      "enforced_at": "path/to/middleware.ext:LINE",
      "notes": "how the gate works"
    }
  ],
  "flows": [
    {
      "from_entry": "ep-1",
      "input_path": "request body field 'url' -> validation helper -> outbound HTTP client call",
      "reaches": "path/to/file.ext:LINE",
      "operation": "issues an outbound network request to a caller-supplied address",
      "validation": ["compares the host against a configured allowlist at path/to/file.ext:LINE"],
      "reachable_from": "unauth | session | m2m | local-user | input-supplier"
    }
  ],
  "assumptions": [
    {
      "id": "asm-1",
      "at": "path/to/file.ext:LINE",
      "assumes": "the address argument was already validated by the caller",
      "enforced_here": false
    }
  ]
}
```

Then replace the `## Guidance` section with:

```markdown
## Guidance

- Keep it a **reachability index**, not a full code dump. A flow exists only if external
  input can plausibly reach its endpoint. This is the bound on the stage.
- **Comprehension only.** No vuln classes, no risk ranking, no bypass speculation. Record
  `operation` factually ("constructs a query from concatenated input"), not as a verdict.
- **Language- and ecosystem-agnostic.** Describe an operation by what it does, never by a
  concrete API name — "starts a subprocess", not `subprocess.run()`. Every path and
  extension above (`path/to/file.ext:LINE`) is an illustrative placeholder; infer the
  target's real conventions from the target.
- `validation` records **what the code checks**, not whether the check holds. Whether it
  holds is `break-hypotheses`'s job.
- `flows` and `assumptions` are what `locate-sinks` fans out over to derive `sink-N` ids
  once a vuln class is confirmed.
- The map is **class-agnostic and target-level**, so every vuln-class hunt against this
  commit reuses it.
- Non-web targets are first-class: an `entry_point` may be a parsed input file
  (`file-input`), a CLI, an IPC/socket, or a local service. Record these the same
  way — the `scope-target` checkpoint reasons over whatever the map shows.
```

- [ ] **Step 5: Run the tests**

```bash
bash tests/run-skill-tests.sh
```

Expected: all step1 and surface-map assertions PASS. The "sinks schema includes origin field" assertion still FAILS (Task 2 creates that file). No other failures.

- [ ] **Step 6: Commit**

```bash
git add skills/map-attack-surface tests/test-static-contracts.sh && git commit -m "refactor(map): make step 1 comprehension-only"
```

---

### Task 2: Add the `locate-sinks` step

**Files:**
- Create: `skills/locate-sinks/SKILL.md`
- Create: `skills/locate-sinks/references/sinks.md`
- Test: `tests/test-static-contracts.sh` (new block; extend the loops at lines 83 and 174)

**Interfaces:**
- Consumes: `surface-map.json` (`flows[]`, `assumptions[]`), `hunts/<VULN>/target.md` (confirmed vuln class + threat model).
- Produces: `hunts/<VULN>/sinks.json` — `{vuln, input_hash, sinks: [{id: "sink-N", origin, class, location, summary, from_flows, from_assumptions}]}`. `sink-N` ids are globally unique and are what `hypotheses.jsonl`, `survivors.jsonl`, and `findings.json` reference.

- [ ] **Step 1: Write the failing assertions**

Append to `tests/test-static-contracts.sh`, immediately before the final `summary` line:

```bash
# --- locate-sinks (2026-08-06) ---
L="skills/locate-sinks/SKILL.md"
assert_file_contains "$L" '^name: locate-sinks' "step3 frontmatter name"
assert_file_contains "$L" 'surface-map\.json' "step3 reads surface-map.json"
assert_file_contains "$L" 'target\.md' "step3 reads target.md"
assert_file_contains "$L" 'scope-target first' "step3 actionable missing-input error"
assert_file_contains "$L" 'sinks\.json' "step3 writes sinks.json"
assert_file_contains "$L" 'sink-[0-9]|stable id' "step3 assigns stable sink ids"
assert_file_contains "$L" '[Dd]ependenc' "step3 conditionally indexes vendored dependencies"
assert_file_contains "$L" 'skip this|no.*dependency sinks' "step3 dependency indexing is conditional"
assert_file_contains "$L" 'sinks\.md' "step3 references its schema"
assert_file_contains "$L" 'every language|ecosystem' "step3 is language-agnostic"
assert_file_exists "skills/locate-sinks/references/sinks.md" "sinks schema exists"
```

In the same file, add `locate-sinks` to the leak-check loop at line 83:

```bash
for d in map-attack-surface scope-target locate-sinks raise-hypotheses break-hypotheses prove-exploit; do
```

and to the description/guard loop at line 174:

```bash
for V in "$M" "$S" "$L" "$R" "$B" "$P"; do
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
bash tests/run-skill-tests.sh
```

Expected: FAIL on every `locate-sinks` assertion (the directory does not exist yet).

- [ ] **Step 3: Create `skills/locate-sinks/SKILL.md`**

```markdown
---
name: locate-sinks
description: Step 3 of offsec-hunter. Turn the class-agnostic map plus the confirmed threat model into the hunt's task queue — the sinks worth attacking for this vuln class, each with a stable id. This is where security judgment begins. Use when a vuln class and threat model are confirmed and the hunt needs its sink list.
---

# locate-sinks — step 3

**Guard:** If `state.json` is absent, stop with "run the `offsec-hunter` orchestrator first".

This is where **security judgment begins**. Steps 1–2 describe how the target works and
what we are hunting for; this step decides **what is worth attacking** for the confirmed
vuln class, and gives each one a stable id the rest of the hunt traces back to.

Writes `hunts/<VULN>/sinks.json` under the output root.

## Gate

Read `surface-map.json` (target-level) and `hunts/<VULN>/target.md`. If `target.md` is
missing or stale, stop: **"no fresh `target.md` — run scope-target first."**

## Procedure

1. Read the confirmed **vuln class** and **threat model** (attacker position, delivery
   vector, win condition, scope notes) from `target.md`. Everything below is scoped to
   them — a sink that cannot serve the confirmed win condition is not a sink for this
   hunt.
2. Derive candidate sinks from the map:
   - From `flows[]` — each flow's `reaches` location and its `operation`. Classify the
     operation against the confirmed vuln class by **what it does**, not by which API it
     calls: outbound network request → `ssrf`, command or dynamic-code execution → `rce`,
     query construction from concatenated input → `sqli`, template rendering → `ssti`,
     plus deserialization, authz checks, and untrusted parsing. These behaviours exist in
     every language; do not pattern-match on one ecosystem's function names.
   - From `assumptions[]` — an assumption the code relies on but does not enforce is a
     sink when violating it serves the win condition. Record the `asm-N` it came from.
3. Search the target for sinks of the confirmed class that the map's flows did not
   reach. The map is bounded by reachability; this step may widen within the class.
   Record these too — `break-hypotheses` decides whether they are actually reachable.
4. **Dependency sinks (conditional)** — **if** the target vendors its dependencies,
   index high-risk code in them as sinks too, marked `"origin": "dependency"`. Reaching
   the win condition may require chaining a target bug with a dependency bug. The rule is
   "the target ships third-party source in-tree", whatever that looks like in its
   ecosystem — `third_party/`, `vendor/`, `node_modules/`, `deps/`, or a lockfile-declared
   tree are **examples of the pattern, not an exhaustive list**. If no vendored deps are
   present, skip this — emit no dependency sinks and no error.
5. Assign each sink a **stable id** (`sink-1`, `sink-2`, …), globally unique across the
   hunt, so `hypotheses.jsonl`, `survivors.jsonl`, and `findings.json` can reference it.
   Ids are assigned here, never by a subagent.
6. Write `hunts/<VULN>/sinks.json` per the schema in `references/sinks.md`. Record the
   step done in `state.json` with the `input_hash` of `surface-map.json` + `target.md`.

This step runs **once per hunt**, not once per round — it re-runs only when `target.md`
changes (a steer that redirects the class or threat model).
```

- [ ] **Step 4: Create `skills/locate-sinks/references/sinks.md`**

```markdown
# sinks.json — schema

Per-hunt, class-scoped. Written by `locate-sinks` to `hunts/<VULN>/sinks.json`. This is
the hunt's task queue: `raise-hypotheses` fans out over it, one subagent per sink.

## Schema

```json
{
  "vuln": "SSRF",
  "input_hash": "<sha256 of surface-map.json + target.md>",
  "sinks": [
    {
      "id": "sink-1",
      "origin": "target | dependency",
      "class": "ssrf | rce | sqli | ssti | deserialization | authz | parsing",
      "location": "path/to/file.ext:LINE",
      "summary": "issues an outbound network request to a caller-supplied address",
      "from_flows": ["ep-1"],
      "from_assumptions": ["asm-2"]
    }
  ]
}
```

## Rules

- `id` is globally unique across the hunt and is assigned **only here**. Subagents never
  invent sink ids.
- `origin` marks vendored dependency code (`dependency`) versus the target's own code
  (`target`). `break-hypotheses` uses it when chaining a target bug with a dependency bug.
- `from_flows` / `from_assumptions` trace a sink back to the map entries that produced
  it. A sink found by direct search in step 3 of the procedure may have both empty.
- `class` is scoped to the hunt's confirmed vuln class. A sink that cannot serve the
  confirmed win condition does not belong here.
- `summary` describes **what the code does**, not which API it calls — "starts a
  subprocess with caller-influenced arguments", not a concrete function name. The classes
  above are behavioural and exist in every language; paths and extensions are
  illustrative placeholders.
```

- [ ] **Step 5: Run the tests**

```bash
bash tests/run-skill-tests.sh
```

Expected: all `locate-sinks` assertions PASS, including "sinks schema includes origin field" from Task 1.

- [ ] **Step 6: Commit**

```bash
git add skills/locate-sinks tests/test-static-contracts.sh && git commit -m "feat(locate-sinks): add step 3 owning sink identification"
```

---

### Task 3: Rewire the downstream gates

**Files:**
- Modify: `skills/raise-hypotheses/SKILL.md` (frontmatter step number, Gate section, context injection)
- Modify: `skills/break-hypotheses/SKILL.md` (frontmatter step number, dependency reference, context injection)
- Modify: `skills/prove-exploit/SKILL.md` (frontmatter step number)
- Modify: `skills/scope-target/SKILL.md` (no step-number change; step 2 is unchanged)
- Test: `tests/test-static-contracts.sh:57`

**Interfaces:**
- Consumes: `hunts/<VULN>/sinks.json` from Task 2.
- Produces: unchanged `hypotheses.jsonl` / `survivors.jsonl` line schemas — the `"sink"` field still holds a `sink-N` id.

- [ ] **Step 1: Change the failing assertion**

In `tests/test-static-contracts.sh`, replace line 57:

```bash
assert_file_contains "$R" 'scope-target first' "step3 actionable missing-input error"
```

with:

```bash
assert_file_contains "$R" 'locate-sinks first' "step4 actionable missing-input error"
assert_file_contains "$R" 'sinks\.json' "step4 reads sinks.json"
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
bash tests/run-skill-tests.sh
```

Expected: FAIL on "step4 actionable missing-input error" and "step4 reads sinks.json".

- [ ] **Step 3: Edit `skills/raise-hypotheses/SKILL.md`**

Change the heading `# raise-hypotheses — step 3` to `# raise-hypotheses — step 4`, and in the frontmatter change `Step 3 of offsec-hunter.` to `Step 4 of offsec-hunter.`.

Replace the `## Gate` section:

```markdown
## Gate

Read `hunts/<VULN>/sinks.json` and `hunts/<VULN>/target.md`. If `sinks.json` is missing
or stale, stop: **"no fresh `sinks.json` — run locate-sinks first."**
```

In the `## Procedure` section, change "a mapped sink" to "a sink from `sinks.json`", and in the context-injection paragraph replace the artifact list `(`surface-map.json`, `hunts/<VULN>/target.md`)` with ``(`hunts/<VULN>/sinks.json`, `hunts/<VULN>/target.md`)``.

Change the final line from `Record the step done in `state.json` with the `input_hash` of `target.md`.` to `Record the step done in `state.json` with the `input_hash` of `sinks.json`.`

- [ ] **Step 4: Edit `skills/break-hypotheses/SKILL.md`**

Change the heading `# break-hypotheses — step 4` to `# break-hypotheses — step 5`, and in the frontmatter change `Step 4 of offsec-hunter.` to `Step 5 of offsec-hunter.`.

In the chainability bullet, replace `(when dependency sinks exist — sinks with `origin: dependency`, see map-attack-surface)` with `(when dependency sinks exist — sinks with `origin: dependency`, see locate-sinks)`.

In the context-injection paragraph, replace the artifact list ``(`surface-map.json`, `target.md`, `hypotheses.jsonl`)`` with ``(`sinks.json`, `target.md`, `hypotheses.jsonl`)``.

- [ ] **Step 5: Edit `skills/prove-exploit/SKILL.md`**

Change the heading `# prove-exploit — step 5` to `# prove-exploit — step 6`, and in the frontmatter change `Step 5 of offsec-hunter.` to `Step 6 of offsec-hunter.`.

- [ ] **Step 6: Run the tests**

```bash
bash tests/run-skill-tests.sh
```

Expected: all PASS except the orchestrator/artifacts assertions handled in Tasks 4-5.

- [ ] **Step 7: Commit**

```bash
git add skills tests/test-static-contracts.sh && git commit -m "refactor(steps): gate raise-hypotheses on sinks.json, renumber steps 4-6"
```

---

### Task 4: Update the artifacts reference

**Files:**
- Modify: `skills/offsec-hunter/references/artifacts.md` (tree, `state.json` example, gating, ids section)
- Test: `tests/test-static-contracts.sh` (new assertions in the Task-1 artifacts block at lines 104-112)

**Interfaces:**
- Consumes: the `sinks.json` schema from Task 2.
- Produces: the canonical spec every other skill defers to for artifact layout and `state.json` shape.

- [ ] **Step 1: Write the failing assertions**

In `tests/test-static-contracts.sh`, append to the artifacts block (after line 112):

```bash
assert_file_contains "$A" 'sinks\.json' "artifacts documents sinks.json"
assert_file_contains "$A" 'locate-sinks' "artifacts documents the locate-sinks step"
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
bash tests/run-skill-tests.sh
```

Expected: FAIL on "artifacts documents sinks.json" and "artifacts documents the locate-sinks step".

- [ ] **Step 3: Update the tree in `skills/offsec-hunter/references/artifacts.md`**

In the `## Tree` code block, add `sinks.json` under `<VULN>/`, immediately after `target.md`:

```
  hunts/
    <VULN>/                   # per-hunt namespace (e.g. SSRF, RCE)
      target.md
      sinks.json
      hypotheses.jsonl
```

- [ ] **Step 4: Update the `state.json` example**

In the `"steps"` object, insert a `locate-sinks` entry between `scope-target` and `raise-hypotheses`:

```json
    "locate-sinks":       {"status": "done", "artifact": "hunts/RCE/sinks.json", "input_hash": "<sha256>", "at": "<iso8601>"},
```

- [ ] **Step 5: Update the gating and ids sections**

In `## Gating & staleness`, after the `surface-map.json` freshness bullet, add:

```markdown
- `surface-map.json` is **class-agnostic** — it carries no vuln classes and no sinks, so
  every vuln-class hunt against the same commit reuses it. Class-scoped sinks live in
  `hunts/<VULN>/sinks.json`, which is stale when `target.md` changes.
```

In `## Stable ids & forward references`, replace the `surface-map.json` sink bullet:

```markdown
- `surface-map.json` (comprehension only): `entry_points[].id` = `"ep-1"`,
  `trust_boundaries[].id` = `"tb-1"`, `assumptions[].id` = `"asm-1"`. No sinks, no vuln
  classes.
- `sinks.json` sink: `"id": "sink-3"`, `"class"`, `"origin": "target | dependency"`
  (marking vendored vs target sinks), assigned by `locate-sinks`.
```

- [ ] **Step 6: Run the tests**

```bash
bash tests/run-skill-tests.sh
```

Expected: all artifacts assertions PASS.

- [ ] **Step 7: Commit**

```bash
git add skills/offsec-hunter/references/artifacts.md tests/test-static-contracts.sh && git commit -m "docs(artifacts): document sinks.json and the locate-sinks step"
```

---

### Task 5: Update the orchestrator

**Files:**
- Modify: `skills/offsec-hunter/SKILL.md` (step list, round loop redirect, steering table)
- Test: `tests/test-static-contracts.sh:14-30` block

**Interfaces:**
- Consumes: all step names and artifact paths defined in Tasks 1-4.
- Produces: the ordered step list every step skill's guard points back to.

- [ ] **Step 1: Write the failing assertion**

In `tests/test-static-contracts.sh`, after line 18 (`orchestrator names step 2`), add:

```bash
assert_file_contains "$O" 'locate-sinks' "orchestrator names step 3"
```

- [ ] **Step 2: Run the tests to verify it fails**

```bash
bash tests/run-skill-tests.sh
```

Expected: FAIL on "orchestrator names step 3".

- [ ] **Step 3: Update the step list in `skills/offsec-hunter/SKILL.md`**

Replace the numbered list (currently five items) with:

```markdown
1. `map-attack-surface` — comprehension → `surface-map.json`
2. `scope-target` — confirm the hunting goal → `hunts/<VULN>/target.md`
3. `locate-sinks` — the hunt's task queue → `hunts/<VULN>/sinks.json`
4. `raise-hypotheses` — cheap fan-out, recall → `hunts/<VULN>/hypotheses.jsonl`
5. `break-hypotheses` — strong adversarial validation → `hunts/<VULN>/survivors.jsonl`
6. `prove-exploit` — confirmed findings + working PoC → `hunts/<VULN>/findings.{md,json}` + `pocs/`

User-facing mental model: **understand → goal → hunt → exploit**.

Steps 1–2 are comprehension and scoping and carry no security verdicts. **Security
judgment begins at `locate-sinks`.**
```

- [ ] **Step 4: Update the round loop section**

Replace the opening sentence of `## Round loop (steps 3–4)` with a retitled heading and body:

```markdown
## Round loop (steps 4–5)

Steps 1 (map), 2 (scope) and 3 (locate) run once. Steps 4 (raise) and 5 (break) are the
body of a **round loop**. Step 6 (prove) runs once at loop exit. With a single productive
round this is exactly the old single-pass flow.
```

In the **Redirect** bullet, replace "point them at mapped sinks no family covers yet" with "point them at sinks in `sinks.json` no family covers yet".

- [ ] **Step 5: Update the steering table**

Replace the steering table with:

```markdown
| Dissatisfaction | Edit | Re-runs |
|---|---|---|
| Missed an entry point or flow | `surface-map.json` | 1 → 2–6 |
| Wrong goal / class / attacker position | `target.md` | 3–6 |
| Missed a sink | `sinks.json` | 4–6 |
| Add or restore a lead | `hypotheses.jsonl` | 5–6 |
| Wrongly killed a candidate | annotate the dropped candidate | 5–6 (that one) |
| PoC doesn't fire | the finding | 6 (that finding) |
```

Change "After step 5:" to "After step 6:" in the paragraph below the table, and in the `### run.md dashboard` section change both occurrences of "step-5 completion" / "step 5" to "step-6 completion" / "step 6".

- [ ] **Step 6: Run the tests**

```bash
bash tests/run-skill-tests.sh
```

Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add skills/offsec-hunter/SKILL.md tests/test-static-contracts.sh && git commit -m "refactor(orchestrator): insert locate-sinks as step 3"
```

---

### Task 6: Update docs, behavioral test, and version

**Files:**
- Modify: `README.md` ("How it works" list, skill count, repo layout, artifacts paragraph)
- Modify: `tests/test-behavioral-recall.sh:17-22`
- Modify: `.claude-plugin/plugin.json` (version)

**Interfaces:**
- Consumes: the final step names and ordering from Task 5.
- Produces: nothing downstream — this is the last task.

- [ ] **Step 1: Add the failing behavioral check**

In `tests/test-behavioral-recall.sh`, replace the step-name checks:

```bash
check "$out" 'map.?attack.?surface' "names step 1"
check "$out" 'scope.?target'        "names step 2"
check "$out" 'locate.?sinks'        "names step 3"
check "$out" 'raise.?hypotheses'    "names step 4"
check "$out" 'break.?hypotheses'    "names step 5"
check "$out" 'prove.?exploit'       "names step 6"
check "$out" 'artifact|gate|state\.json' "describes artifact-gating"
```

- [ ] **Step 2: Update `README.md`**

Replace "The plugin is made of six composable skills" with "The plugin is made of seven composable skills", and "runs five artifact-gated steps in order" with "runs six artifact-gated steps in order".

Replace the numbered "How it works" list with:

```markdown
1. **map-attack-surface** — build/refresh a reusable, commit-stamped model of how the
   target works: entry points, trust boundaries, input flows, and the assumptions the
   code makes. Comprehension only — no vuln classes, no risk verdicts.
2. **scope-target** — define the hunting goal: vuln class + confirmed threat model
   (attacker position, delivery vector, win condition). Interactive confirms with you;
   headless accepts and logs.
3. **locate-sinks** — turn the class-agnostic map plus the confirmed threat model into
   the hunt's task queue: the sinks worth attacking, each with a stable id. Security
   judgment starts here.
4. **raise-hypotheses** — many cheap subagents generate hypotheses (recall).
5. **break-hypotheses** — stronger subagents adversarially confirm reachability (precision).
6. **prove-exploit** — confirmed findings + a working PoC, as `findings.md` (human) and
   `findings.json` (machine), each PoC a minimal `pocs/finding-NNN.md` (one-line summary +
   the exact curl / request chain / WebSocket message in a fenced block), with an
   empty-results report when nothing is exploitable.
```

Change "Steps 3-4 run as an **autonomous round loop**" to "Steps 4-5 run as an **autonomous round loop**".

In the "Install" section, change "ships as six composable" to "ships as seven composable".

In the repo layout block, replace the skills listing with:

```
    ├── map-attack-surface/        # step 1  (references/surface-map.md)
    ├── scope-target/              # step 2
    ├── locate-sinks/              # step 3  (references/sinks.md)
    ├── raise-hypotheses/          # step 4
    ├── break-hypotheses/          # step 5
    └── prove-exploit/             # step 6
```

In the "Run-time artifacts" paragraph, change the key-files list to `target.md`, `sinks.json`, `hypotheses.jsonl`, `survivors.jsonl`, `findings.{md,json}`, `pocs/finding-NNN.md`, and `run.md`.

Add to the design-rationale paragraph at the end:

```markdown
the comprehension-first recon split is designed in
[`docs/superpowers/specs/2026-08-06-comprehension-first-recon-design.md`](docs/superpowers/specs/2026-08-06-comprehension-first-recon-design.md).
```

- [ ] **Step 3: Bump the version**

In `.claude-plugin/plugin.json`, change `"version": "1.1.0"` to `"version": "1.2.0"`.

- [ ] **Step 4: Run both test tiers**

```bash
bash tests/run-skill-tests.sh
```

Expected: all static contract assertions PASS.

```bash
cp -R skills/* ~/.claude/skills/ && CLAUDE_PROMPT_TIMEOUT=240 RUN_BEHAVIORAL=1 bash tests/run-skill-tests.sh
```

Expected: behavioral recall PASS, including "names step 3" for `locate-sinks`. The `cp -R` is required because a repo checkout is not on the skill path.

- [ ] **Step 5: Commit**

```bash
git add README.md tests/test-behavioral-recall.sh .claude-plugin/plugin.json && git commit -m "docs: document the comprehension-first recon split, bump to 1.2.0"
```

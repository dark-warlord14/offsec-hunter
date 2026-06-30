# Flexible Reachability (Threat-Model Checkpoint) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace offsec-hunter's hardcoded HTTP/WS-from-unauth threat model with a map-derived threat model the user confirms at a new Phase 0.5 checkpoint.

**Architecture:** Add one interactive gate (Phase 0.5) between Map and Fan-out that proposes a target-specific threat model (attacker position, delivery vector, impact/win condition, scope notes) inferred from `surface-map.json`, has the user confirm/edit it, and writes `.offsec-hunter/threat-model.md`. Phase 1 is gated on that file; Phases 1–2 reason against the confirmed model instead of the old hardcoded scope. The old scope becomes the default proposal.

**Tech Stack:** Markdown only — the skill (`SKILL.md`), its reference docs, the design spec, and the README. No code, no test framework. Verification per task = `grep`/read consistency checks.

## Global Constraints

- The skill body stays **platform-neutral action language** — no platform-specific tool names in `SKILL.md`. (verbatim from existing skill convention)
- Artifacts live in `.offsec-hunter/` at the target repo root; the directory is gitignored; never commit it. (verbatim)
- `json`/`jsonl` artifacts = machine-generated pipeline data; `md` artifacts = human-confirmed steering prose. The new `threat-model.md` is **markdown prose**. (from spec)
- Changes to enums in the map schema are **additive** — existing web values unchanged. (from spec)
- No new commands, no new vuln classes, no change to the upfront vuln-class entry gate, no change to Phase 0 freshness/reuse, no change to budget orchestration. (from spec)
- The Phase 0.5 checkpoint **always stops and asks** — even when the proposal equals the web default. (from spec)
- Never commit to `master`; work stays on `feat/flexible-reachability`. (user instruction)

---

### Task 1: Broaden the attack-surface map schema (non-web positions/vectors)

**Files:**
- Modify: `skills/offsec-hunter/references/surface-map.md`

**Interfaces:**
- Produces: the broadened enum vocabulary (`cli`, `file-input`, `ipc`, `local-service`; `local-user`, `input-supplier`) that Phase 0.5 reads from the map and Task 2's checkpoint prose references.

- [ ] **Step 1: Broaden the `entry_points.kind` enum in the JSON schema block**

In the `entry_points` object, change the `kind` line:

```
      "kind": "http | websocket | rpc | consumer | job",
```

to:

```
      "kind": "http | websocket | rpc | consumer | job | cli | file-input | ipc | local-service",
```

- [ ] **Step 2: Broaden the `auth` enum in `entry_points`**

Change:

```
      "auth": "unauth | session | m2m",
```

to:

```
      "auth": "unauth | session | m2m | local-user | input-supplier",
```

- [ ] **Step 3: Broaden `reachable_from` in the `flows` object**

In the `flows` example, change:

```
      "reachable_from": "unauth"
```

to:

```
      "reachable_from": "unauth | session | m2m | local-user | input-supplier"
```

- [ ] **Step 4: Add a one-line note under "## Guidance" explaining non-web targets**

Append this bullet to the existing `## Guidance` list:

```
- Non-web targets are first-class: an `entry_point` may be a parsed input file
  (`file-input`), a CLI, an IPC/socket, or a local service. Record these the same
  way — the Phase 0.5 threat-model checkpoint reasons over whatever the map shows.
```

- [ ] **Step 5: Verify the edits**

Run: `grep -n "file-input\|local-user\|input-supplier\|local-service" skills/offsec-hunter/references/surface-map.md`
Expected: matches on the `kind`, `auth`, `reachable_from`, and Guidance lines (≥4 lines).

- [ ] **Step 6: Commit**

```bash
git add skills/offsec-hunter/references/surface-map.md
git commit -m "feat(map): broaden surface-map schema with non-web entry kinds and attacker positions"
```

---

### Task 2: Add Phase 0.5 and reframe scope/Phases 1–2 in SKILL.md

**Files:**
- Modify: `skills/offsec-hunter/SKILL.md`

**Interfaces:**
- Consumes: the broadened map vocabulary from Task 1.
- Produces: the `threat-model.md` artifact contract (four dimensions: attacker position, delivery vector, impact/win condition, scope notes) that Phases 1–2 read.

- [ ] **Step 1: Rewrite the "## Scope (the threat model)" section as the default proposal**

Replace the entire current `## Scope (the threat model)` section (the intro line plus its four bullets) with:

```markdown
## Scope — the default threat model (a proposal, not a fixed rule)

This is the **default** the Phase 0.5 checkpoint starts from. It is confirmed or
overridden per target there — never assume it silently.

- Default attacker position: **unauthenticated or normal-user**.
- Default delivery vector: an external request — **HTTP, a chain of HTTP
  requests, or a WebSocket message**.
- Default impact: high-impact classes (RCE / SSRF / SQLi / SSTI / auth-bypass /
  IDOR / …).

These defaults hold regardless of target and are **not** softened at the
checkpoint:

- **m2m-auth-gated** calls are **out of scope** — UNLESS an auth bypass lets an
  outsider reach them. That bypass is itself the finding.
- Do **not** lean on memory artifacts or other projects' data. Assume nothing
  about this target. Build the model from, and validate against, this target's
  actual current code.
```

- [ ] **Step 2: Add the Phase 0.5 row to the artifacts table**

In the `## How this skill runs` → Artifacts table, insert a row between the Phase 0 and Phase 1 rows so the table reads:

```markdown
| Phase | Produces | Next phase reads |
|-------|----------|------------------|
| 0 Map | `.offsec-hunter/surface-map.json` | itself (freshness) + Phase 0.5 |
| 0.5 Threat-model | `.offsec-hunter/threat-model.md` | Phase 1 |
| 1 Fan-out | `.offsec-hunter/hypotheses.jsonl` | Phase 2 |
| 2 Validate | `.offsec-hunter/survivors.jsonl` | Phase 3 |
| 3 Synthesis | `.offsec-hunter/findings.md` + PoCs | — |
```

- [ ] **Step 3: Update Phase 0's exit pointer**

At the end of `## Phase 0 — Map the attack surface`, the fresh-map shortcut currently says "skip to Phase 1". Change both the table-fresh case and step 2's wording so a fresh map proceeds to **Phase 0.5**, not Phase 1. In step 2 replace:

```
   **fresh; load it and skip to Phase 1.**
```

with:

```
   **fresh; load it and proceed to Phase 0.5.**
```

- [ ] **Step 4: Insert the new "## Phase 0.5 — Threat-model checkpoint" section**

Add this section immediately after Phase 0 and before `## Phase 1`:

```markdown
## Phase 0.5 — Threat-model checkpoint (interactive gate)

Read `surface-map.json`. The map now tells you what an exploit plausibly looks
like for **this** target — use it instead of assuming the web default.

1. **Propose a threat model** inferred from the map, across four dimensions:
   - **Attacker position** — where the attacker sits (e.g. `remote-unauth`,
     `remote-normal-user`, `local-user`, `input-file-supplier`,
     `adjacent-service`).
   - **Delivery vector** — how attacker input reaches the target (e.g. HTTP
     request/chain, WebSocket message, CLI args, a parsed input file/format,
     IPC/socket, environment).
   - **Impact / win condition** — what counts as a successful exploit here.
     Includes RCE/SSRF/data-exfil/auth-bypass **and** non-web wins: DoS /
     "render the target incapable", memory-safety crash.
   - **In/out-of-scope notes** — boundaries explicitly excluded (e.g. m2m-only
     paths unless an auth bypass reaches them) and target-specific assumptions.

   Start from the default Scope above; where the map shows a non-web target,
   propose the fitting model instead.

2. **Always stop and ask the user to confirm or edit the proposal** — even when
   it equals the web default. Do not auto-proceed. This is the nudge.

3. Write the confirmed model to `.offsec-hunter/threat-model.md` as prose, with
   the four dimensions as headings. This is human-confirmed steering (like the
   final report), not machine pipeline data — keep it markdown, not JSON.
```

- [ ] **Step 5: Reframe Phase 1 to read the confirmed model**

In `## Phase 1 — Cheap fan-out`, change the opening so it reads the threat model. Replace:

```
Read `surface-map.json`. Dispatch **many shallow subagents on a cheap/fast model**, each
chasing **one** hypothesis tied to the target vuln class and a mapped sink
(e.g. "does any handler fetch a user-supplied URL without an allowlist?").
```

with:

```
Read `surface-map.json` **and** `threat-model.md`. Dispatch **many shallow
subagents on a cheap/fast model**, each chasing **one** hypothesis tied to the
target vuln class, a mapped sink, and the **confirmed delivery vector + attacker
position** (e.g. "does any handler fetch a user-supplied URL without an
allowlist?", or "does the file parser trust a length field from the input
file?").
```

- [ ] **Step 6: Reframe Phase 2's reachability question against the confirmed model**

In `## Phase 2 — Deep validation`, change the third bullet. Replace:

```
- Is it reachable **unauth or via a single normal-user session** (per scope)?
```

with:

```
- Is it reachable **per the confirmed threat model** (the attacker position and
  delivery vector in `threat-model.md`)?
- Does the result meet the **confirmed win condition** (so a DoS or
  memory-safety crash counts when the user scoped it in)?
```

- [ ] **Step 7: Verify SKILL.md edits are consistent**

Run: `grep -n "Phase 0.5\|threat-model.md\|default threat model\|win condition\|confirmed threat model" skills/offsec-hunter/SKILL.md`
Expected: Phase 0.5 appears in the artifact table, the Phase 0 pointer, the new section heading, and Phases 1–2; `threat-model.md` appears in the table + Phase 0.5 + Phases 1–2.

Run: `grep -n "skip to Phase 1" skills/offsec-hunter/SKILL.md`
Expected: no matches (the fresh-map pointer now targets Phase 0.5).

- [ ] **Step 8: Commit**

```bash
git add skills/offsec-hunter/SKILL.md
git commit -m "feat(skill): add Phase 0.5 threat-model checkpoint; reframe scope and phases 1-2 against confirmed model"
```

---

### Task 3: Update the original design spec to reflect Phase 0.5

**Files:**
- Modify: `docs/superpowers/specs/2026-06-26-offsec-hunter-design.md`

**Interfaces:**
- Consumes: the Phase 0.5 contract from Task 2. Documentation only.

- [ ] **Step 1: Demote the "### Scope rules" block to a default**

In `### Scope rules`, change the first bullet. Replace:

```
- Trigger MUST be an external request: HTTP, a chain of HTTP requests, or a
  WebSocket message, from an **unauth or normal-user session**.
```

with:

```
- **Default** trigger (confirmed/overridden at the Phase 0.5 checkpoint): an
  external request — HTTP, a chain of HTTP requests, or a WebSocket message,
  from an **unauth or normal-user session**. Non-web targets (input-file →
  memory-safety, local service → DoS) are scoped in at the checkpoint.
```

- [ ] **Step 2: Add the Phase 0.5 bullet to the "### Phases" list**

Insert between the `**Phase 0 — Map.**` bullet and the `**Phase 1 — Cheap fan-out.**` bullet:

```
- **Phase 0.5 — Threat-model checkpoint.** Propose a target-specific threat
  model (attacker position, delivery vector, impact/win condition, scope notes)
  inferred from the map; the user always confirms or edits it; write
  `.offsec-hunter/threat-model.md`. Phase 1 is gated on this file. See
  `docs/superpowers/specs/2026-06-30-flexible-reachability-design.md`.
```

- [ ] **Step 3: Verify**

Run: `grep -n "Phase 0.5\|threat-model.md\|Default. trigger\|Default\*\* trigger" docs/superpowers/specs/2026-06-26-offsec-hunter-design.md`
Expected: matches for the new Phase 0.5 bullet and the demoted-default trigger line.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-06-26-offsec-hunter-design.md
git commit -m "docs(spec): record Phase 0.5 threat-model checkpoint in original design"
```

---

### Task 4: Update the README pipeline description

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: the Phase 0.5 contract. Documentation only.

- [ ] **Step 1: Add Phase 0.5 to the "## How it works" numbered list**

In `## How it works`, insert between item `0. **Map**` and item `1. **Fan-out**`:

```
0.5. **Threat-model checkpoint** — propose a target-specific threat model
   (attacker position, delivery vector, win condition) from the map; you confirm
   or edit it before the hunt proceeds. Lets non-web targets (untrusted input
   file → memory-safety bug, local service → DoS) be scoped in, not just web
   requests.
```

- [ ] **Step 2: Verify**

Run: `grep -n "Threat-model checkpoint\|threat model" README.md`
Expected: one match in the How-it-works list.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs(readme): document Phase 0.5 threat-model checkpoint in pipeline overview"
```

---

## Self-Review

**Spec coverage:**
- Phase 0.5 interactive gate → Task 2 Step 4. ✓
- Always-stops-and-asks → Task 2 Step 4 (Step 2 of the section) + Global Constraints. ✓
- Four dimensions → Task 2 Step 4. ✓
- `threat-model.md` markdown artifact + gating → Task 2 Steps 2 & 4; Phase 1 reads it in Step 5. ✓
- Scope demoted to default proposal → Task 2 Step 1; spec Task 3 Step 1. ✓
- Phase 1/2 reference confirmed model → Task 2 Steps 5–6. ✓
- surface-map enums broadened (additive) → Task 1. ✓
- Spec + README docs → Tasks 3 & 4. ✓
- `.gitignore` unchanged (whole dir already ignored) → no task, by design. ✓

**Placeholder scan:** No TBD/TODO; every edit step shows the exact before/after prose. ✓

**Type consistency:** Artifact filename `threat-model.md` and the four dimension names (attacker position, delivery vector, impact/win condition, in/out-of-scope notes) are used identically across Tasks 2–4 and the spec. ✓

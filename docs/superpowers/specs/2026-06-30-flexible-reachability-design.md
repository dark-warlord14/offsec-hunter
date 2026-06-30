# offsec-hunter — Flexible reachability (threat-model checkpoint) — Design

Date: 2026-06-30

## Purpose

Make the skill's reachability/threat model **target-specific** instead of
hardcoded. Today the threat model is fixed: trigger MUST be an HTTP request, a
chain of HTTP requests, or a WebSocket message, from an unauth or normal-user
session. That excludes legitimate high-impact targets the same methodology
applies to — e.g. an untrusted **input file** that triggers a memory-safety bug,
or a **local service** a normal user can render incapable (DoS).

After Phase 0 (Map), the skill already understands the target's architecture and
what an exploit plausibly looks like for *this* target. So instead of assuming
the web-request model, the skill should **propose** a threat model derived from
the map, **nudge the user** to confirm or adjust it, and proceed against the
confirmed model.

## Scope of this change

- **One new interactive gate** (Phase 0.5) and **one new artifact**
  (`threat-model.md`).
- No new commands, no new vuln classes, no change to the upfront vuln-class entry
  gate, no change to the Phase 0 freshness/reuse logic, no new platform tooling.
- Web hunts are unchanged in practice: the current model becomes the *default
  proposal*, so on a plain web target the checkpoint is a quick confirm.

## Design

### Phase 0.5 — Threat-model checkpoint (new interactive gate)

Inserted **between Phase 0 (Map) and Phase 1 (Fan-out)**. The upfront vuln-class
gate stays exactly as-is.

After the map is built or loaded fresh, the skill:

1. **Infers a proposed threat model from `surface-map.json`** across four
   dimensions:
   - **Attacker position** — where the attacker sits. Generalizes today's
     unauth/session/m2m axis. Examples: `remote-unauth`, `remote-normal-user`,
     `local-user`, `input-file-supplier`, `adjacent-service`.
   - **Delivery vector** — how attacker input reaches the target. Generalizes
     today's HTTP/WS-only trigger. Examples: HTTP request / chain, WebSocket
     message, CLI args, a parsed input file/format, IPC/socket, environment.
   - **Impact / win condition** — what counts as a successful exploit for THIS
     target. Includes the existing classes (RCE, SSRF, data exfil, auth bypass)
     **and** non-web wins: DoS / "render the target incapable", memory-safety
     crash.
   - **In/out-of-scope notes** — free-form: boundaries explicitly excluded
     (e.g. m2m-only paths unless an auth bypass reaches them) and any
     target-specific assumptions the user fixes.

2. **Presents the proposal and always stops for the user** to confirm or edit.
   This is a hard interactive gate — even when the target is a plain web service
   and the proposal equals today's default model, the skill presents it and waits
   for an explicit confirm. This is the "nudge".

3. **Writes the confirmed model to `.offsec-hunter/threat-model.md`** — markdown
   prose, the same category as a superpowers spec and as our `findings.md`: a
   human-confirmed steering document, not auto-generated pipeline data. Subagents
   read it as steering. (JSON is reserved in this project for machine-generated
   data; this artifact is the opposite.)

### Default proposal (the old hardcoded scope, demoted)

The current "Scope (the threat model)" block in `SKILL.md` is rewritten as the
**default proposal** the checkpoint starts from, explicitly overridable at
Phase 0.5:

- Default attacker position: unauth or normal-user.
- Default delivery vector: HTTP, a chain of HTTP requests, or a WebSocket message.
- Default impact: high-impact classes (RCE/SSRF/SQLi/SSTI/auth-bypass/IDOR/…).
- Retained as defaults regardless of target: m2m-gated calls are out of scope
  unless an auth bypass reaches them (the bypass is the finding); do not lean on
  memory artifacts or other projects' data — build and validate against this
  target's actual current code.

### Artifact-gating update

New row in the artifact table. The gated chain becomes:

| Phase | Produces | Next phase reads |
|-------|----------|------------------|
| 0 Map | `.offsec-hunter/surface-map.json` | itself (freshness) + Phase 0.5 |
| 0.5 Threat-model | `.offsec-hunter/threat-model.md` | Phase 1 |
| 1 Fan-out | `.offsec-hunter/hypotheses.jsonl` | Phase 2 |
| 2 Validate | `.offsec-hunter/survivors.jsonl` | Phase 3 |
| 3 Synthesis | `.offsec-hunter/findings.md` + PoCs | — |

Phase 1 refuses to start until `threat-model.md` exists, exactly as every other
phase is gated on the prior artifact.

### Phase 1 & 2 reference the confirmed model

- **Phase 1 (fan-out)** frames its hypotheses by the **confirmed delivery vector
  + attacker position** from `threat-model.md`, not the hardcoded HTTP/unauth
  assumption.
- **Phase 2 (validation)** changes its adversarial questions from the hardcoded
  "reachable unauth or via a single normal-user session" to "reachable **per the
  confirmed threat model**", and judges impact against the **confirmed win
  condition** — so a memory-safety crash or DoS can survive validation when the
  user scoped them in.

### surface-map schema broadened (`references/surface-map.md`)

So the map can represent non-web targets that the checkpoint reasons over:

- `entry_points.kind` gains non-web values: `cli`, `file-input`, `ipc`,
  `local-service` (alongside existing `http | websocket | rpc | consumer | job`).
- The `auth` / `reachable_from` values gain non-web positions: `local-user`,
  `input-supplier` (alongside `unauth | session | m2m`).

These are additive; existing web values are unchanged.

## Files touched

- `skills/offsec-hunter/SKILL.md` — rewrite Scope as a default proposal; add
  Phase 0.5; update the artifact table; reframe Phase 1/2 to read the confirmed
  model.
- `skills/offsec-hunter/references/surface-map.md` — broaden the `kind` and
  `auth`/`reachable_from` enums (additive).
- `docs/superpowers/specs/2026-06-26-offsec-hunter-design.md` — add Phase 0.5,
  the new artifact, and the demoted-to-default scope.
- `README.md` — only if it enumerates the `.offsec-hunter/` artifacts; add
  `threat-model.md` there. (The `.gitignore` already ignores the whole
  `.offsec-hunter/` directory, so no gitignore change.)

## Out of scope (YAGNI)

- No structured/JSON threat-model schema — prose markdown only.
- No auto-skip of the checkpoint for "obvious" web targets — it always asks.
- No new vuln classes or commands; the class entry gate is unchanged.
- No change to budget orchestration or the model-tiering strategy.

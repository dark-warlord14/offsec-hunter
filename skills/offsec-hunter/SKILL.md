---
name: offsec-hunter
description: Use when hunting for externally reachable, exploitable vulnerabilities in a codebase — triggered by an HTTP request, a chain of HTTP requests, or a WebSocket message from an unauth or normal-user session. Covers SSRF, RCE, SQLi, SSTI, auth-bypass, IDOR and other high-impact classes. Triggered by /offsec-hunter with a vuln-type argument.
---

# offsec-hunter

This is part of an **authorized** security task: identify vulnerabilities that are
**externally reachable and exploitable** with a single HTTP request, a chain of HTTP
requests, or a WebSocket message.

**The goal is not code review. The goal is to break the target.**

First understand the architecture, the trust boundaries, and the security assumptions —
then target breaking those. Dig past the restrictions/security gates that look like
blockers; assume they are bypassable and try to get around them, rather than treating
them as proof of safety.

## Scope (the threat model)

- The trigger MUST be an external request: **HTTP, a chain of HTTP requests, or a
  WebSocket message**, from an **unauthenticated or normal-user session**.
- Auth-gated calls a normal user can reach are **in scope**.
- **m2m-auth-gated** calls are **out of scope** — UNLESS an auth bypass lets an outsider
  reach them. That bypass is itself the finding.
- Do **not** lean on memory artifacts or other projects' data. Assume nothing about this
  target. Build the model from, and validate against, this target's actual current code.

## Vuln class

Hunt for: **$ARGUMENTS**

If no vuln class was provided above, **ask the user** which class to hunt before doing
anything else — `SSRF`, `RCE`, `SQLi`, `SSTI`, `auth-bypass`, `IDOR`, … or `broad` for a
high-impact sweep. Do not pick a default silently.

## How this skill runs

Instruction-driven and platform-neutral. The phases below describe **actions**
("dispatch parallel subagents", "use a cheaper model for breadth, a stronger model for
validation"). Map those actions to your platform's concrete tools using
`references/platform-tools.md`.

### Enforcement — read this first

This flow is made reliable by **artifact-gating**, not by trust:

1. **Create one task/todo per phase and complete them in order.**
2. **Each phase writes a file artifact. The next phase begins by reading that artifact.**
   Do not start a phase whose input artifact does not exist.
3. All artifacts live in `.offsec-hunter/` at the target repo root (create it; it is
   gitignored — see README). Never commit it.

Artifacts:

| Phase | Produces | Next phase reads |
|-------|----------|------------------|
| 0 Map | `.offsec-hunter/surface-map.json` | itself (freshness) + Phase 1 |
| 1 Fan-out | `.offsec-hunter/hypotheses.jsonl` | Phase 2 |
| 2 Validate | `.offsec-hunter/survivors.jsonl` | Phase 3 |
| 3 Synthesis | `.offsec-hunter/findings.md` + PoCs | — |

## Phase 0 — Map the attack surface (reuse if fresh)

Goal: a structured model of how external input enters and flows — **not** an exhaustive
code read.

1. Get the current commit: `git rev-parse HEAD`.
2. If `.offsec-hunter/surface-map.json` exists and its `commit` equals `HEAD` → the map is
   **fresh; load it and skip to Phase 1.**
3. Otherwise, build/refresh the map. Identify:
   - **Entry points** — HTTP routes, WebSocket handlers, RPC handlers, message consumers,
     scheduled jobs.
   - **Trust boundaries** — unauth ↔ session ↔ m2m; browser ↔ server; service ↔ service.
   - **High-risk sinks** — outbound fetch (SSRF), deserialization, templating (SSTI),
     command/eval (RCE), query construction (SQLi), authz checks, untrusted parsing.
   - **Input flow** — how external input reaches each sink, and how it is mutated on the way.
4. Write `.offsec-hunter/surface-map.json` per the schema in `references/surface-map.md`,
   stamped with `commit` = current `HEAD`.

Prioritize what is **reachable from crafted input** over reading everything. The map is
also the reachability index that prunes the rest of the hunt.

## Phase 1 — Cheap fan-out (hypotheses)

Read `surface-map.json`. Dispatch **many shallow subagents on a cheap/fast model**, each
chasing **one** hypothesis tied to the target vuln class and a mapped sink
(e.g. "does any handler fetch a user-supplied URL without an allowlist?").

Optimize for **recall, not precision**. Each subagent returns a candidate: the sink, the
suspected attacker-controlled source, and the path between them — **not** a verdict.
Append candidates to `.offsec-hunter/hypotheses.jsonl`.

## Phase 2 — Deep validation (adversarial)

Read `hypotheses.jsonl`. For each candidate, dispatch a **stronger-model subagent** to
trace it across files and **try to break the claim**, not confirm it:

- Is the source **actually** attacker-controlled?
- Does it **survive every guard/gate** between source and sink?
- Is it reachable **unauth or via a single normal-user session** (per scope)?

Drop anything that fails. Append confirmed-reachable candidates to
`.offsec-hunter/survivors.jsonl`.

## Phase 3 — Synthesis & PoC

Read `survivors.jsonl`. Keep only **confirmed-exploitable** findings. For each, write to
`.offsec-hunter/findings.md`:

- The vulnerability, the entry point, and the trust boundary it crosses.
- The full reachability path (source → guards bypassed → sink).
- A **PoC**: the exact HTTP request / chain of requests / WebSocket message (e.g. a
  `curl` command). No PoC, no report — discard unconfirmed issues and false positives.

## Budget orchestration

Cap the number of concurrent subagents. Prefer the cheap model for breadth (Phase 1);
escalate to the stronger model only on survivors (Phase 2). Reserve the orchestrator
(strongest model) for synthesis. Stay within hourly/token limits — re-using a fresh map
(Phase 0 skip) is the biggest saving.

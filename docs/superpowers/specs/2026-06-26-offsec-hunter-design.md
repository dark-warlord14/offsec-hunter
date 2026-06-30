# offsec-hunter — Design

Date: 2026-06-26

## Purpose

A reusable, budget-aware, adversarial vulnerability-hunting skill that finds
**externally reachable, exploitable** vulnerabilities triggered by an HTTP
request, a chain of HTTP requests, or a WebSocket message — from an unauthenticated
or normal-user session. The goal is not code review; the goal is to break the target.

The vulnerability class is a parameter (`/offsec-hunter SSRF`, `RCE`, `SQLi`, …).
The method is general; the target class is swappable.

## Why this exists

Re-deriving the target's architecture, trust boundaries, and input flow on every
run wastes budget rebuilding the same model. Practitioner methodology and
production systems both converge on the same fix: **persist the expensive
recon artifact and reuse it; regenerate only the per-run hypotheses and
reasoning.** (Cloudflare's code-review system reuses a shared context file for an
85.7% cache-hit rate; vuln-research write-ups recommend persisting threat models
and trust-boundary maps while regenerating hypotheses per run.)

## Distribution model

One GitHub repo holding a single skill that runs on **both Claude Code and
Codex**. The `SKILL.md` is the shared open agent-skills standard — written once,
consumed by both, with no per-platform manifests. Not distributed via a
marketplace; installed by cloning the repo and symlinking the skill into each
tool's skills directory.

```
offsec-hunter/
├── README.md                       # install for both platforms
├── LICENSE
├── .gitignore
├── docs/superpowers/specs/2026-06-26-offsec-hunter-design.md
└── skills/offsec-hunter/
    ├── SKILL.md                     # the one portable skill
    └── references/
        ├── platform-tools.md        # Claude↔Codex action→tool mapping
        └── surface-map.md            # attack-surface map schema + freshness rule
```

The skill is the single source of truth for both platforms.

## Install

Clone once, then symlink the skill folder into each tool's skills directory
(`cp -R` works too):

**Claude Code** → `~/.claude/skills/offsec-hunter`
**Codex** → `~/.codex/skills/offsec-hunter`

```
git clone https://github.com/deriv-security/offsec-hunter.git
ln -s "$PWD/offsec-hunter/skills/offsec-hunter" ~/.claude/skills/offsec-hunter
ln -s "$PWD/offsec-hunter/skills/offsec-hunter" ~/.codex/skills/offsec-hunter
```

## The skill: behavior

Written in platform-neutral **action language** ("dispatch parallel subagents",
"use a cheaper/faster model for breadth, a stronger model for validation") — no
platform-specific tool names in the body. `references/platform-tools.md` maps
those actions to each platform's concrete tools. No dependency on any
platform-specific orchestration engine (e.g. Claude's Workflow), so it runs
identically on Claude and Codex.

### Enforcement: artifact-gating

A skill is steering, not a runtime engine. The flow is made deterministic by
**gating each phase on the prior phase's file artifact** plus a mandatory
checklist (one task per phase, completed in order). Skipping a phase is
structurally impossible because the next phase has nothing to read.

### Scope rules

- Trigger MUST be an external request: HTTP, a chain of HTTP requests, or a
  WebSocket message, from an **unauth or normal-user session**.
- Auth-gated calls reachable by a normal user are **in scope**.
- m2m-auth-gated calls are **out of scope** unless an auth bypass lets an
  outsider reach them — that bypass is itself the finding.
- Do not lean on memory artifacts or other projects' data. Assume nothing about
  this target; validate against its actual current code.

### Entry gate

If no vuln class is passed, **ask the user** which class to hunt
(SSRF / RCE / SQLi / SSTI / auth-bypass / IDOR / … or `broad` for a high-impact
sweep) before any recon. No silent default.

### Phases (each gated on the prior artifact)

- **Phase 0 — Map.** Build/refresh `.offsec-hunter/surface-map.json`: entry
  points → trust boundaries → high-risk sinks, stamped with the git commit it was
  built from. **Skip if a fresh map exists** (its commit == `HEAD`). The map
  doubles as a reachability index that prunes the hunt.
- **Phase 1 — Cheap fan-out.** Dispatch many shallow subagents on a cheap/fast
  model, each chasing one hypothesis ("does any handler fetch a user-supplied
  URL?"). They return candidate sink + input path, not verdicts. →
  `.offsec-hunter/hypotheses.jsonl`
- **Phase 2 — Deep validation.** Each candidate goes to a stronger-model
  subagent for adversarial cross-file tracing: is the source actually
  attacker-controlled, does it survive the guards, is it reachable unauth or via
  a single session? Try to break the candidate, not confirm it. →
  `.offsec-hunter/survivors.jsonl`
- **Phase 3 — Synthesis.** Keep only confirmed-exploitable findings; produce a
  PoC per finding (curl / request chain). → `.offsec-hunter/findings.md`

### Budget orchestration

Cap concurrent subagents; prefer the cheap model for breadth; escalate to the
stronger model only on survivors; stay within hourly limits.

## Map artifact

- Location: in the **target repo**, `.offsec-hunter/` (gitignored). Platform-neutral
  (not tied to `~/.claude/`), naturally keyed to the repo, keeps the target clean.
- Freshness: the map records the git commit it was built from; the hunt rebuilds
  on mismatch rather than trusting a stale map. Schema in
  `references/surface-map.md`.

## Out of scope (YAGNI)

- No code-property-graph tooling — prose+JSON map only.
- No separate `/map-target` command — mapping is an internal, auto-refreshed
  phase of the one skill.
- No plugin hooks / MCP servers in v1.

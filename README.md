# offsec-hunter

An adversarial, budget-aware vulnerability-hunting skill for **Claude Code** and
**Codex**. It hunts for **externally reachable, exploitable** vulnerabilities — SSRF,
RCE, SQLi, SSTI, auth-bypass, IDOR and other high-impact classes — triggered **by default** by an HTTP
request, a chain of HTTP requests, or a WebSocket message from an unauth or normal-user
session.

The goal is not code review. The goal is to break the target.

> Authorized security testing only.

## How it works

One portable skill (`offsec-hunter`) runs a gated pipeline:

0. **Map** — build/refresh a reusable attack-surface map (entry points → trust boundaries
   → sinks), stamped with the git commit. Skipped automatically if a fresh map exists, so
   you don't re-pay recon cost on every run.
0.5. **Threat-model checkpoint** — propose a target-specific threat model
   (attacker position, delivery vector, win condition) from the map; you confirm
   or edit it before the hunt proceeds. Lets non-web targets (untrusted input
   file → memory-safety bug, local service → DoS) be scoped in, not just web
   requests.
1. **Fan-out** — many cheap subagents generate vulnerability hypotheses (recall).
2. **Validate** — stronger subagents adversarially confirm reachability (precision).
3. **Synthesis** — confirmed findings + a working PoC (curl / request chain) per finding.

Each phase is gated on the previous phase's file artifact (in `.offsec-hunter/`), so the
workflow runs in order every time. The skill body is platform-neutral; per-platform tool
mapping lives in
[`skills/offsec-hunter/references/platform-tools.md`](skills/offsec-hunter/references/platform-tools.md).

## Install

`offsec-hunter` is a single [open-standard](https://agentskills.io/specification) skill —
it works in Claude Code and Codex unmodified. Clone the repo once, then copy the skill
into each tool's skills directory.

```bash
git clone https://github.com/deriv-security/offsec-hunter.git
cd offsec-hunter
```

### Claude Code

```bash
mkdir -p ~/.claude/skills
cp -R skills/offsec-hunter ~/.claude/skills/offsec-hunter
```

### Codex

```bash
mkdir -p ~/.codex/skills
cp -R skills/offsec-hunter ~/.codex/skills/offsec-hunter
```

Restart Codex after installing so it re-scans the skills directory. Re-run the `cp -R`
after a `git pull` to update an installed copy.

> **Note:** install with `cp -R`, not a symlink. Codex's skill scanner does not follow
> symlinks, so a symlinked skill silently fails to appear.

## Usage

```
/offsec-hunter SSRF
```

If you omit the vuln class, the skill asks which one to hunt (or `broad` for a high-impact
sweep) before starting.

## Repo layout

```
offsec-hunter/
├── README.md  ·  LICENSE  ·  .gitignore
├── docs/superpowers/specs/2026-06-26-offsec-hunter-design.md
└── skills/offsec-hunter/
    ├── SKILL.md                  # the portable skill (open agent-skills standard)
    └── references/
        ├── platform-tools.md
        └── surface-map.md
```

The full design rationale is in
[`docs/superpowers/specs/2026-06-26-offsec-hunter-design.md`](docs/superpowers/specs/2026-06-26-offsec-hunter-design.md).

## Run-time artifacts

When the skill runs against a target, it writes its working artifacts to
`.offsec-hunter/` at that target's repo root. Add `.offsec-hunter/` to the target's
`.gitignore` — these are local recon/findings, not source.

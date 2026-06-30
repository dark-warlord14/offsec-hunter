# offsec-hunter

An adversarial, budget-aware vulnerability-hunting skill for **Claude Code** and
**Codex**. It hunts for **externally reachable, exploitable** vulnerabilities — SSRF,
RCE, SQLi, SSTI, auth-bypass, IDOR and other high-impact classes — triggered **by default** by an HTTP
request, a chain of HTTP requests, or a WebSocket message from an unauth or normal-user
session.

The goal is not code review. The goal is to break the target.

> Authorized security testing only.

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

## Install

`offsec-hunter` is a plugin of six composable [open-standard](https://agentskills.io/specification) skills —
they work in Claude Code and Codex unmodified. Clone the repo once, then copy the skills
into each tool's skills directory.

```bash
git clone https://github.com/deriv-security/offsec-hunter.git
cd offsec-hunter
```

### Claude Code

```bash
mkdir -p ~/.claude/skills
cp -R skills/* ~/.claude/skills/
```

### Codex

```bash
mkdir -p ~/.codex/skills
cp -R skills/* ~/.codex/skills/
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

The full design rationale is in
[`docs/superpowers/specs/2026-06-26-offsec-hunter-design.md`](docs/superpowers/specs/2026-06-26-offsec-hunter-design.md).

## Run-time artifacts

When the skill runs against a target, it writes working artifacts under the **output
root** — by default `<target>/.offsec-hunter/` (add `.offsec-hunter/` to the target's
`.gitignore`), or a central `~/.offsec-hunter/<target-id>/` when the target tree is
read-only. Per-hunt artifacts are namespaced `hunts/<VULN>/` so different vuln classes
never clobber each other. See
[`skills/offsec-hunter/references/artifacts.md`](skills/offsec-hunter/references/artifacts.md).

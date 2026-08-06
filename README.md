# offsec-hunter

`offsec-hunter` is an adversarial, budget-aware vulnerability-hunting skill for
**Claude Code** and **Codex**. It looks for **externally reachable, exploitable**
bugs — SSRF, RCE, SQLi, SSTI, auth-bypass, IDOR, and other high-impact classes.
By default, it focuses on attacks triggered by an HTTP request, a chain of HTTP
requests, or a WebSocket message from an unauthenticated or normal-user session.

This is not a code-review assistant. The goal is to break the target, prove what
breaks, and leave behind enough evidence that the result is auditable.

> Authorized security testing only.

## How it works

The plugin is **one skill** — `offsec-hunter` — whose six steps live as reference files it loads on demand. The `offsec-hunter` orchestrator runs
six artifact-gated steps in order: each step reads the artifact from the previous
step and refuses to continue if that artifact is missing or stale. That keeps the
workflow honest, even after a resume or a redirected run.

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

Steps 4-5 run as an **autonomous round loop**. The orchestrator raises hypotheses,
tries to break them, synthesizes what survived, then redirects the next round. It
groups related ideas into a family registry, blocks routes that have gone stale,
and keeps launching rounds until two rounds in a row come up dry. Round state lives
in `state.json`, so the loop can resume without starting over. At the end, the
orchestrator regenerates a human-readable `run.md` dashboard with rounds, families,
and each finding's `finding -> survivor -> hypothesis -> sink` trace.

A completed hunt can also be **steered**. Edit the artifact at the right level
(`surface-map.json`, `target.md`, `hypotheses.jsonl`, and so on), then re-run the
hunt; only the stale steps run again, and new results merge additively. The step
bodies stay platform-neutral, with per-platform tool mapping in
[`skills/offsec-hunter/references/platform-tools.md`](skills/offsec-hunter/references/platform-tools.md).

## Install

`offsec-hunter` ships as a single
[open-standard](https://agentskills.io/specification) skill. It works in Claude
Code and Codex without modification. Clone the repo once, then copy the skill into
the tool you use.

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

### Upgrading from 1.x

1.x installed seven separate skills. Overwriting with `cp -R` leaves the six old step
directories in place, where they stay independently triggerable and contradict the
consolidated orchestrator. Remove them first:

```bash
rm -rf ~/.claude/skills/{map-attack-surface,scope-target,locate-sinks,raise-hypotheses,break-hypotheses,prove-exploit}
rm -rf ~/.codex/skills/{map-attack-surface,scope-target,locate-sinks,raise-hypotheses,break-hypotheses,prove-exploit}
```

Then re-run the `cp -R` for your tool.

## Usage

```
/offsec-hunter SSRF
```

If you omit the vuln class, the skill asks what to hunt before it starts. Use
`broad` for a high-impact sweep.

## Repo layout

```
offsec-hunter/
├── README.md  ·  LICENSE  ·  .gitignore
├── .claude-plugin/plugin.json
├── docs/superpowers/specs/  ·  docs/superpowers/plans/
├── tests/                         # static contract + behavioral recall tests
└── skills/
    └── offsec-hunter/             # the only skill
        ├── SKILL.md               # orchestrator
        └── references/
            ├── platform-tools.md  ·  artifacts.md
            └── step-1-map-attack-surface.md … step-6-prove-exploit.md
```

The main design rationale is in
[`docs/superpowers/specs/2026-06-26-offsec-hunter-design.md`](docs/superpowers/specs/2026-06-26-offsec-hunter-design.md);
the autonomous round loop is designed in
[`docs/superpowers/specs/2026-07-21-autonomous-round-loop-design.md`](docs/superpowers/specs/2026-07-21-autonomous-round-loop-design.md);
the comprehension-first recon split is designed in
[`docs/superpowers/specs/2026-08-06-comprehension-first-recon-design.md`](docs/superpowers/specs/2026-08-06-comprehension-first-recon-design.md);
the single-skill consolidation is designed in [`docs/superpowers/specs/2026-08-06-single-skill-consolidation-design.md`](docs/superpowers/specs/2026-08-06-single-skill-consolidation-design.md).

## Run-time artifacts

When the skill runs against a target, it writes working artifacts under the
**output root**. By default, that is `<target>/.offsec-hunter/`; add
`.offsec-hunter/` to the target's `.gitignore`. If the target tree is read-only,
the skill can use a central `~/.offsec-hunter/<target-id>/` directory instead.

Per-hunt artifacts live under `hunts/<VULN>/`, so separate vuln-class hunts do not
clobber each other. The key files are `target.md`, `sinks.json`, `hypotheses.jsonl`,
`survivors.jsonl`, `findings.{md,json}`, `pocs/finding-NNN.md`, and the regenerated
`run.md` dashboard. See
[`skills/offsec-hunter/references/artifacts.md`](skills/offsec-hunter/references/artifacts.md)
for the full layout.

# Comprehension-first recon — design

**Date:** 2026-08-06
**Status:** approved, not yet implemented

## Problem

`map-attack-surface` (step 1) currently does two jobs at once:

1. **Comprehension** — entry points, trust boundaries, how external input flows.
2. **Security judgment** — it labels each sink with a vuln `class`
   (`ssrf | rce | sqli | ssti | deserialization | authz | parsing`), calls them
   "high-risk sinks", and records trust-boundary notes on "where it might be
   bypassable".

Job 2 is premature. It forms verdicts before `scope-target` (step 2) has even chosen
a vuln class, which means the map bakes in a class taxonomy that the run may not use,
and it invites the recon agent to start hunting instead of understanding.

The goal: step 1 becomes comprehension only — how the target works, its trust
boundaries, its data flows, and what the code assumes. Actual security hunting begins
downstream.

## Prior art

Five harnesses were reviewed. They do **not** agree, and the disagreement is the
useful part.

| Harness | Recon stage | Security-neutral? |
|---|---|---|
| [Code-Augur](https://arxiv.org/pdf/2606.18619) | Specification Inference → Vulnerability Detection | **Yes** — explicitly no sink identification, no vuln-class assignment; emits preconditions/postconditions/invariants, and hunting looks for deviations from them |
| [Cloudflare Glasswing](https://blog.cloudflare.com/cyber-frontier-models/) | Arch doc: build commands, trust boundaries, entry points, **and "likely attack surface"** + a task queue | No |
| [flaw0/mythosharness](https://github.com/flaw0-security/mythosharness) | Recon → arch doc; each hunter gets arch doc + **one attack class + one scope hint** | No — narrowing is per-task, injected at hunt time |
| [Tenable](https://www.tenable.com/blog/testing-claude-mythos-preview-for-code-security-tenable) | **Threat model first**, which "scopes a static pass to specific abuse cases in specific code paths" | No — scoping *precedes* and bounds comprehension |
| [Anthropic reference harness](https://github.com/anthropics/defending-code-reference-harness) | `/threat-model` → `/vuln-scan` "scoped by threat model"; autonomous Recon partitions source into "input-parsing subsystems worth attacking separately" | No |

### What the prior art actually converges on

Not "recon emits nothing security-related." The convergent pattern is: **the shared,
reusable artifact is comprehension; the security-specific narrowing is per-task and
injected downstream.** Cloudflare and flaw0 both keep one stable arch doc and hand each
hunter a class plus a scope hint separately.

Cloudflare states the underlying principle directly: *"splitting the chain across
agents produces better reasoning"* — "Is this code buggy?" and "Can an attacker
actually reach this bug from outside?" are better asked narrowly and separately.

### The constraint Tenable adds

Tenable warns: *"Point an agent at a complex service and it exhausts its context window
just mapping architecture."*

This lands directly on step 1. Today the **only** thing bounding it is its security
framing — "not an exhaustive code read", "prioritize what is **reachable from crafted
input** over reading everything." Remove the security judgment *and* that pruning rule
and step 1 degenerates into "understand this codebase", which is unbounded.

**Therefore: strip the vuln-class judgment, keep the reachability-driven pruning.**
Reachability is a factual property of the code ("can external input get here"), not a
verdict about a vulnerability, so it survives the comprehension-only rule while still
bounding the stage.

### What Code-Augur adds

Its comprehension artifact is richer than a sink list: inferred **assumptions and
invariants** — "this function assumes its `url` argument was already validated by its
caller", "this parser trusts the length field". Those are statements about how the
target works, and they are better hunting seeds than a class-tagged sink list, because
hunting becomes "find a path that violates this assumption" — which is exactly what
`break-hypotheses` already adjudicates.

## Design

### Step order

A sixth step, `locate-sinks`, is inserted after `scope-target`. It is Cloudflare's task
queue and flaw0's "attack class + scope hint", made into an artifact-gated step.

| Step | Skill | Reads | Writes |
|---|---|---|---|
| 1 | `map-attack-surface` | target code | `surface-map.json` (commit-stamped, **class-agnostic**) |
| 2 | `scope-target` | `surface-map.json` | `hunts/<VULN>/target.md` |
| 3 | `locate-sinks` | `surface-map.json` + `target.md` | `hunts/<VULN>/sinks.json` |
| 4 | `raise-hypotheses` | `sinks.json` | `hypotheses.jsonl` |
| 5 | `break-hypotheses` | `hypotheses.jsonl` | `survivors.jsonl` |
| 6 | `prove-exploit` | `survivors.jsonl` | `findings.{md,json}` + `pocs/` |

Steps 4–5 remain the round-loop body. Step 3 runs once per hunt (it is class-scoped,
so it re-runs when `target.md` changes).

### What moves out of step 1

- The entire `sinks[]` array, including the `class` and `origin` fields.
- Conditional **dependency indexing** — deciding that vendored code is worth indexing
  as sinks is a security judgment motivated by bug-chaining.
- Risk vocabulary: "high-risk sinks", "where it might be bypassable".

### What stays in step 1

- `entry_points[]` (`ep-N`), `trust_boundaries[]` (`tb-N`), `flows[]`.
- Reachability pruning — a flow is recorded only if external input can plausibly reach
  its endpoint. This is the stage's bound.
- Commit-stamped freshness and cross-hunt reuse.

### What is added to step 1

- `assumptions[]` (`asm-N`) — inferred preconditions/invariants per Code-Augur.
  Consumed by `locate-sinks` when deriving sinks, so the field has a real consumer and
  is not speculative.

### Language and ecosystem neutrality

The comprehension-only rule makes this constraint sharper, so it is stated explicitly
rather than left implicit.

Both `map-attack-surface` and `locate-sinks` must describe the target in terms of
**behaviour**, never in terms of one language's API names, one framework's routing
conventions, or one ecosystem's directory layout:

- Operations are recorded as "issues an outbound network request", "constructs a query
  from concatenated input", "starts a subprocess", "renders a template" — not
  `http.get()`, `subprocess.run()`, or any other concrete call.
- Every file path, extension, and directory name in a schema example is an **illustrative
  placeholder** (`path/to/file.ext:LINE`). The agent infers the target's actual
  conventions from the target.
- Vendored-dependency layouts (`vendor/`, `node_modules/`, `third_party/`, `deps/`, a
  lockfile-declared tree) are listed as **examples of a pattern**, not an exhaustive set.
  The rule is "the target vendors its dependencies", whatever that looks like in its
  ecosystem.

This mirrors the existing platform-neutrality invariant — skill prose speaks in actions,
concrete tool names live only in `platform-tools.md` — and extends it from the *agent's*
runtime to the *target's* runtime.

### Schema changes to `surface-map.json`

- `sinks[]` — **removed** (moves to `sinks.json`).
- `flows[].to_sink` → `flows[].reaches` — a `file:LINE` plus a factual one-line
  description of the operation at that location ("issues an outbound HTTP request with
  the supplied URL"), with **no** vuln class.
- `flows[].guards` → `flows[].validation` — a factual statement of what the code checks
  ("compares host against `ALLOWED_HOSTS` at `file.ext:LINE`"), not a judgment about
  whether it holds. Whether it holds is still `break-hypotheses`'s job.
- `trust_boundaries[].notes` — describes how the gate works; drops "where it might be
  bypassable".
- `assumptions[]` — added.

### `sinks.json` (new, per-hunt)

Owned by `locate-sinks`. It holds everything removed from the map, now scoped to the
confirmed vuln class from `target.md`:

```json
{
  "vuln": "SSRF",
  "input_hash": "<sha256 of surface-map.json + target.md>",
  "sinks": [
    {
      "id": "sink-1",
      "origin": "target | dependency",
      "class": "ssrf",
      "location": "path/to/file.ext:LINE",
      "summary": "outbound HTTP fetch of a request-supplied URL",
      "from_flows": ["ep-1"],
      "from_assumptions": ["asm-2"]
    }
  ]
}
```

### Invariants preserved

- **`sink-N` ids keep their meaning and their global uniqueness**, so the full trace
  `finding → survivor → hypothesis → sink` is unchanged, as is the round-loop redirect
  ("mapped sinks no family covers yet" now reads `sinks.json`).
- The orchestrator remains **sole id authority** — `locate-sinks` is orchestrator-run,
  not a subagent-assigned id space.
- Artifact-gating is unchanged; the new step adds one more gate.
- The map stays **target-level and class-agnostic**, so it is still reused across
  vuln-class hunts. It is now *more* reusable, since it no longer carries class tags.

## Decisions taken

- **Keep the name `map-attack-surface`.** Entry points plus trust boundaries is a fair
  reading of "attack surface", and renaming costs churn across README, tests, the
  plugin manifest, and the orchestrator for no behavioral gain.
- **Name the new step `locate-sinks`**, matching the verb-noun convention of its
  siblings.

## Explicitly out of scope

- **Reordering scope before map.** Tenable and Anthropic's reference harness both scope
  first; this change pushes us further from that shape. It is a larger restructuring and
  is deferred.
- **A dedicated Trace stage.** Cloudflare calls reachability tracing "the stage that
  matters most"; ours is folded into `break-hypotheses`. Deferred.
- **Cross-repo reasoning.** Tenable: "the vulnerable code and the entry point that
  reaches it each typically live in different services." Our two-roots model assumes a
  single target root. Real gap, deferred.
- **A deterministic success oracle.** Mozilla uses an ASan crash as ground truth; step 6
  requires a PoC but has no automated oracle. Deferred.

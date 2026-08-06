# Step 1 — map-attack-surface

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
4. Write `surface-map.json` per the schema below, stamped with
   `commit` = current `HEAD`. Record the step as done in `state.json`.

Prioritize what is **reachable from crafted input** over reading everything.

## surface-map.json — schema & freshness

The map is the persisted, reusable recon artifact. It is written to
`.offsec-hunter/surface-map.json` at the target repo root and is **gitignored**.

## Freshness rule

The map records the git commit it was built from. On each run:

- If `surface-map.json` exists and `commit == git rev-parse HEAD` → **fresh**: load and
  reuse, skip rebuilding.
- Otherwise → **stale or missing**: rebuild. Never trust a stale map.

This makes reuse automatic and self-maintaining: the map regenerates only when the code
actually changed.

## Schema

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

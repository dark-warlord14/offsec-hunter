# Attack-surface map — schema & freshness

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

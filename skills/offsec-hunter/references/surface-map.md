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
      "kind": "http | websocket | rpc | consumer | job",
      "route": "POST /api/fetch",
      "auth": "unauth | session | m2m",
      "handler": "path/to/handler.ext:LINE"
    }
  ],
  "trust_boundaries": [
    {
      "id": "tb-1",
      "from": "unauth",
      "to": "session",
      "enforced_at": "path/to/middleware.ext:LINE",
      "notes": "how the gate works / where it might be bypassable"
    }
  ],
  "sinks": [
    {
      "id": "sink-1",
      "class": "ssrf | rce | sqli | ssti | deserialization | authz | parsing",
      "location": "path/to/file.ext:LINE",
      "summary": "outbound HTTP fetch of a request-supplied URL"
    }
  ],
  "flows": [
    {
      "from_entry": "ep-1",
      "to_sink": "sink-1",
      "input_path": "body.url -> validate() -> http.get()",
      "guards": ["allowlist check at file.ext:LINE"],
      "reachable_from": "unauth"
    }
  ]
}
```

## Guidance

- Keep it a **reachability index**, not a full code dump. A flow exists only if external
  input can plausibly reach the sink.
- `flows` is what Phase 1 fans out over — each flow is a hypothesis seed.
- Record `guards` honestly; Phase 2's job is to determine whether they actually hold.

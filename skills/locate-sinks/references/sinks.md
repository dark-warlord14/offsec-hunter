# sinks.json — schema

Per-hunt, class-scoped. Written by `locate-sinks` to `hunts/<VULN>/sinks.json`. This is
the hunt's task queue: `raise-hypotheses` fans out over it, one subagent per sink.

## Schema

```json
{
  "vuln": "SSRF",
  "input_hash": "<sha256 of surface-map.json + target.md>",
  "sinks": [
    {
      "id": "sink-1",
      "origin": "target | dependency",
      "class": "ssrf | rce | sqli | ssti | deserialization | authz | parsing",
      "location": "path/to/file.ext:LINE",
      "summary": "issues an outbound network request to a caller-supplied address",
      "from_flows": ["ep-1"],
      "from_assumptions": ["asm-2"]
    }
  ]
}
```

## Rules

- `id` is globally unique across the hunt and is assigned **only here**. Subagents never
  invent sink ids.
- `origin` marks vendored dependency code (`dependency`) versus the target's own code
  (`target`). `break-hypotheses` uses it when chaining a target bug with a dependency bug.
- `from_flows` / `from_assumptions` trace a sink back to the map entries that produced
  it. A sink found by direct search in step 3 of the procedure may have both empty.
- `class` is scoped to the hunt's confirmed vuln class. A sink that cannot serve the
  confirmed win condition does not belong here.
- `summary` describes **what the code does**, not which API it calls — "starts a
  subprocess with caller-influenced arguments", not a concrete function name. The classes
  above are behavioural and exist in every language; paths and extensions are
  illustrative placeholders.

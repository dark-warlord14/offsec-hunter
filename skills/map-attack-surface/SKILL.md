---
name: map-attack-surface
description: Step 1 of offsec-hunter. Build or refresh a reusable attack-surface map of a target — entry points, trust boundaries, high-risk sinks, and input flows — stamped with the git commit. Reuses a fresh map automatically.
---

# map-attack-surface — step 1

Goal: a structured model of how external input enters and flows — **not** an exhaustive
code read. This map is also the reachability index that prunes the rest of the hunt.

This step writes `surface-map.json` under the output root (see the offsec-hunter artifacts
guide). It has no input artifact — it is the first step.

## Procedure

1. Get the current commit: `git rev-parse HEAD`.
2. If `surface-map.json` exists and its `commit` equals `HEAD` → the map is **fresh**: load
   it and stop (downstream steps reuse it).
3. Otherwise build/refresh the map. Identify:
   - **Entry points** — HTTP routes, WebSocket handlers, RPC handlers, message consumers,
     scheduled jobs, parsed input files, CLIs, IPC/sockets, local services.
   - **Trust boundaries** — unauth ↔ session ↔ m2m; browser ↔ server; service ↔ service.
   - **High-risk sinks** — outbound fetch (SSRF), deserialization, templating (SSTI),
     command/eval (RCE), query construction (SQLi), authz checks, untrusted parsing.
     Assign each sink a **stable id** (`sink-1`, `sink-2`, …) so downstream artifacts can
     reference it.
   - **Input flow** — how external input reaches each sink and how it is mutated en route.
   - **Dependency sinks (conditional)** — **if** the target vendors its dependencies
     (common layouts: `third_party/`, `vendor/`, `node_modules/`, `deps/`, or a
     lockfile-declared tree), index high-risk code in them as sinks too, with their own
     `sink-N` ids. RCE may require chaining a target bug with a dependency bug. If no
     vendored deps are present, skip this — emit no dependency sinks and no error.
4. Write `surface-map.json` per the schema in `references/surface-map.md`, stamped with
   `commit` = current `HEAD`. Record the step as done in `state.json`.

Prioritize what is **reachable from crafted input** over reading everything.

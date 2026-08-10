# Platform tool mapping

The `SKILL.md` body speaks in **actions**. Map each action to your platform's concrete
tools. The skill never depends on a platform-specific orchestration engine.

## Action → tool

| Action in SKILL.md | Claude Code | Codex |
|---|---|---|
| "Use the `<name>` skill" | `Skill` tool with that skill's name | the skill is available by name; if it does not load, read its `SKILL.md` in the sibling skill directory |
| "Dispatch a subagent" | `Agent` / `Task` tool | spawn agents explicitly ("spawn one agent per sink") |
| "...on a cheap/fast model" | set `model: "haiku"` | inherits the orchestrator's model — see note |
| "...stronger model for validation" | set `model: "sonnet"` | inherits the orchestrator's model — see note |
| "shallow read-only hunting" | `subagent_type: "Explore"` | read-only delegated task |
| "deeper task needing more tools" | `subagent_type: "general-purpose"` | general delegated task |
| "create one task per step" | `TaskCreate` / todo list | task/todo tracking |
| "run subagents in parallel" | multiple `Agent` calls in one message | concurrent task delegation |
| "always-on project context" | `CLAUDE.md` | `AGENTS.md` |
| "vuln-class argument delivery" | user-supplied argument to `/offsec-hunter`, or `broad` if none | user-supplied argument at invocation, or `broad` if none |

Notes:
- Claude Code: do NOT use `subagent_type: "general"` — it is invalid; the catch-all is
  `general-purpose`.
- If a platform lacks parallel subagents, run any per-item subagent step (e.g. `raise-hypotheses`
  hypotheses or `break-hypotheses` candidates) sequentially on the assigned model — the
  artifact-gating and step order are unchanged.
- The orchestrator (the main session) always resolves roots/mode and runs `prove-exploit`
  synthesis itself.
- **Reaching a sibling skill is allowed.** A step skill is a peer, not a private directory.
  Use it by name; if the platform does not surface it, read its `SKILL.md` from the sibling
  skill directory. Doing the step's work inline from the orchestrator's summary line is the
  one thing that is never acceptable.
- **Model tiering is Claude Code only.** Codex subagents **inherit the orchestrator's
  model**; per-task model selection is not currently available. On Codex the cheap/strong
  split does not apply — run every step on the session model and rely on artifact gating,
  not cost tiering, for control.
- **Fan-out width differs.** Codex guidance is to keep delegation concurrency at 1 unless
  there is a specific reason, and warns that broad delegation instructions cause repeated
  fan-out. On Codex, run the per-item steps (`raise-hypotheses`, `break-hypotheses`) with a
  small fixed concurrency or sequentially. Artifact gating and step order are unchanged.
- **Codex delegates on an explicit instruction.** Codex spawns subagents after a direct
  request or an applicable skill instruction, so phrase delegation imperatively ("spawn one
  agent per sink"), not as a description.

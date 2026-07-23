# Platform tool mapping

The `SKILL.md` body speaks in **actions**. Map each action to your platform's concrete
tools. The skill never depends on a platform-specific orchestration engine.

## Action → tool

| Action in SKILL.md | Claude Code | Codex |
|---|---|---|
| "Dispatch a subagent" | `Agent` / `Task` tool | native subagent / task delegation |
| "...on a cheap/fast model" | set `model: "haiku"` | select a fast/cheap model for the task |
| "...stronger model for validation" | set `model: "sonnet"` | select a stronger model for the task |
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

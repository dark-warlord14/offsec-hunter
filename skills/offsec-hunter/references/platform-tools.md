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
| "create one task per phase" | `TaskCreate` / todo list | task/todo tracking |
| "run subagents in parallel" | multiple `Agent` calls in one message | concurrent task delegation |

Notes:
- Claude Code: do NOT use `subagent_type: "general"` — it is invalid; the catch-all is
  `general-purpose`.
- If a platform lacks parallel subagents, run the Phase 1 hypotheses sequentially on the
  cheap model — the artifact-gating and phase order are unchanged.
- The orchestrator (the main session) always does Phase 0 reasoning and Phase 3 synthesis.

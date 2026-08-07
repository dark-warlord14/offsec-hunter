#!/usr/bin/env bash
# Tier 2 — behavioral recall: assert the agent describes the workflow correctly.
# Opt-in (LLM calls): RUN_BEHAVIORAL=1 bash tests/run-skill-tests.sh
#
# Runs against either platform, since the skills target both:
#   AGENT=claude (default)  RUN_BEHAVIORAL=1 bash tests/run-skill-tests.sh
#   AGENT=codex             RUN_BEHAVIORAL=1 bash tests/run-skill-tests.sh
#
# Codex note: `codex exec` echoes the loaded skill body into its transcript, so grepping
# raw stdout would match the SKILL.md text instead of the agent's answer — a false pass.
# `-o FILE` writes only the final message, which is what we assert against.
set -uo pipefail
TIMEOUT="${CLAUDE_PROMPT_TIMEOUT:-120}"
AGENT="${AGENT:-claude}"
fail=0

run_agent() {
  case "$AGENT" in
    claude) timeout "$TIMEOUT" claude -p "$1" 2>&1 ;;
    codex)
      local out; out="$(mktemp)"
      timeout "$TIMEOUT" codex exec --skip-git-repo-check -o "$out" "$1" </dev/null >/dev/null 2>&1
      cat "$out"; rm -f "$out" ;;
    *) echo "unknown AGENT: $AGENT" >&2; exit 2 ;;
  esac
}
run_claude() { run_agent "$1"; }   # back-compat alias

check() { # haystack pattern label
  if echo "$1" | grep -Eiq "$2"; then echo "  [PASS] $3";
  else echo "  [FAIL] $3"; fail=1; fi
}

echo "=== Behavioral recall (agent: $AGENT) ==="
out="$(run_claude 'Describe the offsec-hunter skill: list its steps in order and how it gates between them. Be brief.')"

check "$out" 'map.?attack.?surface' "names step 1"
check "$out" 'scope.?target'        "names step 2"
check "$out" 'locate.?sinks'        "names step 3"
check "$out" 'raise.?hypotheses'    "names step 4"
check "$out" 'break.?hypotheses'    "names step 5"
check "$out" 'prove.?exploit'       "names step 6"
check "$out" 'artifact|gate|state\.json' "describes artifact-gating"

out2="$(run_claude 'In offsec-hunter, what is the difference between interactive and headless mode? Be brief.')"
check "$out2" 'headless' "explains headless mode"
check "$out2" 'confirm|ask|interactive' "explains interactive mode"

# Steps must be USED as skills, never inlined by the orchestrator. Asked as its own
# prompt — a question about steps and gating does not elicit how they are invoked.
out4="$(run_claude 'In offsec-hunter, how does the orchestrator carry out each step — does it do the work itself? Be brief.')"
check "$out4" 'skill'                    "says the steps are skills"
check "$out4" 'use|invoke'               "says the orchestrator uses them"
check "$out4" 'not|never|rather than|instead' "says it does not do the work itself"

out3="$(run_claude 'In offsec-hunter, when does the hunt stop launching new rounds, and what is a family registry? Be brief.')"
check "$out3" 'dry|two rounds|2 rounds' "explains the dry-round stop rule"
check "$out3" 'famil' "explains the family registry"
check "$out3" 'block|redirect' "explains blocked/redirect behaviour"

[ "$fail" -eq 0 ] && echo "  ---- behavioral PASS ----" || { echo "  ---- behavioral FAIL ----"; exit 1; }

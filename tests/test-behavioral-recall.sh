#!/usr/bin/env bash
# Tier 2 — behavioral recall: assert the agent describes the workflow correctly.
# Opt-in (LLM calls): RUN_BEHAVIORAL=1 bash tests/run-skill-tests.sh
set -uo pipefail
TIMEOUT="${CLAUDE_PROMPT_TIMEOUT:-120}"
fail=0

run_claude() { timeout "$TIMEOUT" claude -p "$1" 2>&1; }

check() { # haystack pattern label
  if echo "$1" | grep -Eiq "$2"; then echo "  [PASS] $3";
  else echo "  [FAIL] $3"; fail=1; fi
}

echo "=== Behavioral recall ==="
out="$(run_claude 'Describe the offsec-hunter skill: list its steps in order and how it gates between them. Be brief.')"

check "$out" 'map.?attack.?surface' "names step 1"
check "$out" 'scope.?target'        "names step 2"
check "$out" 'raise.?hypotheses'    "names step 3"
check "$out" 'break.?hypotheses'    "names step 4"
check "$out" 'prove.?exploit'       "names step 5"
check "$out" 'artifact|gate|state\.json' "describes artifact-gating"

out2="$(run_claude 'In offsec-hunter, what is the difference between interactive and headless mode? Be brief.')"
check "$out2" 'headless' "explains headless mode"
check "$out2" 'confirm|ask|interactive' "explains interactive mode"

[ "$fail" -eq 0 ] && echo "  ---- behavioral PASS ----" || { echo "  ---- behavioral FAIL ----"; exit 1; }

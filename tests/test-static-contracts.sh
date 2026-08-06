#!/usr/bin/env bash
# Tier 1 — static contract tests over the skill markdown (no LLM).
set -uo pipefail
source "$(cd "$(dirname "$0")" && pwd)/test-helpers.sh"

echo "=== Static contract tests ==="

# --- Packaging (Task 1) ---
assert_file_exists ".claude-plugin/plugin.json" "plugin manifest exists"
assert_file_contains ".claude-plugin/plugin.json" '"name"[[:space:]]*:[[:space:]]*"offsec-hunter"' "manifest names the plugin"

# (subsequent tasks append their assertion blocks below)

# --- Orchestrator (Task 2) ---
O="skills/offsec-hunter/SKILL.md"
M="skills/offsec-hunter/references/step-1-map-attack-surface.md"
S="skills/offsec-hunter/references/step-2-scope-target.md"
L="skills/offsec-hunter/references/step-3-locate-sinks.md"
R="skills/offsec-hunter/references/step-4-raise-hypotheses.md"
B="skills/offsec-hunter/references/step-5-break-hypotheses.md"
P="skills/offsec-hunter/references/step-6-prove-exploit.md"
assert_single_skill "offsec-hunter is the only skill"
assert_references_one_level "references are one level deep"
assert_file_contains "$O" '^name: offsec-hunter' "orchestrator frontmatter name"
assert_file_contains "$O" 'map-attack-surface' "orchestrator names step 1"
assert_file_contains "$O" 'scope-target' "orchestrator names step 2"
assert_file_contains "$O" 'locate-sinks' "orchestrator names step 3"
assert_file_contains "$O" 'raise-hypotheses' "orchestrator names step 4"
assert_file_contains "$O" 'break-hypotheses' "orchestrator names step 5"
assert_file_contains "$O" 'prove-exploit' "orchestrator names step 6"
assert_file_contains "$O" 'interactive' "orchestrator documents interactive mode"
assert_file_contains "$O" 'headless' "orchestrator documents headless mode"
assert_file_contains "$O" 'state\.json' "orchestrator references state.json"
assert_file_contains "$O" '[Tt]arget root' "orchestrator resolves target root"
assert_file_contains "$O" '[Oo]utput root' "orchestrator resolves output root"
assert_file_contains "$O" '[Ss]teer' "orchestrator documents steering"
assert_file_contains "$O" 'artifacts\.md' "orchestrator references artifacts guide by name"
assert_file_exists "skills/offsec-hunter/references/artifacts.md" "artifacts guide exists"
assert_file_contains "$O" 'references/step-1-map-attack-surface\.md' "orchestrator names step 1 reference"
assert_file_contains "$O" 'references/step-6-prove-exploit\.md' "orchestrator names step 6 reference"
assert_file_contains "$O" '[Rr]ead.*references/step' "orchestrator instructs reading the step file"
assert_file_contains "$O" 'comprehension only' "orchestrator carries step 1 binding constraint"
assert_file_contains "$O" 'write .?state\.json.? .*before|[Bb]efore .*step 1' "orchestrator writes state.json before step 1"
assert_file_not_contains "$O" 'invoke the .[a-z-]+. skill' "orchestrator no longer says invoke-by-name"
assert_file_not_contains "$O" 'Never reach into' "orchestrator drops the reach-into prohibition"

# --- map-attack-surface (Task 3) ---
assert_file_contains "$M" 'surface-map\.json' "step1 writes surface-map.json"
assert_file_contains "$M" 'rev-parse HEAD' "step1 commit-stamps freshness"
assert_file_contains "$M" 'surface-map\.json — schema' "step1 carries its schema inline"

# --- scope-target (Task 4) ---
assert_file_contains "$S" 'surface-map\.json' "step2 reads surface-map.json"
assert_file_contains "$S" 'map-attack-surface first' "step2 actionable missing-input error"
assert_file_contains "$S" 'target\.md' "step2 writes target.md"
assert_file_contains "$S" 'interactive' "step2 has interactive branch"
assert_file_contains "$S" 'headless' "step2 has headless branch"
assert_file_contains "$S" '[Aa]ttacker position' "step2 covers attacker position"
assert_file_contains "$S" '[Dd]elivery vector' "step2 covers delivery vector"
assert_file_contains "$S" '[Ww]in condition' "step2 covers win condition"

# --- raise-hypotheses (Task 5) ---
assert_file_contains "$R" 'target\.md' "step4 reads target.md"
assert_file_contains "$R" 'locate-sinks first' "step4 actionable missing-input error"
assert_file_contains "$R" 'sinks\.json' "step4 reads sinks.json"
assert_file_contains "$R" 'hypotheses\.jsonl' "step4 writes hypotheses.jsonl"
assert_file_contains "$R" '[Rr]ecall' "step4 optimizes recall"
assert_file_contains "$R" '(cheap|fast)' "step4 uses cheap/fast model"

# --- break-hypotheses (Task 6) ---
assert_file_contains "$B" 'hypotheses\.jsonl' "step5 reads hypotheses.jsonl"
assert_file_contains "$B" 'raise-hypotheses first' "step5 actionable missing-input error"
assert_file_contains "$B" 'survivors\.jsonl' "step5 writes survivors.jsonl"
assert_file_contains "$B" '(break the claim|try to break)' "step5 is adversarial"
assert_file_contains "$B" '(stronger|strong)' "step5 uses a stronger model"

# --- prove-exploit (Task 7) ---
assert_file_contains "$P" 'survivors\.jsonl' "step6 reads survivors.jsonl"
assert_file_contains "$P" 'break-hypotheses first' "step6 actionable missing-input error"
assert_file_contains "$P" 'findings\.json' "step6 emits machine-readable findings"
assert_file_contains "$P" 'findings\.md' "step6 emits human-readable findings"
assert_file_contains "$P" 'no exploitable findings' "step6 has empty-results report"
assert_file_contains "$P" 'entry-point \+ sink' "step6 documents additive-merge dedup key"
assert_file_contains "$P" 'pocs/finding-NNN\.md' "step6 writes minimal markdown PoCs"

# --- map is comprehension-only (2026-08-06) ---
assert_file_not_contains "$M" 'sink-[0-9]|high-risk sink|[Ss]inks —' "step1 emits no sinks"
assert_file_contains "$M" '[Cc]omprehension only' "step1 declares comprehension-only"
assert_file_contains "$M" 'asm-[0-9]|[Aa]ssumption' "step1 records assumptions"
assert_file_contains "$M" 'reachab' "step1 keeps reachability pruning as its bound"
assert_file_contains "$M" 'language|ecosystem' "step1 is language-agnostic"
assert_file_contains "$M" 'asm-[0-9]' "surface-map schema has assumption ids"
assert_file_contains "$M" 'language|ecosystem' "surface-map schema is language-agnostic"
assert_file_not_contains "$M" '"sinks"' "surface-map schema has no sinks array"

# --- Orchestrator round loop (Task 2) ---
assert_file_contains "$O" '[Rr]ound loop' "orchestrator documents the round loop"
assert_file_contains "$O" '2 (consecutive )?dry rounds' "orchestrator states the dry-round stop rule"
assert_file_contains "$O" 'round > 6|round &gt; 6' "orchestrator has soft backstop"
assert_file_contains "$O" '[Ff]amily registry' "orchestrator manages the family registry"
assert_file_contains "$O" '[Bb]locked' "orchestrator documents blocked families"
assert_file_contains "$O" '[Rr]edirect' "orchestrator documents redirect"
assert_file_contains "$O" '[Rr]esumable|reads state\.json' "orchestrator documents resumable loop"
assert_file_contains "$O" '[Cc]ontext-injection|inject' "orchestrator documents context-injection contract"
assert_file_contains "$O" 'run\.md' "orchestrator writes run.md dashboard"

# --- Round-loop artifacts (Task 1) ---
A="skills/offsec-hunter/references/artifacts.md"
assert_file_contains "$A" '"round"' "artifacts documents round field"
assert_file_contains "$A" '"dry_streak"' "artifacts documents dry_streak field"
assert_file_contains "$A" '"families"' "artifacts documents family registry"
assert_file_contains "$A" '"round_log"' "artifacts documents round_log"
assert_file_contains "$A" 'sink-[0-9]' "artifacts documents stable sink ids"
assert_file_contains "$A" '[Rr]esumable' "artifacts documents resumable loop"
assert_file_contains "$A" 'sinks\.json' "artifacts documents sinks.json"
assert_file_contains "$A" 'locate-sinks' "artifacts documents the locate-sinks step"
assert_file_contains "$A" '"chain"' "artifacts documents chain field"
assert_file_contains "$A" 'stale when .surface-map\.json. or .target\.md.' "artifacts ties sinks.json staleness to both inputs"

# --- raise round-aware + ids (Task 4) ---
assert_file_contains "$R" '"family"' "step4 tags hypotheses with a family"
assert_file_contains "$R" '"sink"' "step4 references the sink id"
assert_file_contains "$R" '[Rr]ound' "step4 is round-aware"
assert_file_contains "$R" 'output_root|inject' "step4 injects context into subagents"

# --- break chaining + trace (Task 5) ---
assert_file_contains "$B" '[Cc]hain' "step5 documents bug-chaining"
assert_file_contains "$B" '"chain"' "step5 records chain field on survivors"
assert_file_contains "$B" '"severity"' "step5 carries severity"
assert_file_contains "$B" '"confidence"' "step5 carries confidence"
assert_file_contains "$B" '[Dd]ependenc' "step5 chains dependency bugs when present"

# --- prove trace + dashboard (Task 6) ---
assert_file_contains "$P" '"survivor"' "step6 traces finding to survivor"
assert_file_contains "$P" '"sink"' "step6 traces finding to sink"
assert_file_contains "$P" '"confidence"' "step6 carries confidence"
assert_file_contains "$P" 'run\.md' "step6 contributes to run.md dashboard"

# --- v2: canonical state + resume (Task 9) ---
assert_file_contains "$A" '"status": "looping"' "artifacts shows looping status"
assert_file_contains "$A" 'last_round' "artifacts shows last_round"
assert_file_contains "$O" 'initialize' "orchestrator initializes round state"
assert_file_contains "$O" 'no-op|already recorded' "orchestrator makes re-run idempotent"

# --- v2: id authority + round tags + dedup (Task 10) ---
assert_file_contains "$O" 'sole id authority|assigns.*id|id authority' "orchestrator is id authority"
assert_file_contains "$R" '"round"' "hypotheses carry round tag"
assert_file_contains "$B" '"round"' "survivors carry round tag"
assert_file_contains "$B" 'dedup|de-duplicat' "survivors are de-duplicated"
assert_file_contains "$A" '"round"' "artifacts document round tag on lines"

# --- v2: staleness vs rounds (Task 11) ---
assert_file_contains "$A" 'steering only|governs steering' "artifacts scopes staleness to steering"
assert_file_contains "$O" 'every round|drives.*by round' "orchestrator re-runs raise/break each round"
assert_file_contains "$B" 'current round|round == ' "break processes current round only"

# --- v2: materially-new definition (Task 12) ---
assert_file_contains "$O" 'distinct sink|guard-bypass' "orchestrator defines materially-new operationally"
assert_file_contains "$R" '"mechanism"' "hypotheses carry a mechanism field"
assert_file_contains "$A" '"mechanism"' "artifacts document the mechanism field"

# --- v2: break context injection (Task 13) ---
assert_file_contains "$B" 'output_root|inject' "break injects context into subagents"
assert_file_contains "$B" 'candidate.*fields|full fields' "break injects the candidate's fields"

# --- v2: chaining at synthesis (Task 14) ---
assert_file_contains "$O" 'chain' "orchestrator assembles chains at synthesis"
assert_file_contains "$B" 'chainable|flag' "break only flags chainability"

# --- v2: run.md single owner (Task 15) ---
assert_file_contains "$O" 'regenerate' "orchestrator regenerates run.md"
assert_file_contains "$P" 'not.*run\.md|orchestrator.*run\.md' "prove defers run.md to orchestrator"

# --- v2: codex portability (Task 16) ---
assert_file_contains "skills/offsec-hunter/references/platform-tools.md" 'AGENTS\.md' "platform-tools maps always-on context"
assert_file_not_contains "$O" '\$ARGUMENTS' "orchestrator body has no \$ARGUMENTS token"
assert_file_not_contains "$S" '\$ARGUMENTS' "scope body has no \$ARGUMENTS token"

# --- v2: schema fields (Task 18) ---
assert_file_contains "$A" 'guards' "artifacts documents guards field on survivors"
assert_file_contains "$A" 'origin' "artifacts documents origin field on sinks"
assert_file_contains "$L" 'origin' "sinks schema includes origin field"

# --- v2: rounds=1 regression (Task 18) ---
assert_file_contains "$O" 'single(-| )?pass|single productive round' "orchestrator preserves single-pass at rounds=1"

# --- locate-sinks (2026-08-06) ---
assert_file_contains "$L" 'surface-map\.json' "step3 reads surface-map.json"
assert_file_contains "$L" 'target\.md' "step3 reads target.md"
assert_file_contains "$L" 'scope-target first' "step3 actionable missing-input error"
assert_file_contains "$L" 'sinks\.json' "step3 writes sinks.json"
assert_file_contains "$L" 'sink-[0-9]|stable id' "step3 assigns stable sink ids"
assert_file_contains "$L" '[Dd]ependenc' "step3 conditionally indexes vendored dependencies"
assert_file_contains "$L" 'skip this|no.*dependency sinks' "step3 dependency indexing is conditional"
assert_file_contains "$L" 'sinks\.json — schema' "step3 carries its schema inline"
assert_file_contains "$L" 'every language|ecosystem' "step3 is language-agnostic"

summary

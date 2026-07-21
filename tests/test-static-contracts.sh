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
assert_file_contains "$O" '^name: offsec-hunter' "orchestrator frontmatter name"
assert_file_contains "$O" 'map-attack-surface' "orchestrator names step 1"
assert_file_contains "$O" 'scope-target' "orchestrator names step 2"
assert_file_contains "$O" 'raise-hypotheses' "orchestrator names step 3"
assert_file_contains "$O" 'break-hypotheses' "orchestrator names step 4"
assert_file_contains "$O" 'prove-exploit' "orchestrator names step 5"
assert_file_contains "$O" 'interactive' "orchestrator documents interactive mode"
assert_file_contains "$O" 'headless' "orchestrator documents headless mode"
assert_file_contains "$O" 'state\.json' "orchestrator references state.json"
assert_file_contains "$O" '[Tt]arget root' "orchestrator resolves target root"
assert_file_contains "$O" '[Oo]utput root' "orchestrator resolves output root"
assert_file_contains "$O" '[Ss]teer' "orchestrator documents steering"
assert_file_contains "$O" 'artifacts\.md' "orchestrator references artifacts guide by name"
assert_file_exists "skills/offsec-hunter/references/artifacts.md" "artifacts guide exists"
assert_no_cross_skill_paths "no cross-skill relative paths"

# --- map-attack-surface (Task 3) ---
M="skills/map-attack-surface/SKILL.md"
assert_file_contains "$M" '^name: map-attack-surface' "step1 frontmatter name"
assert_file_contains "$M" 'surface-map\.json' "step1 writes surface-map.json"
assert_file_contains "$M" 'rev-parse HEAD' "step1 commit-stamps freshness"
assert_file_contains "$M" 'surface-map\.md' "step1 references its schema"
assert_file_exists "skills/map-attack-surface/references/surface-map.md" "schema moved to step1"
assert_file_absent "skills/offsec-hunter/references/surface-map.md" "schema no longer under orchestrator"

# --- scope-target (Task 4) ---
S="skills/scope-target/SKILL.md"
assert_file_contains "$S" '^name: scope-target' "step2 frontmatter name"
assert_file_contains "$S" 'surface-map\.json' "step2 reads surface-map.json"
assert_file_contains "$S" 'map-attack-surface first' "step2 actionable missing-input error"
assert_file_contains "$S" 'target\.md' "step2 writes target.md"
assert_file_contains "$S" 'interactive' "step2 has interactive branch"
assert_file_contains "$S" 'headless' "step2 has headless branch"
assert_file_contains "$S" '[Aa]ttacker position' "step2 covers attacker position"
assert_file_contains "$S" '[Dd]elivery vector' "step2 covers delivery vector"
assert_file_contains "$S" '[Ww]in condition' "step2 covers win condition"

# --- raise-hypotheses (Task 5) ---
R="skills/raise-hypotheses/SKILL.md"
assert_file_contains "$R" '^name: raise-hypotheses' "step3 frontmatter name"
assert_file_contains "$R" 'target\.md' "step3 reads target.md"
assert_file_contains "$R" 'scope-target first' "step3 actionable missing-input error"
assert_file_contains "$R" 'hypotheses\.jsonl' "step3 writes hypotheses.jsonl"
assert_file_contains "$R" '[Rr]ecall' "step3 optimizes recall"
assert_file_contains "$R" '(cheap|fast)' "step3 uses cheap/fast model"

# --- break-hypotheses (Task 6) ---
B="skills/break-hypotheses/SKILL.md"
assert_file_contains "$B" '^name: break-hypotheses' "step4 frontmatter name"
assert_file_contains "$B" 'hypotheses\.jsonl' "step4 reads hypotheses.jsonl"
assert_file_contains "$B" 'raise-hypotheses first' "step4 actionable missing-input error"
assert_file_contains "$B" 'survivors\.jsonl' "step4 writes survivors.jsonl"
assert_file_contains "$B" '(break the claim|try to break)' "step4 is adversarial"
assert_file_contains "$B" '(stronger|strong)' "step4 uses a stronger model"

# --- prove-exploit (Task 7) ---
P="skills/prove-exploit/SKILL.md"
assert_file_contains "$P" '^name: prove-exploit' "step5 frontmatter name"
assert_file_contains "$P" 'survivors\.jsonl' "step5 reads survivors.jsonl"
assert_file_contains "$P" 'break-hypotheses first' "step5 actionable missing-input error"
assert_file_contains "$P" 'findings\.json' "step5 emits machine-readable findings"
assert_file_contains "$P" 'findings\.md' "step5 emits human-readable findings"
assert_file_contains "$P" 'no exploitable findings' "step5 has empty-results report"
assert_file_contains "$P" 'entry-point \+ sink' "step5 documents additive-merge dedup key"
assert_file_contains "$P" 'pocs/' "step5 writes runnable PoCs"

# --- shared-refs do not leak into step skills (all dirs now exist) ---
for d in map-attack-surface scope-target raise-hypotheses break-hypotheses prove-exploit; do
  assert_file_absent "skills/$d/references/platform-tools.md" "$d has no platform-tools.md"
  assert_file_absent "skills/$d/references/artifacts.md" "$d has no artifacts.md"
done

# --- map dependency sinks + ids (Task 3) ---
assert_file_contains "$M" 'sink-[0-9]|stable id' "step1 assigns stable sink ids"
assert_file_contains "$M" '[Dd]ependenc' "step1 conditionally indexes vendored dependencies"
assert_file_contains "$M" '[Ii]f|when|present' "step1 makes dependency indexing conditional"

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
assert_file_contains "$A" '"chain"' "artifacts documents chain field"

# --- raise round-aware + ids (Task 4) ---
assert_file_contains "$R" '"family"' "step3 tags hypotheses with a family"
assert_file_contains "$R" '"sink"' "step3 references the sink id"
assert_file_contains "$R" '[Rr]ound' "step3 is round-aware"
assert_file_contains "$R" 'output_root|inject' "step3 injects context into subagents"

# --- break chaining + trace (Task 5) ---
assert_file_contains "$B" '[Cc]hain' "step4 documents bug-chaining"
assert_file_contains "$B" '"chain"' "step4 records chain field on survivors"
assert_file_contains "$B" '"severity"' "step4 carries severity"
assert_file_contains "$B" '"confidence"' "step4 carries confidence"
assert_file_contains "$B" '[Dd]ependenc' "step4 chains dependency bugs when present"

summary

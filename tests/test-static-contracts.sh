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

summary

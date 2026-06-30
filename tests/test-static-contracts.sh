#!/usr/bin/env bash
# Tier 1 — static contract tests over the skill markdown (no LLM).
set -uo pipefail
source "$(cd "$(dirname "$0")" && pwd)/test-helpers.sh"

echo "=== Static contract tests ==="

# --- Packaging (Task 1) ---
assert_file_exists ".claude-plugin/plugin.json" "plugin manifest exists"
assert_file_contains ".claude-plugin/plugin.json" '"name"[[:space:]]*:[[:space:]]*"offsec-hunter"' "manifest names the plugin"

# (subsequent tasks append their assertion blocks below)

summary

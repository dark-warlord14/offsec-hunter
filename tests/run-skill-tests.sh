#!/usr/bin/env bash
# Entry point: run all offsec-hunter skill tests.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

bash "$SCRIPT_DIR/test-static-contracts.sh"
# Behavioral recall (Tier 2) is added in a later task and is opt-in:
if [ "${RUN_BEHAVIORAL:-0}" = "1" ]; then
  bash "$SCRIPT_DIR/test-behavioral-recall.sh"
fi

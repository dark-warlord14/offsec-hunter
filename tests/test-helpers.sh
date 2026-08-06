#!/usr/bin/env bash
# Shared assertions for static contract tests.
PASS=0
FAIL=0
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_file_exists() {
  local file="$1" label="$2"
  if [ -f "$REPO_ROOT/$file" ]; then echo "  [PASS] $label"; PASS=$((PASS+1));
  else echo "  [FAIL] $label — missing: $file"; FAIL=$((FAIL+1)); fi
}

assert_file_absent() {
  local file="$1" label="$2"
  if [ ! -e "$REPO_ROOT/$file" ]; then echo "  [PASS] $label"; PASS=$((PASS+1));
  else echo "  [FAIL] $label — should not exist: $file"; FAIL=$((FAIL+1)); fi
}

assert_file_contains() {
  local file="$1" pattern="$2" label="$3"
  if grep -Eq "$pattern" "$REPO_ROOT/$file" 2>/dev/null; then echo "  [PASS] $label"; PASS=$((PASS+1));
  else echo "  [FAIL] $label — '$pattern' not in $file"; FAIL=$((FAIL+1)); fi
}

assert_file_not_contains() {
  local file="$1" pattern="$2" label="$3"
  if grep -Eq "$pattern" "$REPO_ROOT/$file" 2>/dev/null; then echo "  [FAIL] $label — '$pattern' found in $file"; FAIL=$((FAIL+1));
  else echo "  [PASS] $label"; PASS=$((PASS+1)); fi
}

summary() {
  echo ""; echo "  ---- $PASS passed, $FAIL failed ----"
  [ "$FAIL" -eq 0 ]
}

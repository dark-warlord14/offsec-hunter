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

# Fails if more than one SKILL.md exists — offsec-hunter must be the only skill.
assert_single_skill() {
  local label="$1" count
  count="$(find "$REPO_ROOT/skills" -name SKILL.md | wc -l | tr -d ' ')"
  if [ "$count" = "1" ]; then echo "  [PASS] $label"; PASS=$((PASS+1));
  else echo "  [FAIL] $label — found $count SKILL.md files, expected 1"; FAIL=$((FAIL+1)); fi
}

# Fails if a reference file points at another file to read (references must be
# one level deep from SKILL.md, or Claude may only partially read them).
assert_references_one_level() {
  local label="$1" hits
  hits="$(grep -REn '\]\([^)]*\.md\)|read [`"'"'"']?references/' \
    "$REPO_ROOT/skills/offsec-hunter/references" 2>/dev/null || true)"
  if [ -z "$hits" ]; then echo "  [PASS] $label"; PASS=$((PASS+1));
  else echo "  [FAIL] $label — nested reference found:"; echo "$hits"; FAIL=$((FAIL+1)); fi
}

summary() {
  echo ""; echo "  ---- $PASS passed, $FAIL failed ----"
  [ "$FAIL" -eq 0 ]
}

#!/bin/bash
# Validate the local deterministic llm-wiki lint helper.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CLI="$PROJECT_ROOT/scripts/llm-wiki"
GOLDEN="$SCRIPT_DIR/fixtures/golden-wiki"
PASS=0
FAIL=0
TOTAL=0

log_pass() { PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); printf "  \033[32mPASS\033[0m: %s\n" "$1"; }
log_fail() { FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); printf "  \033[31mFAIL\033[0m: %s - %s\n" "$1" "$2"; }

expect_success() {
  local name="$1"
  shift
  local output
  if output="$("$@" 2>&1)" && grep -q "Result: PASS" <<<"$output"; then
    log_pass "$name"
  else
    log_fail "$name" "$output"
  fi
}

expect_failure_contains() {
  local name="$1"
  local expected="$2"
  shift 2
  local output
  set +e
  output="$("$@" 2>&1)"
  local rc=$?
  set -e
  if [ "$rc" -ne 0 ] && grep -q "$expected" <<<"$output"; then
    log_pass "$name"
  else
    log_fail "$name" "$output"
  fi
}

echo "=== Local llm-wiki CLI Lint ==="

if [ -x "$CLI" ]; then
  log_pass "scripts/llm-wiki is executable"
else
  log_fail "scripts/llm-wiki is executable" "missing executable bit"
fi

expect_success "golden wiki passes local lint" "$CLI" lint "$GOLDEN"

expect_failure_contains \
  "missing-index fixture fails local lint" \
  "Required _index.md is missing" \
  "$CLI" lint "$SCRIPT_DIR/fixtures/defects/missing-index"

expect_failure_contains \
  "bad-frontmatter fixture fails local lint" \
  "Invalid type" \
  "$CLI" lint "$SCRIPT_DIR/fixtures/defects/bad-frontmatter"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
mkdir "$tmpdir/wiki"
cp -R "$GOLDEN/." "$tmpdir/wiki/"
mv "$tmpdir/wiki/wiki/concepts/sample-concept.md" \
  "$tmpdir/wiki/wiki/references/sample-concept.md"

expect_failure_contains \
  "misplaced file is reported" \
  "File is in the wrong directory" \
  "$CLI" lint "$tmpdir/wiki"

set +e
fix_output="$("$CLI" lint --fix "$tmpdir/wiki" 2>&1)"
fix_rc=$?
set -e
if [ "$fix_rc" -eq 0 ] \
  && grep -q "Moved wiki/references/sample-concept.md to wiki/concepts/sample-concept.md" <<<"$fix_output" \
  && [ -f "$tmpdir/wiki/wiki/concepts/sample-concept.md" ]; then
  log_pass "--fix moves misplaced wiki files"
else
  log_fail "--fix moves misplaced wiki files" "$fix_output"
fi

echo ""
echo "==========================================="
printf "Results: \033[32m%d passed\033[0m, \033[31m%d failed\033[0m, %d total\n" "$PASS" "$FAIL" "$TOTAL"

if [ "$FAIL" -ne 0 ]; then
  exit 1
fi

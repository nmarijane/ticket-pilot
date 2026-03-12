#!/bin/bash
# Test suite for detect-tracker.sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DETECT="$SCRIPT_DIR/detect-tracker.sh"
PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "  PASS: $desc"
    ((PASS++))
  else
    echo "  FAIL: $desc (expected '$expected', got '$actual')"
    ((FAIL++))
  fi
}

assert_exit() {
  local desc="$1" expected="$2"
  shift 2
  "$DETECT" "$@" >/dev/null 2>&1
  local actual=$?
  if [[ "$actual" == "$expected" ]]; then
    echo "  PASS: $desc (exit $actual)"
    ((PASS++))
  else
    echo "  FAIL: $desc (expected exit $expected, got $actual)"
    ((FAIL++))
  fi
}

echo "=== detect-tracker.sh tests ==="

echo ""
echo "--- Output tests ---"

# GitHub patterns
assert_eq "GitHub #123" "github" "$("$DETECT" '#123')"
assert_eq "GitHub #1" "github" "$("$DETECT" '#1')"
assert_eq "GitHub owner/repo#456" "github" "$("$DETECT" 'owner/repo#456')"
assert_eq "GitHub my-org/my-repo#99" "github" "$("$DETECT" 'my-org/my-repo#99')"
assert_eq "GitHub org.name/repo-name#1" "github" "$("$DETECT" 'org.name/repo-name#1')"

# Ambiguous PREFIX-NUMBER patterns (could be Linear or Jira)
assert_eq "PREFIX-123 ambiguous" "ambiguous" "$("$DETECT" 'ENG-123')"
assert_eq "DES-42 ambiguous" "ambiguous" "$("$DETECT" 'DES-42')"
assert_eq "PROJ-1 ambiguous" "ambiguous" "$("$DETECT" 'PROJ-1')"
assert_eq "AB-999 ambiguous" "ambiguous" "$("$DETECT" 'AB-999')"
assert_eq "ABCDE-1 ambiguous (5 chars)" "ambiguous" "$("$DETECT" 'ABCDE-1')"

# Single-letter prefixes (issue #3)
assert_eq "X-123 single letter" "ambiguous" "$("$DETECT" 'X-123')"
assert_eq "A-1 single letter" "ambiguous" "$("$DETECT" 'A-1')"
assert_eq "Z-999 single letter" "ambiguous" "$("$DETECT" 'Z-999')"

# Unknown patterns
assert_eq "lowercase prefix" "unknown" "$("$DETECT" 'eng-123')"
assert_eq "no number" "unknown" "$("$DETECT" 'ENG-')"
assert_eq "just text" "unknown" "$("$DETECT" 'hello')"
assert_eq "just number" "unknown" "$("$DETECT" '123')"
assert_eq "too long prefix" "unknown" "$("$DETECT" 'ABCDEF-123')"

# Empty/missing input
assert_eq "empty string" "unknown" "$("$DETECT" '')"

echo ""
echo "--- Exit code tests ---"

assert_exit "empty input exits 1" "1" ""
assert_exit "github exits 0" "0" "#123"
assert_exit "ambiguous exits 0" "0" "ENG-123"
assert_exit "unknown format exits 0" "0" "hello"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1

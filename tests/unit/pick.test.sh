#!/bin/bash
# Unit tests for scripts/pick.sh — tracker detection and argument parsing.
# Pattern mirrors scripts/test-detect-tracker.sh.
#
# Strategy: source pick.sh minus the final `main "$@"` line so we can call
# individual functions directly without triggering the full interactive flow.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PICK="$REPO_ROOT/scripts/pick.sh"

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "  PASS: $desc"
    ((PASS++))
  else
    echo "  FAIL: $desc"
    echo "         expected : '$expected'"
    echo "         got      : '$actual'"
    ((FAIL++))
  fi
}

assert_exit() {
  local desc="$1" expected_exit="$2"
  shift 2
  actual_exit=0
  "$@" >/dev/null 2>&1 || actual_exit=$?
  if [[ "$actual_exit" == "$expected_exit" ]]; then
    echo "  PASS: $desc (exit $actual_exit)"
    ((PASS++))
  else
    echo "  FAIL: $desc (expected exit $expected_exit, got $actual_exit)"
    ((FAIL++))
  fi
}

# ---------------------------------------------------------------------------
# source_pick: source pick.sh functions without executing main.
# We strip the last line (`main "$@"`) and also strip `set -euo pipefail`
# so the test runner's error handling isn't affected.
# ---------------------------------------------------------------------------
PICK_FUNCTIONS="$(mktemp /tmp/pick_functions_XXXX.sh)"
# Remove: set -euo pipefail, main "$@", and check_deps (interactive/dep checks)
sed '/^set -euo pipefail/d; /^main "\$@"/d' "$PICK" > "$PICK_FUNCTIONS"
# Append a no-op check_deps so tests don't fail on missing gum/claude
echo 'check_deps() { :; }' >> "$PICK_FUNCTIONS"
chmod +x "$PICK_FUNCTIONS"
trap 'rm -f "$PICK_FUNCTIONS"' EXIT

# ---------------------------------------------------------------------------
echo "=== pick.sh tests ==="
echo ""
echo "--- detect_tracker: --tracker flag takes priority ---"
# ---------------------------------------------------------------------------

run_detect_flag() {
  local tracker_value="$1"
  (
    source "$PICK_FUNCTIONS"
    TRACKER="$tracker_value"
    gum() { return 1; }
    detect_tracker 2>/dev/null
  )
}

assert_eq "--tracker github"  "github"  "$(run_detect_flag github)"
assert_eq "--tracker linear"  "linear"  "$(run_detect_flag linear)"
assert_eq "--tracker jira"    "jira"    "$(run_detect_flag jira)"
assert_eq "--tracker asana"   "asana"   "$(run_detect_flag asana)"

# ---------------------------------------------------------------------------
echo ""
echo "--- detect_tracker: config file detection ---"
# ---------------------------------------------------------------------------

run_detect_config() {
  local tracker_value="$1"
  local tmp_config
  tmp_config="$(mktemp /tmp/ticket_pilot_XXXX.json)"
  printf '{"tracker":"%s"}' "$tracker_value" > "$tmp_config"
  result=$(
    source "$PICK_FUNCTIONS"
    TRACKER=""
    find_config() { echo "$tmp_config"; }
    gum() { return 1; }
    detect_tracker 2>/dev/null
  )
  rm -f "$tmp_config"
  echo "$result"
}

assert_eq "config: github" "github" "$(run_detect_config github)"
assert_eq "config: linear" "linear" "$(run_detect_config linear)"
assert_eq "config: jira"   "jira"   "$(run_detect_config jira)"
assert_eq "config: asana"  "asana"  "$(run_detect_config asana)"

# When config has empty tracker field, gum is called (returns empty → exits 0).
# Note: detect_tracker calls `exit 0` in the Cancelled branch which terminates
# the subshell before any subsequent echo runs, so we capture the exit code
# of the subshell directly.
run_detect_empty_config_exit() {
  local tmp_config
  tmp_config="$(mktemp /tmp/ticket_pilot_XXXX.json)"
  echo '{"tracker":""}' > "$tmp_config"
  (
    source "$PICK_FUNCTIONS"
    TRACKER=""
    find_config() { echo "$tmp_config"; }
    gum() { return 1; }
    detect_tracker 2>/dev/null
  )
  local exit_code=$?
  rm -f "$tmp_config"
  echo "$exit_code"
}
assert_eq "empty tracker in config: falls through to gum, exits 0" \
  "0" "$(run_detect_empty_config_exit)"

# No config and gum unavailable → exits 0 (Cancelled)
run_detect_no_config_exit() {
  (
    source "$PICK_FUNCTIONS"
    TRACKER=""
    find_config() { echo ""; }
    gum() { return 1; }
    detect_tracker 2>/dev/null
  )
  echo $?
}
assert_eq "no config, no gum: exits 0 (Cancelled)" \
  "0" "$(run_detect_no_config_exit)"

# ---------------------------------------------------------------------------
echo ""
echo "--- detect_tracker: gum interactive fallback ---"
# ---------------------------------------------------------------------------

run_detect_gum() {
  local gum_choice="$1"
  (
    source "$PICK_FUNCTIONS"
    TRACKER=""
    find_config() { echo ""; }
    gum() { echo "$gum_choice"; }
    detect_tracker 2>/dev/null
  )
}

assert_eq "gum picks github"  "github"  "$(run_detect_gum github)"
assert_eq "gum picks linear"  "linear"  "$(run_detect_gum linear)"
assert_eq "gum picks jira"    "jira"    "$(run_detect_gum jira)"
assert_eq "gum picks asana"   "asana"   "$(run_detect_gum asana)"

# ---------------------------------------------------------------------------
echo ""
echo "--- parse_args: ACTION and SCOPE ---"
# ---------------------------------------------------------------------------

run_parse() {
  (
    source "$PICK_FUNCTIONS"
    parse_args "$@" 2>/dev/null
    printf "ACTION=%s SCOPE=%s TRACKER=%s" "$ACTION" "$SCOPE" "$TRACKER"
  )
}

assert_eq "no args: defaults" \
  "ACTION= SCOPE=mine TRACKER=" \
  "$(run_parse)"

assert_eq "resolve action" \
  "ACTION=resolve SCOPE=mine TRACKER=" \
  "$(run_parse resolve)"

assert_eq "explore action" \
  "ACTION=explore SCOPE=mine TRACKER=" \
  "$(run_parse explore)"

assert_eq "triage action" \
  "ACTION=triage SCOPE=mine TRACKER=" \
  "$(run_parse triage)"

assert_eq "moderate action" \
  "ACTION=moderate SCOPE=mine TRACKER=" \
  "$(run_parse moderate)"

assert_eq "--all sets SCOPE=all" \
  "ACTION= SCOPE=all TRACKER=" \
  "$(run_parse --all)"

assert_eq "--sprint sets SCOPE=sprint" \
  "ACTION= SCOPE=sprint TRACKER=" \
  "$(run_parse --sprint)"

assert_eq "--tracker github" \
  "ACTION= SCOPE=mine TRACKER=github" \
  "$(run_parse --tracker github)"

assert_eq "--tracker asana" \
  "ACTION= SCOPE=mine TRACKER=asana" \
  "$(run_parse --tracker asana)"

assert_eq "resolve --all" \
  "ACTION=resolve SCOPE=all TRACKER=" \
  "$(run_parse resolve --all)"

assert_eq "--tracker jira triage --sprint" \
  "ACTION=triage SCOPE=sprint TRACKER=jira" \
  "$(run_parse --tracker jira triage --sprint)"

# flags can appear before action
assert_eq "--all before action" \
  "ACTION=resolve SCOPE=all TRACKER=" \
  "$(run_parse --all resolve)"

# ---------------------------------------------------------------------------
echo ""
echo "--- parse_args: unknown argument exits non-zero ---"
# ---------------------------------------------------------------------------

assert_exit "unknown arg --foo exits 1" "1" \
  bash -c "source '$PICK_FUNCTIONS' 2>/dev/null; parse_args --foo 2>/dev/null"

assert_exit "unknown action 'deploy' exits 1" "1" \
  bash -c "source '$PICK_FUNCTIONS' 2>/dev/null; parse_args deploy 2>/dev/null"

# ---------------------------------------------------------------------------
echo ""
echo "--- main: unknown tracker exits 1 ---"
# ---------------------------------------------------------------------------

unknown_tracker_exit() {
  (
    source "$PICK_FUNCTIONS"
    detect_tracker() { echo "notexist"; }
    fetch_github() { echo ""; }
    main 2>/dev/null
    echo $?
  ) 2>/dev/null
  # Capture the last exit code
  local r=$?
  echo $r
}
# main exits 1 when tracker is unknown
(
  source "$PICK_FUNCTIONS"
  TRACKER="notexist"
  detect_tracker() { echo "notexist"; }
  main 2>/dev/null
)
exit_code=$?
assert_eq "unknown tracker in main → exit 1" "1" "$exit_code"

# ---------------------------------------------------------------------------
echo ""
echo "--- find_config: walks directory tree ---"
# ---------------------------------------------------------------------------

TMP_TREE="$(mktemp -d)"
mkdir -p "$TMP_TREE/a/b/c"
mkdir -p "$TMP_TREE/a/.claude"
echo '{"tracker":"linear"}' > "$TMP_TREE/a/.claude/ticket-pilot.json"

run_find_config() {
  local start_dir="$1"
  (
    source "$PICK_FUNCTIONS"
    cd "$start_dir"
    find_config
  )
}

assert_eq "find_config: finds config 2 levels up" \
  "$TMP_TREE/a/.claude/ticket-pilot.json" \
  "$(run_find_config "$TMP_TREE/a/b/c")"

assert_eq "find_config: finds config in direct parent" \
  "$TMP_TREE/a/.claude/ticket-pilot.json" \
  "$(run_find_config "$TMP_TREE/a/b")"

assert_eq "find_config: finds config in same dir" \
  "$TMP_TREE/a/.claude/ticket-pilot.json" \
  "$(run_find_config "$TMP_TREE/a")"

# No config → returns empty
TMP_EMPTY="$(mktemp -d)"
assert_eq "find_config: returns empty when no config" \
  "" \
  "$(run_find_config "$TMP_EMPTY")"

rm -rf "$TMP_TREE" "$TMP_EMPTY"

# ---------------------------------------------------------------------------
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1

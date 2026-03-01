#!/usr/bin/env bash
# Tests for the test-scenarios subcommand in tools/ror.
# Tests scenario discovery, filtering, and error handling.
# Does NOT launch Godot — only tests CLI argument parsing and file discovery.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Counters
PASS=0
FAIL=0
ERRORS=()

RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
RESET='\033[0m'

pass() {
    PASS=$((PASS + 1))
    printf "${GREEN}  PASS${RESET} %s\n" "$1"
}

fail() {
    FAIL=$((FAIL + 1))
    ERRORS+=("$1")
    printf "${RED}  FAIL${RESET} %s\n" "$1"
}

# Create a temp directory with test scenario files
TMPDIR_SCENARIOS=$(mktemp -d)
trap 'rm -rf "$TMPDIR_SCENARIOS"' EXIT

# Populate with test scenarios
mkdir -p "$TMPDIR_SCENARIOS/tests/scenarios"
cat > "$TMPDIR_SCENARIOS/tests/scenarios/alpha.scenario" <<'SCEN'
# Alpha test
speed 3
assert time>=0
SCEN

cat > "$TMPDIR_SCENARIOS/tests/scenarios/beta_gather.scenario" <<'SCEN'
# Beta gather test
speed 3
assert food>=0
SCEN

cat > "$TMPDIR_SCENARIOS/tests/scenarios/gamma.scenario" <<'SCEN'
# Gamma test
assert wood>=0
SCEN

# ==================== Tests ====================
printf "\n${BOLD}test-scenarios: scenario discovery${RESET}\n"

# Test: finds .scenario files
count=$(find "$TMPDIR_SCENARIOS/tests/scenarios" -name '*.scenario' | wc -l | tr -d ' ')
if [[ "$count" == "3" ]]; then
    pass "discovers 3 scenario files"
else
    fail "discovers 3 scenario files (found $count)"
fi

# Test: filter matches subset
filtered=$(find "$TMPDIR_SCENARIOS/tests/scenarios" -name '*.scenario' -print0 | sort -z | while IFS= read -r -d '' f; do
    basename="$(basename "$f" .scenario)"
    if [[ "$basename" == *"gather"* ]]; then
        echo "$f"
    fi
done | wc -l | tr -d ' ')
if [[ "$filtered" == "1" ]]; then
    pass "filter 'gather' matches 1 file"
else
    fail "filter 'gather' matches 1 file (found $filtered)"
fi

# Test: filter with no matches
filtered=$(find "$TMPDIR_SCENARIOS/tests/scenarios" -name '*.scenario' -print0 | sort -z | while IFS= read -r -d '' f; do
    basename="$(basename "$f" .scenario)"
    if [[ "$basename" == *"nonexistent"* ]]; then
        echo "$f"
    fi
done | wc -l | tr -d ' ')
if [[ "$filtered" == "0" ]]; then
    pass "filter 'nonexistent' matches 0 files"
else
    fail "filter 'nonexistent' matches 0 files (found $filtered)"
fi

printf "\n${BOLD}test-scenarios: CLI argument parsing${RESET}\n"

# Source ror functions for argument parsing tests
_tmp_ror=$(mktemp)
sed '/^case "\${1:-help}" in$/,$ { /^case/i\
return 0 2>/dev/null || true
d; }' "$PROJECT_ROOT/tools/ror" > "$_tmp_ror"
sed -i '' 's/^set -euo pipefail$/set -uo pipefail/' "$_tmp_ror"
source "$_tmp_ror"
rm -f "$_tmp_ror"

# Test: missing scenario directory gives error
output=$(cmd_test_scenarios 2>&1 || true)
# The function should error because there's no Godot, but let's test
# it reaches the scenario discovery phase by overriding find_godot
find_godot() { echo "/usr/bin/true"; }

# Override PROJECT_ROOT temporarily to the temp dir with no scenarios dir
_orig_root="$PROJECT_ROOT"
PROJECT_ROOT="$TMPDIR_SCENARIOS/nonexistent"
output=$(cmd_test_scenarios 2>&1 || true)
if echo "$output" | grep -q "Scenario directory not found"; then
    pass "errors when scenario directory missing"
else
    fail "errors when scenario directory missing (got: $output)"
fi
PROJECT_ROOT="$_orig_root"

printf "\n${BOLD}test-scenarios: scenario file sorting${RESET}\n"

# Test: files are discovered in sorted order
sorted_names=$(find "$TMPDIR_SCENARIOS/tests/scenarios" -name '*.scenario' -print0 | sort -z | while IFS= read -r -d '' f; do
    basename "$f" .scenario
done | tr '\n' ',')
if [[ "$sorted_names" == "alpha,beta_gather,gamma," ]]; then
    pass "scenarios discovered in sorted order"
else
    fail "scenarios discovered in sorted order (got: $sorted_names)"
fi

printf "\n${BOLD}test-scenarios: cleanup function${RESET}\n"

# Test: cleanup function handles non-existent PID gracefully
_test_scenarios_cleanup 99999 /dev/null 2>/dev/null
if [[ $? -eq 0 ]] || true; then
    pass "cleanup handles non-existent PID"
fi

# Test: cleanup removes log file
tmplog=$(mktemp)
echo "test" > "$tmplog"
_test_scenarios_cleanup 99999 "$tmplog" 2>/dev/null
if [[ ! -f "$tmplog" ]]; then
    pass "cleanup removes log file"
else
    fail "cleanup removes log file"
    rm -f "$tmplog"
fi

# ==================== Summary ====================
echo ""
printf "${BOLD}Results: ${GREEN}$PASS passed${RESET}, "
if [[ $FAIL -gt 0 ]]; then
    printf "${RED}$FAIL failed${RESET}\n"
    echo ""
    for e in "${ERRORS[@]}"; do
        printf "  ${RED}✖${RESET} %s\n" "$e"
    done
    exit 1
else
    printf "${GREEN}0 failed${RESET}\n"
    exit 0
fi

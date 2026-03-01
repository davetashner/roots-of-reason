#!/usr/bin/env bash
# Tests for scenario assertion commands in tools/ror.
# Mocks curl to return controlled JSON responses, then exercises each assertion.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Counters
PASS=0
FAIL=0
ERRORS=()

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
RESET='\033[0m'

# --- Test helpers ---
pass() {
    PASS=$((PASS + 1))
    printf "${GREEN}  PASS${RESET} %s\n" "$1"
}

fail() {
    FAIL=$((FAIL + 1))
    ERRORS+=("$1")
    printf "${RED}  FAIL${RESET} %s\n" "$1"
}

# --- Mock curl ---
MOCK_STATUS_JSON='{}'
MOCK_ENTITIES_JSON='{"entities": []}'

curl() {
    local url=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s|-f|-sf|-fs) shift ;;
            http*) url="$1"; shift ;;
            *) shift ;;
        esac
    done

    if [[ "$url" == *"/status"* ]]; then
        echo "$MOCK_STATUS_JSON"
    elif [[ "$url" == *"/entities"* ]]; then
        # Apply server-side owner filtering like the real debug server would
        if [[ "$url" == *"owner="* ]]; then
            local owner_val
            owner_val=$(echo "$url" | sed -n 's/.*owner=\([0-9]*\).*/\1/p')
            echo "$MOCK_ENTITIES_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
data['entities'] = [e for e in data.get('entities', []) if e.get('owner_id', -1) == int('$owner_val')]
print(json.dumps(data))
"
        else
            echo "$MOCK_ENTITIES_JSON"
        fi
    else
        echo "{}"
    fi
}
export -f curl

# Source the ror functions by temporarily replacing the main case block.
# We create a modified copy that returns before the case statement.
_tmp_ror=$(mktemp)
# Copy everything up to the main case block, adding a return
sed '/^case "\${1:-help}" in$/,$ { /^case/i\
return 0 2>/dev/null || true
d; }' "$PROJECT_ROOT/tools/ror" > "$_tmp_ror"
# Remove set -e so individual assertion failures don't kill us
sed -i '' 's/^set -euo pipefail$/set -uo pipefail/' "$_tmp_ror"
# Source it — this defines all functions
source "$_tmp_ror"
rm -f "$_tmp_ror"

# ==================== assert tests ====================
printf "\n${BOLD}assert command${RESET}\n"

MOCK_STATUS_JSON='{"game_time": 50.0, "player_resources": {"food": 200, "wood": 150, "gold": 50, "stone": 25}}'

if _scenario_assert "food>=100" >/dev/null 2>&1; then
    pass "assert food>=100 with food=200"
else
    fail "assert food>=100 with food=200"
fi

if _scenario_assert "food>=300" >/dev/null 2>&1; then
    fail "assert food>=300 with food=200 should fail"
else
    pass "assert food>=300 with food=200 correctly fails"
fi

if _scenario_assert "wood>100" >/dev/null 2>&1; then
    pass "assert wood>100 with wood=150"
else
    fail "assert wood>100 with wood=150"
fi

if _scenario_assert "gold==50" >/dev/null 2>&1; then
    pass "assert gold==50 with gold=50"
else
    fail "assert gold==50 with gold=50"
fi

if _scenario_assert "time>30" >/dev/null 2>&1; then
    pass "assert time>30 with time=50"
else
    fail "assert time>30 with time=50"
fi

if _scenario_assert "stone!=0" >/dev/null 2>&1; then
    pass "assert stone!=0 with stone=25"
else
    fail "assert stone!=0 with stone=25"
fi

# idle count
MOCK_ENTITIES_JSON='{"entities": [
    {"name": "Unit_1", "owner_id": 0, "action": "idle", "entity_category": "own_unit"},
    {"name": "Unit_2", "owner_id": 0, "action": "gathering", "entity_category": "own_unit"}
]}'
if _scenario_assert "idle==1" >/dev/null 2>&1; then
    pass "assert idle==1 with 1 idle unit"
else
    fail "assert idle==1 with 1 idle unit"
fi

# error message includes actual value
output=$(_scenario_assert "food>=999" 2>&1 || true)
if echo "$output" | grep -q "actual.*food=200"; then
    pass "assert failure message includes actual value"
else
    fail "assert failure message includes actual value (got: $output)"
fi

# invalid format
if _scenario_assert "invalid" >/dev/null 2>&1; then
    fail "assert with invalid condition should fail"
else
    pass "assert rejects invalid condition format"
fi

# empty
if _scenario_assert "" >/dev/null 2>&1; then
    fail "assert with empty condition should fail"
else
    pass "assert rejects empty condition"
fi

# ==================== assert-count tests ====================
printf "\n${BOLD}assert-count command${RESET}\n"

MOCK_ENTITIES_JSON='{"entities": [
    {"name": "V1", "owner_id": 0, "entity_category": "own_unit", "unit_category": "villager", "action": "gathering"},
    {"name": "V2", "owner_id": 0, "entity_category": "own_unit", "unit_category": "villager", "action": "idle"},
    {"name": "S1", "owner_id": 0, "entity_category": "own_unit", "unit_category": "swordsman", "action": "idle"},
    {"name": "E1", "owner_id": 1, "entity_category": "enemy_unit", "unit_category": "archer", "action": "moving"}
]}'

if _scenario_assert_count ">= 4" >/dev/null 2>&1; then
    pass "assert-count >= 4 with 4 entities"
else
    fail "assert-count >= 4 with 4 entities"
fi

if _scenario_assert_count "--owner 0 >= 3" >/dev/null 2>&1; then
    pass "assert-count --owner 0 >= 3"
else
    fail "assert-count --owner 0 >= 3"
fi

if _scenario_assert_count "--owner 0 >= 10" >/dev/null 2>&1; then
    fail "assert-count --owner 0 >= 10 should fail"
else
    pass "assert-count --owner 0 >= 10 correctly fails"
fi

if _scenario_assert_count "--action idle >= 2" >/dev/null 2>&1; then
    pass "assert-count --action idle >= 2"
else
    fail "assert-count --action idle >= 2"
fi

if _scenario_assert_count "--owner 1 == 1" >/dev/null 2>&1; then
    pass "assert-count --owner 1 == 1"
else
    fail "assert-count --owner 1 == 1"
fi

if _scenario_assert_count "" >/dev/null 2>&1; then
    fail "assert-count with empty args should fail"
else
    pass "assert-count rejects empty args"
fi

# ==================== assert-no-idle tests ====================
printf "\n${BOLD}assert-no-idle command${RESET}\n"

MOCK_ENTITIES_JSON='{"entities": [
    {"name": "V1", "owner_id": 0, "entity_category": "own_unit", "unit_category": "villager", "action": "idle"},
    {"name": "V2", "owner_id": 0, "entity_category": "own_unit", "unit_category": "villager", "action": "gathering"}
]}'
if _scenario_assert_no_idle >/dev/null 2>&1; then
    fail "assert-no-idle should fail with idle units"
else
    pass "assert-no-idle correctly fails with idle units"
fi

# idle unit names in error message
output=$(_scenario_assert_no_idle 2>&1 || true)
if echo "$output" | grep -q "V1"; then
    pass "assert-no-idle error lists idle unit names"
else
    fail "assert-no-idle error lists idle unit names (got: $output)"
fi

MOCK_ENTITIES_JSON='{"entities": [
    {"name": "V1", "owner_id": 0, "entity_category": "own_unit", "unit_category": "villager", "action": "gathering"},
    {"name": "V2", "owner_id": 0, "entity_category": "own_unit", "unit_category": "villager", "action": "moving"}
]}'
if _scenario_assert_no_idle >/dev/null 2>&1; then
    pass "assert-no-idle passes when all units active"
else
    fail "assert-no-idle passes when all units active"
fi

# ==================== assert-building-at tests ====================
printf "\n${BOLD}assert-building-at command${RESET}\n"

MOCK_ENTITIES_JSON='{"entities": [
    {"name": "Building_barracks_5_4", "entity_category": "own_building", "building_name": "barracks", "grid_position": {"x": 5, "y": 4}, "hp": 800, "max_hp": 1000},
    {"name": "Building_house_10_10", "entity_category": "own_building", "building_name": "house", "grid_position": {"x": 10, "y": 10}, "hp": 500, "max_hp": 500}
]}'

if _scenario_assert_building_at "barracks 5 4" >/dev/null 2>&1; then
    pass "assert-building-at barracks 5 4"
else
    fail "assert-building-at barracks 5 4"
fi

# shows HP info on success
output=$(_scenario_assert_building_at "barracks 5 4" 2>&1 || true)
if echo "$output" | grep -q "800/1000"; then
    pass "assert-building-at shows HP info"
else
    fail "assert-building-at shows HP info (got: $output)"
fi

if _scenario_assert_building_at "barracks 1 1" >/dev/null 2>&1; then
    fail "assert-building-at barracks 1 1 should fail"
else
    pass "assert-building-at barracks 1 1 correctly fails"
fi

if _scenario_assert_building_at "castle 5 4" >/dev/null 2>&1; then
    fail "assert-building-at castle 5 4 should fail"
else
    pass "assert-building-at castle 5 4 correctly fails"
fi

if _scenario_assert_building_at "barracks 5" >/dev/null 2>&1; then
    fail "assert-building-at with missing Y should fail"
else
    pass "assert-building-at rejects missing args"
fi

# ==================== assert-entity-hp tests ====================
printf "\n${BOLD}assert-entity-hp command${RESET}\n"

MOCK_ENTITIES_JSON='{"entities": [
    {"name": "Unit_swordsman_0", "owner_id": 0, "entity_category": "own_unit", "unit_category": "swordsman", "hp": 80, "max_hp": 100, "action": "idle"},
    {"name": "Unit_archer_0", "owner_id": 0, "entity_category": "own_unit", "unit_category": "archer", "hp": 30, "max_hp": 40, "action": "moving"},
    {"name": "Unit_enemy_0", "owner_id": 1, "entity_category": "enemy_unit", "unit_category": "swordsman", "hp": 0, "max_hp": 100, "action": "idle"}
]}'

if _scenario_assert_entity_hp "--owner 0 > 0" >/dev/null 2>&1; then
    pass "assert-entity-hp --owner 0 > 0"
else
    fail "assert-entity-hp --owner 0 > 0"
fi

if _scenario_assert_entity_hp "--name Unit_swordsman_0 >= 80" >/dev/null 2>&1; then
    pass "assert-entity-hp --name Unit_swordsman_0 >= 80"
else
    fail "assert-entity-hp --name Unit_swordsman_0 >= 80"
fi

if _scenario_assert_entity_hp "--owner 0 >= 50" >/dev/null 2>&1; then
    fail "assert-entity-hp --owner 0 >= 50 should fail (archer has 30)"
else
    pass "assert-entity-hp --owner 0 >= 50 correctly fails"
fi

if _scenario_assert_entity_hp "--owner 1 == 0" >/dev/null 2>&1; then
    pass "assert-entity-hp --owner 1 == 0"
else
    fail "assert-entity-hp --owner 1 == 0"
fi

MOCK_ENTITIES_JSON='{"entities": []}'
if _scenario_assert_entity_hp "--owner 0 > 0" >/dev/null 2>&1; then
    fail "assert-entity-hp with no matches should fail"
else
    pass "assert-entity-hp correctly fails with no matching entities"
fi

if _scenario_assert_entity_hp "" >/dev/null 2>&1; then
    fail "assert-entity-hp with empty args should fail"
else
    pass "assert-entity-hp rejects empty args"
fi

# ==================== Step dispatch ====================
printf "\n${BOLD}scenario step dispatch${RESET}\n"

MOCK_STATUS_JSON='{"game_time": 100.0, "player_resources": {"food": 500, "wood": 300, "gold": 100, "stone": 50}}'
MOCK_ENTITIES_JSON='{"entities": [
    {"name": "V1", "owner_id": 0, "entity_category": "own_unit", "unit_category": "villager", "action": "gathering"}
]}'

if _run_scenario_step "assert food>=100" >/dev/null 2>&1; then
    pass "step dispatch: assert food>=100"
else
    fail "step dispatch: assert food>=100"
fi

if _run_scenario_step "assert-count --owner 0 >= 1" >/dev/null 2>&1; then
    pass "step dispatch: assert-count --owner 0 >= 1"
else
    fail "step dispatch: assert-count --owner 0 >= 1"
fi

if _run_scenario_step "assert-no-idle" >/dev/null 2>&1; then
    pass "step dispatch: assert-no-idle"
else
    fail "step dispatch: assert-no-idle"
fi

MOCK_ENTITIES_JSON='{"entities": [
    {"name": "TC", "entity_category": "own_building", "building_name": "town_center", "grid_position": {"x": 5, "y": 5}, "hp": 2400, "max_hp": 2400}
]}'
if _run_scenario_step "assert-building-at town_center 5 5" >/dev/null 2>&1; then
    pass "step dispatch: assert-building-at town_center 5 5"
else
    fail "step dispatch: assert-building-at town_center 5 5"
fi

MOCK_ENTITIES_JSON='{"entities": [
    {"name": "Unit_0", "owner_id": 0, "entity_category": "own_unit", "unit_category": "swordsman", "hp": 100, "max_hp": 100}
]}'
if _run_scenario_step "assert-entity-hp --owner 0 > 0" >/dev/null 2>&1; then
    pass "step dispatch: assert-entity-hp --owner 0 > 0"
else
    fail "step dispatch: assert-entity-hp --owner 0 > 0"
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

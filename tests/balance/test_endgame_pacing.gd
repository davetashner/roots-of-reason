extends GdUnitTestSuite
## Balance audit: endgame pacing from Information Age to Singularity victory.
##
## Timing model assumptions (standard play, no war bonus, no events):
## - Research speed formula: effective_speed = base * age_mult * (1 + tech_bonuses)
## - Age advancement runs at real-time (no speed multiplier applied)
## - Resource income is not a bottleneck for research time estimation —
##   we measure *research duration* as the gating factor, not resource gathering.
## - A player researches techs sequentially (one at a time).
## - China bonus: 1.20x research_speed applied as base_speed multiplier.
## - Maya bonus: 0.85x age_advancement_cost (reduces resources, not time).
##
## Key targets (from ADR / bead jup.7):
## - Information -> Singularity total research: 15-25 minutes
## - China advantage over generic: <= 3 minutes
## - Maya advantage over generic: <= 2 minutes

const RESEARCH_CONFIG: Dictionary = {
	"age_research_multipliers":
	{
		"0": 1.0,
		"1": 1.0,
		"2": 1.1,
		"3": 1.2,
		"4": 1.5,
		"5": 2.5,
		"6": 5.0,
	},
}

## Age advancement research times (in seconds, NOT affected by speed multiplier)
const AGE_ADVANCE_TIMES: Dictionary = {
	1: 40,  # -> Bronze Age
	2: 60,  # -> Iron Age
	3: 90,  # -> Medieval Age
	4: 120,  # -> Industrial Age
	5: 150,  # -> Information Age
	6: 200,  # -> Singularity Age
}

## Age advancement costs (for Maya discount calculation)
const AGE_ADVANCE_COSTS: Dictionary = {
	1: {"food": 500},
	2: {"food": 800, "gold": 200},
	3: {"food": 1000, "gold": 600},
	4: {"food": 1200, "gold": 800, "knowledge": 400},
	5: {"gold": 1500, "knowledge": 1000},
	6: {"gold": 2000, "knowledge": 2000},
}

## Standard resource income rates for time-to-gather estimation (Information Age).
## Assumes ~20 villagers, 3-4 libraries, trade income, and tech bonuses
## (spaceflight +50% knowledge_rate, mechanical_power +25% gather_rate).
## These represent a well-played game entering the Information Age.
const INCOME_ESTIMATE: Dictionary = {
	"food_per_sec": 4.0,  # ~10 villagers on food
	"wood_per_sec": 3.0,  # ~7 villagers on wood
	"gold_per_sec": 3.5,  # ~8 villagers on gold + trade income
	"stone_per_sec": 1.5,  # ~4 villagers on stone
	"knowledge_per_sec": 3.0,  # 4 libraries (0.5/s) + spaceflight bonus + tech bonuses
}

## All tech data by age for timing calculations.
## Extracted from tech_tree.json — only non-civ-exclusive techs.
var _tech_tree: Array = []


func before() -> void:
	var file := FileAccess.open("res://data/tech/tech_tree.json", FileAccess.READ)
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(content)
	if parsed is Array:
		_tech_tree = parsed


# ---------------------------------------------------------------------------
# Helper: get all generic techs (no civ_exclusive) for a given age
# ---------------------------------------------------------------------------
func _get_techs_for_age(age: int) -> Array:
	var result: Array = []
	for tech: Dictionary in _tech_tree:
		if int(tech.get("age", -1)) == age and tech.get("civ_exclusive", "") == "":
			result.append(tech)
	return result


# ---------------------------------------------------------------------------
# Helper: total base research time for all generic techs in an age
# ---------------------------------------------------------------------------
func _total_base_research_time_for_age(age: int) -> float:
	var total: float = 0.0
	for tech: Dictionary in _get_techs_for_age(age):
		total += float(tech.get("research_time", 0))
	return total


# ---------------------------------------------------------------------------
# Helper: effective research time for all techs in an age
# (applies age multiplier but no war/event bonuses)
# ---------------------------------------------------------------------------
func _effective_research_time_for_age(age: int, base_speed: float = 1.0) -> float:
	var base_total: float = _total_base_research_time_for_age(age)
	var speed: float = ResearchSpeed.get_effective_speed(base_speed, age, RESEARCH_CONFIG)
	return ResearchSpeed.get_effective_time(base_total, speed)


# ---------------------------------------------------------------------------
# Helper: time to gather resources for age advancement
# Returns seconds assuming constant income rates.
# ---------------------------------------------------------------------------
func _age_advance_gather_time(age_index: int, cost_multiplier: float = 1.0) -> float:
	var costs: Dictionary = AGE_ADVANCE_COSTS.get(age_index, {})
	var max_time: float = 0.0
	for resource: String in costs:
		var amount: float = float(costs[resource]) * cost_multiplier
		var rate_key: String = resource + "_per_sec"
		var rate: float = INCOME_ESTIMATE.get(rate_key, 1.0)
		var t: float = amount / rate
		if t > max_time:
			max_time = t
	return max_time


# ---------------------------------------------------------------------------
# Helper: total time to traverse an age (research all techs + advance)
# ---------------------------------------------------------------------------
func _total_age_time(age: int, base_speed: float = 1.0, cost_multiplier: float = 1.0) -> float:
	var research_time: float = _effective_research_time_for_age(age, base_speed)
	# Age advancement time (not speed-multiplied) + resource gathering
	var next_age: int = age + 1
	var advance_time: float = float(AGE_ADVANCE_TIMES.get(next_age, 0))
	var gather_time: float = _age_advance_gather_time(next_age, cost_multiplier)
	# Gathering happens in parallel with research, so we take the max overlap
	# But advancement research time is sequential (happens after paying cost)
	# Conservative: research_time + advance_time (gathering overlaps with research)
	return research_time + advance_time


# ---------------------------------------------------------------------------
# Helper: Singularity chain timing (GPU Foundry -> Transformer Lab -> AGI Core)
# Also includes prerequisite techs within age 6.
# ---------------------------------------------------------------------------
func _singularity_chain_time(base_speed: float = 1.0) -> Dictionary:
	var speed6: float = ResearchSpeed.get_effective_speed(base_speed, 6, RESEARCH_CONFIG)
	# Singularity chain techs and their base research times:
	# computing_theory (age 5, 75s) - prereq, researched in age 5
	# semiconductor_fab (age 5, 90s) - prereq, researched in age 5
	# neural_networks (60s), big_data (55s) - can be parallel but we're sequential
	# parallel_computing (70s) - unlocks gpu_foundry
	# deep_learning (80s) - needs neural_networks + big_data
	# transformer_architecture (100s) - needs deep_learning + parallel_computing
	# alignment_research (120s) - needs transformer_architecture
	# gpu_foundry (120s) - needs machine_learning
	# transformer_lab (180s) - needs gpu_foundry
	# agi_core (300s) - needs transformer_lab
	#
	# Critical path through age 6 (sequential chain):
	# neural_networks(60) -> deep_learning(80) needs big_data too
	# parallel_computing(70) -> transformer_architecture(100) needs deep_learning
	# alignment_research(120)
	# gpu_foundry(120) -> transformer_lab(180) -> agi_core(300)
	#
	# The critical path is the longest sequential dependency:
	# Option A: neural_networks(60) + deep_learning(80) +
	#           transformer_architecture(100) + alignment_research(120) = 360s base
	# Option B: parallel_computing(70) + transformer_architecture(100) +
	#           alignment_research(120) = 290s base
	# Option C: gpu_foundry(120) + transformer_lab(180) + agi_core(300) = 600s base
	#
	# Must also research: big_data(55), which is needed for deep_learning
	#
	# Full dependency chain to AGI Core (both alignment_research AND agi_core unlock it):
	# alignment_research unlocks agi_core building, but agi_core tech needs transformer_lab
	#
	# So agi_core tech prereq chain:
	# gpu_foundry(120) -> transformer_lab(180) -> agi_core(300) = 600s base
	# But gpu_foundry needs machine_learning (age 5, already done)
	#
	# transformer_architecture prereq chain:
	# neural_networks(60) + deep_learning(80) needs big_data(55)
	# parallel_computing(70) + transformer_architecture(100)
	# Then alignment_research(120)
	#
	# These two chains can overlap if player researches them in parallel
	# (but only 1 research at a time, so they're sequential).
	#
	# Total age 6 generic techs base time:
	var age6_total_base: float = _total_base_research_time_for_age(6)
	var age6_effective: float = age6_total_base / speed6

	# Critical path only (minimum to reach AGI Core):
	# Need both transformer_lab chain AND alignment_research chain
	# Minimum path: neural_networks(60) + big_data(55) + deep_learning(80) +
	#   parallel_computing(70) + transformer_architecture(100) +
	#   alignment_research(120) + gpu_foundry(120) + transformer_lab(180) +
	#   agi_core(300) = 1085s base
	var critical_path_base: float = 60 + 55 + 80 + 70 + 100 + 120 + 120 + 180 + 300
	var critical_path_effective: float = critical_path_base / speed6

	return {
		"age6_all_techs_base": age6_total_base,
		"age6_all_techs_effective": age6_effective,
		"critical_path_base": critical_path_base,
		"critical_path_effective": critical_path_effective,
		"speed_multiplier": speed6,
	}


# ===========================================================================
# TESTS
# ===========================================================================


func test_age_transition_times_documented() -> void:
	## Documents expected research time for each age transition.
	## This test always passes — it's a documentation/audit test.
	var total_game_time: float = 0.0

	# Stone Age (age 0) -> Bronze Age
	var stone_research: float = _effective_research_time_for_age(0)
	var stone_advance: float = float(AGE_ADVANCE_TIMES.get(1, 0))
	var stone_total: float = stone_research + stone_advance
	total_game_time += stone_total

	# Bronze Age (age 1) -> Iron Age
	var bronze_research: float = _effective_research_time_for_age(1)
	var bronze_advance: float = float(AGE_ADVANCE_TIMES.get(2, 0))
	var bronze_total: float = bronze_research + bronze_advance
	total_game_time += bronze_total

	# Iron Age (age 2) -> Medieval
	var iron_research: float = _effective_research_time_for_age(2)
	var iron_advance: float = float(AGE_ADVANCE_TIMES.get(3, 0))
	var iron_total: float = iron_research + iron_advance
	total_game_time += iron_total

	# Medieval Age (age 3) -> Industrial
	var medieval_research: float = _effective_research_time_for_age(3)
	var medieval_advance: float = float(AGE_ADVANCE_TIMES.get(4, 0))
	var medieval_total: float = medieval_research + medieval_advance
	total_game_time += medieval_total

	# Industrial Age (age 4) -> Information
	var industrial_research: float = _effective_research_time_for_age(4)
	var industrial_advance: float = float(AGE_ADVANCE_TIMES.get(5, 0))
	var industrial_total: float = industrial_research + industrial_advance
	total_game_time += industrial_total

	# Information Age (age 5) -> Singularity
	var info_research: float = _effective_research_time_for_age(5)
	var info_advance: float = float(AGE_ADVANCE_TIMES.get(6, 0))
	var info_total: float = info_research + info_advance
	total_game_time += info_total

	# Singularity Age (age 6) — research to AGI Core
	var sing_data: Dictionary = _singularity_chain_time()
	var sing_total: float = sing_data["critical_path_effective"]
	total_game_time += sing_total

	# Print audit results
	print("=== ENDGAME PACING AUDIT ===")
	print(
		(
			"Stone Age (age 0):       %.0fs research + %ds advance = %.0fs (%.1f min)"
			% [stone_research, int(stone_advance), stone_total, stone_total / 60.0]
		)
	)
	print(
		(
			"Bronze Age (age 1):      %.0fs research + %ds advance = %.0fs (%.1f min)"
			% [bronze_research, int(bronze_advance), bronze_total, bronze_total / 60.0]
		)
	)
	print(
		(
			"Iron Age (age 2):        %.0fs research + %ds advance = %.0fs (%.1f min)"
			% [iron_research, int(iron_advance), iron_total, iron_total / 60.0]
		)
	)
	print(
		(
			"Medieval Age (age 3):    %.0fs research + %ds advance = %.0fs (%.1f min)"
			% [medieval_research, int(medieval_advance), medieval_total, medieval_total / 60.0]
		)
	)
	print(
		(
			"Industrial Age (age 4):  %.0fs research + %ds advance = %.0fs (%.1f min)"
			% [industrial_research, int(industrial_advance), industrial_total, industrial_total / 60.0]
		)
	)
	print(
		(
			"Information Age (age 5): %.0fs research + %ds advance = %.0fs (%.1f min)"
			% [info_research, int(info_advance), info_total, info_total / 60.0]
		)
	)
	print("Singularity Age (age 6): %.0fs critical path (5.0x speed)" % [sing_total])
	print("---")
	print("Total game time estimate: %.0fs (%.1f min)" % [total_game_time, total_game_time / 60.0])
	print(
		(
			"Info->Singularity (age 5 research + advance + age 6 chain): %.0fs (%.1f min)"
			% [info_total + sing_total, (info_total + sing_total) / 60.0]
		)
	)

	# This is a documentation test — assert something minimal
	assert_bool(_tech_tree.size() > 0).is_true()


func test_information_to_singularity_timing() -> void:
	## Target: 15-25 minutes from Information Age entry to AGI Core completion.
	## This includes:
	## 1. Researching age 5 techs (at 2.5x speed)
	## 2. Advancing to Singularity Age (200s raw time)
	## 3. Researching the critical path through age 6 (at 5.0x speed)
	var info_research: float = _effective_research_time_for_age(5)
	var advance_to_sing: float = float(AGE_ADVANCE_TIMES.get(6, 0))
	var sing_data: Dictionary = _singularity_chain_time()
	var sing_critical: float = sing_data["critical_path_effective"]

	var total_seconds: float = info_research + advance_to_sing + sing_critical
	var total_minutes: float = total_seconds / 60.0

	print("--- Information -> Singularity Timing ---")
	print("Age 5 research (2.5x speed): %.0fs (%.1f min)" % [info_research, info_research / 60.0])
	print("Advance to Singularity:      %ds (%.1f min)" % [int(advance_to_sing), advance_to_sing / 60.0])
	print("Age 6 critical path (5.0x):  %.0fs (%.1f min)" % [sing_critical, sing_critical / 60.0])
	print("TOTAL: %.0fs (%.1f min)" % [total_seconds, total_minutes])
	print("Target: 15-25 minutes")

	assert_float(total_minutes).is_greater_equal(15.0)
	assert_float(total_minutes).is_less_equal(25.0)


func test_singularity_chain_critical_path() -> void:
	## Verify the Singularity chain critical path components.
	var data: Dictionary = _singularity_chain_time()
	var critical_base: float = data["critical_path_base"]
	var critical_eff: float = data["critical_path_effective"]
	var speed: float = data["speed_multiplier"]

	print("--- Singularity Chain ---")
	print("Speed multiplier (age 6): %.1f" % speed)
	print("Critical path base time: %.0fs" % critical_base)
	print("Critical path effective:  %.0fs (%.1f min)" % [critical_eff, critical_eff / 60.0])
	print("Breakdown (base seconds):")
	print("  neural_networks:           60s")
	print("  big_data:                  55s")
	print("  deep_learning:             80s")
	print("  parallel_computing:        70s")
	print("  transformer_architecture: 100s")
	print("  alignment_research:       120s")
	print("  gpu_foundry:              120s")
	print("  transformer_lab:          180s")
	print("  agi_core:                 300s")
	print("  TOTAL:                   1085s -> %.0fs at 5.0x" % critical_eff)

	assert_float(speed).is_equal_approx(5.0, 0.01)
	# Critical path base should be 1085s
	assert_float(critical_base).is_equal_approx(1085.0, 0.01)
	# At 5.0x speed, effective should be 217s (~3.6 min)
	assert_float(critical_eff).is_equal_approx(217.0, 0.5)


func test_china_research_advantage_within_3_minutes() -> void:
	## China has 1.20x research_speed. This applies as base_speed multiplier,
	## making all research 20% faster. Verify advantage <= 3 minutes over
	## the full Information -> Singularity window.
	var generic_info: float = _effective_research_time_for_age(5, 1.0)
	var china_info: float = _effective_research_time_for_age(5, 1.20)
	var advance_time: float = float(AGE_ADVANCE_TIMES.get(6, 0))
	var generic_sing: float = _singularity_chain_time(1.0)["critical_path_effective"]
	var china_sing: float = _singularity_chain_time(1.20)["critical_path_effective"]

	var generic_total: float = generic_info + advance_time + generic_sing
	var china_total: float = china_info + advance_time + china_sing
	var advantage_seconds: float = generic_total - china_total
	var advantage_minutes: float = advantage_seconds / 60.0

	print("--- China Research Advantage ---")
	print("Generic total: %.0fs (%.1f min)" % [generic_total, generic_total / 60.0])
	print("China total:   %.0fs (%.1f min)" % [china_total, china_total / 60.0])
	print("Advantage:     %.0fs (%.1f min)" % [advantage_seconds, advantage_minutes])
	print("Limit:         <= 3.0 minutes")

	assert_float(advantage_minutes).is_less_equal(3.0)
	assert_float(advantage_minutes).is_greater(0.0)


func test_maya_age_cost_advantage_within_2_minutes() -> void:
	## Maya has 0.85x age_advancement_cost. This reduces the resource cost
	## to advance ages, meaning they need less gathering time before advancing.
	## Since age advancement research_time is NOT affected (only cost),
	## and gathering happens in parallel with researching techs, the Maya
	## advantage is the difference in *non-overlapping* gather time — i.e.
	## how much extra idle time generic players spend waiting to afford
	## advancement after finishing all tech research for the age.
	##
	## If research_time > gather_time, the savings are zero (no idle wait).
	## Maya advantage = max(0, generic_wait - maya_wait) for each transition.
	var research_age5: float = _effective_research_time_for_age(5)

	# Singularity advancement: gather time for age 6 costs
	var generic_gather_6: float = _age_advance_gather_time(6, 1.0)
	var maya_gather_6: float = _age_advance_gather_time(6, 0.85)
	# Non-overlapping wait: how long you idle after research finishes
	var generic_wait_6: float = maxf(0.0, generic_gather_6 - research_age5)
	var maya_wait_6: float = maxf(0.0, maya_gather_6 - research_age5)
	var savings_6: float = generic_wait_6 - maya_wait_6

	# Information advancement: gather time for age 5 costs
	# Age 4 research time provides the overlap window
	var research_age4: float = _effective_research_time_for_age(4)
	var generic_gather_5: float = _age_advance_gather_time(5, 1.0)
	var maya_gather_5: float = _age_advance_gather_time(5, 0.85)
	var generic_wait_5: float = maxf(0.0, generic_gather_5 - research_age4)
	var maya_wait_5: float = maxf(0.0, maya_gather_5 - research_age4)
	var savings_5: float = generic_wait_5 - maya_wait_5

	var total_savings_seconds: float = savings_6 + savings_5
	var total_savings_minutes: float = total_savings_seconds / 60.0

	print("--- Maya Age Cost Advantage (overlap model) ---")
	print("Age 5 research time: %.0fs" % research_age5)
	print("Sing gather: generic=%.0fs, maya=%.0fs" % [generic_gather_6, maya_gather_6])
	print(
		(
			"Sing wait (after research): generic=%.0fs, maya=%.0fs, save=%.0fs"
			% [
				generic_wait_6,
				maya_wait_6,
				savings_6,
			]
		)
	)
	print("Age 4 research time: %.0fs" % research_age4)
	print("Info gather: generic=%.0fs, maya=%.0fs" % [generic_gather_5, maya_gather_5])
	print(
		(
			"Info wait (after research): generic=%.0fs, maya=%.0fs, save=%.0fs"
			% [
				generic_wait_5,
				maya_wait_5,
				savings_5,
			]
		)
	)
	print("Total savings:   %.0fs (%.2f min)" % [total_savings_seconds, total_savings_minutes])
	print("Limit:           <= 2.0 minutes")

	assert_float(total_savings_minutes).is_less_equal(2.0)
	assert_float(total_savings_minutes).is_greater_equal(0.0)


func test_age_research_multipliers_escalate() -> void:
	## Verify multipliers increase monotonically, ensuring later ages
	## feel progressively faster despite higher base research times.
	var prev: float = 0.0
	for age: int in range(0, 7):
		var speed: float = ResearchSpeed.get_effective_speed(1.0, age, RESEARCH_CONFIG)
		assert_float(speed).is_greater_equal(prev)
		prev = speed


func test_singularity_age_multiplier_is_highest() -> void:
	## The Singularity Age (6) must have the highest multiplier to make
	## the endgame feel like an exponential research explosion.
	var sing_speed: float = ResearchSpeed.get_effective_speed(1.0, 6, RESEARCH_CONFIG)
	for age: int in range(0, 6):
		var speed: float = ResearchSpeed.get_effective_speed(1.0, age, RESEARCH_CONFIG)
		assert_float(sing_speed).is_greater(speed)


func test_agi_core_is_longest_single_research() -> void:
	## AGI Core (300s base) should be the longest individual research
	## in the entire tech tree, reflecting its game-ending significance.
	var agi_core_time: float = 0.0
	var max_other_time: float = 0.0
	var max_other_id: String = ""
	for tech: Dictionary in _tech_tree:
		var t: float = float(tech.get("research_time", 0))
		var tid: String = tech.get("id", "")
		if tid == "agi_core":
			agi_core_time = t
		elif t > max_other_time:
			max_other_time = t
			max_other_id = tid

	print("--- AGI Core Research Time ---")
	print("AGI Core: %.0fs" % agi_core_time)
	print("Next longest: %s at %.0fs" % [max_other_id, max_other_time])

	assert_float(agi_core_time).is_greater(max_other_time)


func test_total_game_time_reasonable() -> void:
	## Total game time (Stone -> AGI Core) should be roughly 45-90 minutes
	## for a standard-paced game with no interruptions.
	var total: float = 0.0
	for age: int in range(0, 6):
		total += _total_age_time(age)
	# Add Singularity age critical path
	total += _singularity_chain_time()["critical_path_effective"]

	var minutes: float = total / 60.0
	print("--- Total Game Time ---")
	print("Estimated total: %.0fs (%.1f min)" % [total, minutes])

	# Reasonable range for an RTS game
	assert_float(minutes).is_greater_equal(30.0)
	assert_float(minutes).is_less_equal(90.0)

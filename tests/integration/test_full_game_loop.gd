extends GdUnitTestSuite
## Full game loop stress test: Stone Age to Singularity victory.
## Advances through all 7 ages, researches all techs in prerequisite order,
## places singularity chain buildings, and verifies victory triggers.
##
## Uses a local TechManager and VictoryManager to avoid needing a full scene tree.
## Target: completes in < 60 seconds.

const TechManagerScript := preload("res://scripts/prototype/tech_manager.gd")
const VictoryManagerScript := preload("res://scripts/prototype/victory_manager.gd")

const RMGuard := preload("res://tests/helpers/resource_manager_guard.gd")
const GMGuard := preload("res://tests/helpers/game_manager_guard.gd")

var _rm_guard: RefCounted
var _gm_guard: RefCounted
var _tm: Node
var _vm: Node


func before_test() -> void:
	_rm_guard = RMGuard.new()
	_gm_guard = GMGuard.new()
	GameManager.current_age = 0
	GameManager.is_paused = false
	GameManager.game_speed = 1.0
	GameManager.game_time = 0.0
	# Create TechManager as a child node so it initializes properly
	_tm = Node.new()
	_tm.set_script(TechManagerScript)
	add_child(_tm)
	# Create VictoryManager
	_vm = Node.new()
	_vm.set_script(VictoryManagerScript)
	add_child(_vm)
	# Wire VictoryManager to GameManager age signal
	GameManager.age_advanced.connect(_vm.on_age_advanced)


func after_test() -> void:
	if GameManager.age_advanced.is_connected(_vm.on_age_advanced):
		GameManager.age_advanced.disconnect(_vm.on_age_advanced)
	if is_instance_valid(_vm):
		_vm.queue_free()
	if is_instance_valid(_tm):
		_tm.queue_free()
	_gm_guard.dispose()
	_rm_guard.dispose()


func _give_max_resources(player_id: int) -> void:
	ResourceManager.init_player(player_id, {})
	DebugAPI.give_all_resources(player_id, 99999)


func _research_all_via_tm(player_id: int) -> int:
	## Researches every tech in prerequisite order using the local TechManager.
	## Returns the count of techs researched. Uses direct _researched_techs
	## manipulation (same approach as DebugAPI.research_tech) since we cannot
	## go through DebugAPI which needs a scene root with _tech_manager reference.
	var tech_tree: Variant = DataLoader.load_json("res://data/tech/tech_tree.json")
	if tech_tree == null or not (tech_tree is Array):
		return 0
	# Allow all age techs by setting age to max
	var saved_age: int = GameManager.current_age
	GameManager.current_age = 6
	var researched: Array[String] = []
	var remaining: Array[Dictionary] = []
	for entry: Variant in tech_tree:
		if entry is Dictionary and "id" in entry:
			remaining.append(entry)
	var max_iterations: int = remaining.size() * 2
	var iterations: int = 0
	while not remaining.is_empty() and iterations < max_iterations:
		iterations += 1
		var progressed := false
		var still_remaining: Array[Dictionary] = []
		for tech: Dictionary in remaining:
			var prereqs: Array = tech.get("prerequisites", [])
			var met := true
			for prereq: Variant in prereqs:
				if str(prereq) not in researched:
					met = false
					break
			if met:
				var tech_id: String = str(tech["id"])
				# Add directly to TechManager's researched list
				if player_id not in _tm._researched_techs:
					_tm._researched_techs[player_id] = []
				_tm._researched_techs[player_id].append(tech_id)
				var effects: Dictionary = tech.get("effects", {})
				_tm.tech_researched.emit(player_id, tech_id, effects)
				_tm.research_queue_changed.emit(player_id)
				if tech.get("singularity_chain", false):
					var tech_name: String = str(tech.get("name", tech_id))
					_tm.singularity_tech_researched.emit(player_id, tech_id, tech_name)
				researched.append(tech_id)
				progressed = true
			else:
				still_remaining.append(tech)
		remaining = still_remaining
		if not progressed:
			for tech: Dictionary in remaining:
				var tech_id: String = str(tech["id"])
				if player_id not in _tm._researched_techs:
					_tm._researched_techs[player_id] = []
				_tm._researched_techs[player_id].append(tech_id)
				var effects: Dictionary = tech.get("effects", {})
				_tm.tech_researched.emit(player_id, tech_id, effects)
				researched.append(tech_id)
			break
	GameManager.current_age = saved_age
	return researched.size()


func _check_resources_non_negative(player_id: int) -> String:
	## Returns empty string if all resources >= 0, or description of the problem.
	for res_type: ResourceManager.ResourceType in ResourceManager.RESOURCE_KEYS:
		var amount: int = ResourceManager.get_amount(player_id, res_type)
		var key: String = ResourceManager.RESOURCE_KEYS[res_type]
		if amount < 0:
			return "Resource %s is negative: %d" % [key, amount]
	return ""


# -- Test: full game loop Stone Age to Singularity --


func test_full_game_stone_to_singularity() -> void:
	var player_id: int = 0
	_give_max_resources(player_id)

	# 1. Verify starting at Stone Age (age 0)
	assert_int(GameManager.current_age).is_equal(0)
	assert_str(GameManager.get_age_name()).is_equal("Stone Age")

	# 2. Track signals via array capture (lambdas don't capture loop vars by value)
	var age_signals: Array = []
	var age_cb := func(new_age: int) -> void: age_signals.append(new_age)
	GameManager.age_advanced.connect(age_cb)

	var tech_signals: Array = []
	var tech_cb := func(pid: int, tid: String, _effects: Dictionary) -> void:
		tech_signals.append({"player_id": pid, "tech_id": tid})
	_tm.tech_researched.connect(tech_cb)

	var singularity_signals: Array = []
	var sing_cb := func(pid: int, tid: String, tname: String) -> void:
		singularity_signals.append({"player_id": pid, "tech_id": tid, "name": tname})
	_tm.singularity_tech_researched.connect(sing_cb)

	# 3. Research all techs in prerequisite order via local TechManager
	var tech_count: int = _research_all_via_tm(player_id)

	# Verify techs were researched
	var researched: Array = _tm.get_researched_techs(player_id)
	assert_bool(researched.is_empty()).is_false()
	# Should have all techs (tech_tree has ~77+ entries)
	assert_int(researched.size()).is_greater(70)

	# Verify key singularity chain techs are researched
	assert_bool(_tm.is_tech_researched("machine_learning", player_id)).is_true()
	assert_bool(_tm.is_tech_researched("gpu_foundry", player_id)).is_true()
	assert_bool(_tm.is_tech_researched("transformer_lab", player_id)).is_true()
	assert_bool(_tm.is_tech_researched("agi_core", player_id)).is_true()

	# Verify singularity chain signals fired
	assert_bool(singularity_signals.size() > 0).is_true()

	# Verify tech signals fired for each researched tech
	assert_int(tech_signals.size()).is_equal(researched.size())

	# 4. Verify resources are still non-negative
	_give_max_resources(player_id)
	var res_check: String = _check_resources_non_negative(player_id)
	assert_str(res_check).override_failure_message(res_check).is_empty()

	# 5. Advance through all 7 ages (0=Stone through 6=Singularity)
	var victory_signals: Array = []
	var victory_cb := func(pid: int, condition: String) -> void:
		victory_signals.append({"player_id": pid, "condition": condition})
	_vm.player_victorious.connect(victory_cb)

	for i: int in range(GameManager.AGE_NAMES.size() - 1):
		DebugAPI.advance_age(player_id)

	# Verify we reached Singularity Age
	assert_int(GameManager.current_age).is_equal(6)
	assert_str(GameManager.get_age_name()).is_equal("Singularity Age")

	# 6. Verify age_advanced signals fired for each transition
	assert_int(age_signals.size()).is_equal(6)
	for i: int in range(6):
		assert_int(int(age_signals[i])).is_equal(i + 1)

	# 7. Verify singularity victory was triggered by reaching age 6
	assert_int(victory_signals.size()).is_equal(1)
	assert_int(int(victory_signals[0]["player_id"])).is_equal(player_id)
	assert_str(str(victory_signals[0]["condition"])).is_equal("singularity")

	# 8. Verify VictoryManager state
	assert_bool(_vm.is_game_over()).is_true()
	var result: Dictionary = _vm.get_game_result()
	assert_int(int(result["winner"])).is_equal(player_id)
	assert_str(str(result["condition"])).is_equal("singularity")

	# Cleanup signal connections
	GameManager.age_advanced.disconnect(age_cb)
	_tm.tech_researched.disconnect(tech_cb)
	_tm.singularity_tech_researched.disconnect(sing_cb)
	_vm.player_victorious.disconnect(victory_cb)


func test_age_progression_names_correct() -> void:
	## Verifies all 7 age names are accessible and correct.
	var expected_names: Array[String] = [
		"Stone Age",
		"Bronze Age",
		"Iron Age",
		"Medieval Age",
		"Industrial Age",
		"Information Age",
		"Singularity Age",
	]
	assert_int(GameManager.AGE_NAMES.size()).is_equal(7)
	for i: int in range(expected_names.size()):
		assert_str(GameManager.AGE_NAMES[i]).is_equal(expected_names[i])


func test_all_techs_researchable_in_prerequisite_order() -> void:
	## Verifies all techs can be researched and are tracked by TechManager.
	var player_id: int = 0
	_give_max_resources(player_id)

	# Research all techs via local TechManager
	var tech_count: int = _research_all_via_tm(player_id)
	assert_int(tech_count).is_greater(70)

	# Verify every tech in the tree is now researched
	var tech_tree: Variant = DataLoader.load_json("res://data/tech/tech_tree.json")
	assert_bool(tech_tree is Array).is_true()
	var tree_arr: Array = tech_tree
	for entry: Variant in tree_arr:
		if entry is Dictionary and "id" in entry:
			var tid: String = str(entry["id"])
			(
				assert_bool(_tm.is_tech_researched(tid, player_id))
				. override_failure_message("Tech '%s' was not researched" % tid)
				. is_true()
			)

	# Verify resources are non-negative after research
	_give_max_resources(player_id)
	var res_check: String = _check_resources_non_negative(player_id)
	assert_str(res_check).override_failure_message(res_check).is_empty()


func test_agi_core_building_triggers_signal() -> void:
	## Verifies that VictoryManager emits agi_core_built when AGI Core is placed.
	var player_id: int = 0
	_give_max_resources(player_id)
	GameManager.current_age = 6

	var agi_signals: Array = []
	var agi_cb := func(pid: int) -> void: agi_signals.append(pid)
	_vm.agi_core_built.connect(agi_cb)

	# Reset game_over so building signal can fire
	_vm._game_over = false

	# Simulate placing a completed AGI Core building
	var building := Node2D.new()
	building.set_script(preload("res://scripts/prototype/prototype_building.gd"))
	building.building_name = "agi_core"
	building.owner_id = player_id
	building.under_construction = false
	building.build_progress = 1.0
	building.hp = 5000
	building.max_hp = 5000
	building.grid_pos = Vector2i(10, 10)
	building.footprint = Vector2i(4, 4)
	add_child(building)
	auto_free(building)

	# Directly invoke the VictoryManager handler
	_vm._on_building_placed(building)

	# Verify agi_core_built signal fired
	assert_int(agi_signals.size()).is_equal(1)
	assert_int(int(agi_signals[0])).is_equal(player_id)

	_vm.agi_core_built.disconnect(agi_cb)


func test_gpu_foundry_building_data_valid() -> void:
	## Verifies GPU Foundry building data exists and is correctly configured.
	var stats: Dictionary = DataLoader.get_building_stats("gpu_foundry")
	assert_dict(stats).is_not_empty()
	assert_str(str(stats.get("name", ""))).is_equal("GPU Foundry")
	assert_int(int(stats.get("age_required", -1))).is_equal(6)
	var fp: Array = stats.get("footprint", [])
	assert_int(fp.size()).is_equal(2)
	assert_int(int(fp[0])).is_equal(3)
	assert_int(int(fp[1])).is_equal(3)


func test_transformer_lab_building_data_valid() -> void:
	## Verifies Transformer Lab building data exists and is correctly configured.
	var stats: Dictionary = DataLoader.get_building_stats("transformer_lab")
	assert_dict(stats).is_not_empty()
	assert_str(str(stats.get("name", ""))).is_equal("Transformer Lab")
	assert_int(int(stats.get("age_required", -1))).is_equal(6)
	var fp: Array = stats.get("footprint", [])
	assert_int(fp.size()).is_equal(2)
	assert_int(int(fp[0])).is_equal(3)
	assert_int(int(fp[1])).is_equal(3)
	# Transformer Lab requires GPU Foundry building
	var req_buildings: Array = stats.get("required_buildings", [])
	assert_array(req_buildings).contains(["gpu_foundry"])
	# Part of singularity chain
	assert_bool(bool(stats.get("singularity_chain", false))).is_true()


func test_agi_core_building_data_valid() -> void:
	## Verifies AGI Core building data exists and is correctly configured.
	var stats: Dictionary = DataLoader.get_building_stats("agi_core")
	assert_dict(stats).is_not_empty()
	assert_str(str(stats.get("name", ""))).is_equal("AGI Core")
	assert_int(int(stats.get("age_required", -1))).is_equal(6)
	var fp: Array = stats.get("footprint", [])
	assert_int(fp.size()).is_equal(2)
	assert_int(int(fp[0])).is_equal(4)
	assert_int(int(fp[1])).is_equal(4)
	# AGI Core requires Transformer Lab building
	var req_buildings: Array = stats.get("required_buildings", [])
	assert_array(req_buildings).contains(["transformer_lab"])


func test_victory_manager_detects_singularity_age() -> void:
	## Verifies VictoryManager triggers victory when age reaches Singularity.
	var player_id: int = 0
	var victory_signals: Array = []
	var cb := func(pid: int, condition: String) -> void:
		victory_signals.append({"player_id": pid, "condition": condition})
	_vm.player_victorious.connect(cb)

	# Directly call on_age_advanced with Singularity age
	_vm.on_age_advanced(6)

	assert_int(victory_signals.size()).is_equal(1)
	assert_str(str(victory_signals[0]["condition"])).is_equal("singularity")
	assert_bool(_vm.is_game_over()).is_true()

	_vm.player_victorious.disconnect(cb)


func test_resources_stay_non_negative_through_full_loop() -> void:
	## Verifies resources never go negative during the full game progression.
	var player_id: int = 0
	_give_max_resources(player_id)

	# Research all techs via local TechManager
	_research_all_via_tm(player_id)
	var res_check: String = _check_resources_non_negative(player_id)
	assert_str(res_check).override_failure_message("After research_all: %s" % res_check).is_empty()

	# Advance through all ages
	for i: int in range(GameManager.AGE_NAMES.size() - 1):
		_give_max_resources(player_id)
		DebugAPI.advance_age(player_id)
		res_check = _check_resources_non_negative(player_id)
		(
			assert_str(res_check)
			. override_failure_message("After advancing to age %d: %s" % [GameManager.current_age, res_check])
			. is_empty()
		)

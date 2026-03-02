extends GdUnitTestSuite
## Full Singularity victory integration test: Stone Age to AGI Core completion.
## Validates the entire prerequisite chain: age advancement, tech research in
## dependency order, building unlock gates, building placement (GPU Foundry →
## Transformer Lab → AGI Core), and victory condition triggers.
##
## Uses ScenarioBuilder for initial setup, local TechManager + VictoryManager,
## and BuildingPlacer.is_building_unlocked() to verify prerequisite gates.
## Target: completes in < 60 seconds headless.

const ScenarioBuilder := preload("res://tests/helpers/scenario_builder.gd")
const TechManagerScript := preload("res://scripts/prototype/tech_manager.gd")
const VictoryManagerScript := preload("res://scripts/prototype/victory_manager.gd")
const PlacerScript := preload("res://scripts/prototype/building_placer.gd")
const MapScript := preload("res://scripts/prototype/prototype_map.gd")
const PathfindingScript := preload("res://scripts/prototype/pathfinding_grid.gd")
const TargetDetectorScript := preload("res://scripts/prototype/target_detector.gd")
const BuildingScript := preload("res://scripts/prototype/prototype_building.gd")
const RMGuard := preload("res://tests/helpers/resource_manager_guard.gd")
const GMGuard := preload("res://tests/helpers/game_manager_guard.gd")

var _rm_guard: RefCounted
var _gm_guard: RefCounted
var _tm: Node
var _vm: Node
var _placer: Node
var _scene: Node2D


func before_test() -> void:
	_rm_guard = RMGuard.new()
	_gm_guard = GMGuard.new()
	GameManager.current_age = 0
	GameManager.is_paused = false
	GameManager.game_speed = 1.0
	GameManager.game_time = 0.0
	# Build scene tree for BuildingPlacer
	_scene = Node2D.new()
	_scene.name = "TestScene"
	add_child(_scene)
	# Map
	var map := Node2D.new()
	map.name = "Map"
	map.set_script(MapScript)
	map._tile_grid = _build_grass_grid(30)
	_scene.add_child(map)
	# Pathfinder
	var pf := Node.new()
	pf.name = "PathfindingGrid"
	pf.set_script(PathfindingScript)
	_scene.add_child(pf)
	pf.build(30, map._tile_grid, {"grass": 1.0})
	# Target detector
	var td := Node.new()
	td.name = "TargetDetector"
	td.set_script(TargetDetectorScript)
	_scene.add_child(td)
	# Camera
	var cam := Camera2D.new()
	cam.name = "Camera"
	_scene.add_child(cam)
	# TechManager
	_tm = Node.new()
	_tm.set_script(TechManagerScript)
	_scene.add_child(_tm)
	# BuildingPlacer
	_placer = Node.new()
	_placer.name = "BuildingPlacer"
	_placer.set_script(PlacerScript)
	_scene.add_child(_placer)
	_placer.setup(cam, pf, map, td, _tm)
	# VictoryManager — wire to signals
	_vm = Node.new()
	_vm.set_script(VictoryManagerScript)
	_scene.add_child(_vm)
	GameManager.age_advanced.connect(_vm.on_age_advanced)
	_vm.setup(_placer)


func after_test() -> void:
	if GameManager.age_advanced.is_connected(_vm.on_age_advanced):
		GameManager.age_advanced.disconnect(_vm.on_age_advanced)
	if is_instance_valid(_scene):
		_scene.queue_free()
	_gm_guard.dispose()
	_rm_guard.dispose()


func _build_grass_grid(grid_size: int) -> Dictionary:
	var grid: Dictionary = {}
	for x in grid_size:
		for y in grid_size:
			grid[Vector2i(x, y)] = "grass"
	return grid


func _research_tech_via_tm(tech_id: String, player_id: int) -> void:
	## Research a single tech directly through TechManager internals.
	var tech_data: Dictionary = DataLoader.get_tech_data(tech_id)
	if tech_data.is_empty():
		return
	if player_id not in _tm._researched_techs:
		_tm._researched_techs[player_id] = []
	_tm._researched_techs[player_id].append(tech_id)
	var effects: Dictionary = tech_data.get("effects", {})
	_tm.tech_researched.emit(player_id, tech_id, effects)
	_tm.research_queue_changed.emit(player_id)
	if tech_data.get("singularity_chain", false):
		var tech_name: String = str(tech_data.get("name", tech_id))
		_tm.singularity_tech_researched.emit(player_id, tech_id, tech_name)


func _research_all_in_order(player_id: int) -> Array[String]:
	## Research all techs in prerequisite order. Returns list of researched IDs.
	var tech_tree: Variant = DataLoader.load_json("res://data/tech/tech_tree.json")
	if tech_tree == null or not (tech_tree is Array):
		return []
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
				var tid: String = str(tech["id"])
				_research_tech_via_tm(tid, player_id)
				researched.append(tid)
				progressed = true
			else:
				still_remaining.append(tech)
		remaining = still_remaining
		if not progressed:
			break
	GameManager.current_age = saved_age
	return researched


func _place_building(building_name: String, player_id: int, grid_pos: Vector2i) -> Node2D:
	## Place a fully-constructed building and register with BuildingPlacer.
	var stats: Dictionary = DataLoader.get_building_stats(building_name)
	var fp_arr: Array = stats.get("footprint", [1, 1])
	var fp := Vector2i(int(fp_arr[0]), int(fp_arr[1]))
	var building := Node2D.new()
	building.set_script(BuildingScript)
	building.name = "Building_%s_%d_%d" % [building_name, grid_pos.x, grid_pos.y]
	building.position = IsoUtils.grid_to_screen(Vector2(grid_pos))
	building.building_name = building_name
	building.footprint = fp
	building.grid_pos = grid_pos
	building.owner_id = player_id
	building.max_hp = int(stats.get("hp", 100))
	building.hp = building.max_hp
	building.under_construction = false
	building.build_progress = 1.0
	building.entity_category = "own_building" if player_id == 0 else "enemy_building"
	_scene.add_child(building)
	# Register with placer's tracking (for _check_required_buildings)
	(
		_placer
		. _placed_buildings
		. append(
			{
				"building_name": building_name,
				"grid_pos": [grid_pos.x, grid_pos.y],
				"player_id": player_id,
				"node": building,
			}
		)
	)
	# Notify VictoryManager
	_placer.building_placed.emit(building)
	return building


# -- Main integration test --


func test_singularity_victory_stone_to_agi_core() -> void:
	## Full walkthrough: Stone Age → research all techs → build singularity
	## chain buildings → advance to Singularity Age → verify victory.
	var pid: int = 0

	# 1. Setup via ScenarioBuilder
	var sb := ScenarioBuilder.new()
	(
		sb
		. with_scene_root(_scene)
		. give_resources(
			pid,
			{
				"food": 99999,
				"wood": 99999,
				"stone": 99999,
				"gold": 99999,
				"knowledge": 99999,
			}
		)
		. execute()
	)

	# Verify starting state
	assert_int(GameManager.current_age).is_equal(0)
	assert_str(GameManager.get_age_name()).is_equal("Stone Age")

	# 2. Track signals
	var victory_signals: Array = []
	var victory_cb := func(p: int, condition: String) -> void:
		victory_signals.append({"player_id": p, "condition": condition})
	_vm.player_victorious.connect(victory_cb)

	var agi_signals: Array = []
	var agi_cb := func(p: int) -> void: agi_signals.append(p)
	_vm.agi_core_built.connect(agi_cb)

	var singularity_tech_signals: Array = []
	var sing_cb := func(p: int, tid: String, tname: String) -> void:
		singularity_tech_signals.append({"player_id": p, "tech_id": tid, "name": tname})
	_tm.singularity_tech_researched.connect(sing_cb)

	# 3. Verify building unlock gates BEFORE any research
	assert_bool(_placer.is_building_unlocked("house", pid)).is_true()
	assert_bool(_placer.is_building_unlocked("farm", pid)).is_true()
	# Age-gated buildings should be locked
	assert_bool(_placer.is_building_unlocked("barracks", pid)).is_false()
	assert_bool(_placer.is_building_unlocked("gpu_foundry", pid)).is_false()
	assert_bool(_placer.is_building_unlocked("transformer_lab", pid)).is_false()
	assert_bool(_placer.is_building_unlocked("agi_core", pid)).is_false()

	# 4. Research ALL techs in prerequisite order
	var researched: Array[String] = _research_all_in_order(pid)
	assert_int(researched.size()).is_greater(70)

	# Verify key singularity chain techs were researched
	var chain_techs: Array[String] = [
		"computing_theory",
		"semiconductor_fab",
		"machine_learning",
		"neural_networks",
		"parallel_computing",
		"deep_learning",
		"transformer_architecture",
		"alignment_research",
		"gpu_foundry",
		"transformer_lab",
		"agi_core",
	]
	for tech_id: String in chain_techs:
		(
			assert_bool(_tm.is_tech_researched(tech_id, pid))
			. override_failure_message("Singularity chain tech '%s' not researched" % tech_id)
			. is_true()
		)

	# Verify singularity tech signals fired
	assert_int(singularity_tech_signals.size()).is_greater(0)

	# 5. Advance through all ages (0 → 6)
	for i: int in range(GameManager.AGE_NAMES.size() - 1):
		DebugAPI.advance_age(pid)

	assert_int(GameManager.current_age).is_equal(6)
	assert_str(GameManager.get_age_name()).is_equal("Singularity Age")

	# Victory should have triggered from age advance
	assert_int(victory_signals.size()).is_equal(1)
	assert_str(str(victory_signals[0]["condition"])).is_equal("singularity")

	# Reset game_over so we can test the building chain independently
	_vm._game_over = false
	_vm._winner = -1
	_vm._win_condition = ""
	victory_signals.clear()

	# 6. Verify singularity buildings are now unlocked
	assert_bool(_placer.is_building_unlocked("gpu_foundry", pid)).is_true()
	# transformer_lab requires gpu_foundry building — not yet placed
	assert_bool(_placer.is_building_unlocked("transformer_lab", pid)).is_false()

	# 7. Place GPU Foundry
	var gpu := _place_building("gpu_foundry", pid, Vector2i(5, 5))
	assert_bool(is_instance_valid(gpu)).is_true()

	# Now transformer_lab should be unlocked
	assert_bool(_placer.is_building_unlocked("transformer_lab", pid)).is_true()
	# agi_core still locked — needs transformer_lab building
	assert_bool(_placer.is_building_unlocked("agi_core", pid)).is_false()

	# 8. Place Transformer Lab
	var tlab := _place_building("transformer_lab", pid, Vector2i(10, 5))
	assert_bool(is_instance_valid(tlab)).is_true()

	# Now agi_core should be unlocked
	assert_bool(_placer.is_building_unlocked("agi_core", pid)).is_true()

	# 9. Place AGI Core — should trigger agi_core_built signal
	var agi := _place_building("agi_core", pid, Vector2i(15, 5))
	assert_bool(is_instance_valid(agi)).is_true()

	# Verify agi_core_built signal fired
	assert_int(agi_signals.size()).is_equal(1)
	assert_int(int(agi_signals[0])).is_equal(pid)

	# 10. Verify game state
	assert_bool(_vm.is_game_over()).is_false()

	# Cleanup signal connections
	_vm.player_victorious.disconnect(victory_cb)
	_vm.agi_core_built.disconnect(agi_cb)
	_tm.singularity_tech_researched.disconnect(sing_cb)


# -- Prerequisite chain validation tests --


func test_prerequisite_chain_gpu_foundry_blocks_transformer_lab() -> void:
	## Transformer Lab requires GPU Foundry building — verify the gate.
	var pid: int = 0
	ResourceManager.init_player(pid, {})
	DebugAPI.give_all_resources(pid, 99999)
	GameManager.current_age = 6

	# Research all techs
	_research_all_in_order(pid)

	# GPU Foundry should be unlocked (no required_buildings)
	assert_bool(_placer.is_building_unlocked("gpu_foundry", pid)).is_true()

	# Transformer Lab requires gpu_foundry building — should be blocked
	assert_bool(_placer.is_building_unlocked("transformer_lab", pid)).is_false()

	# Place GPU Foundry
	_place_building("gpu_foundry", pid, Vector2i(3, 3))

	# Now Transformer Lab should be unlocked
	assert_bool(_placer.is_building_unlocked("transformer_lab", pid)).is_true()


func test_prerequisite_chain_transformer_lab_blocks_agi_core() -> void:
	## AGI Core requires Transformer Lab building — verify the gate.
	var pid: int = 0
	ResourceManager.init_player(pid, {})
	DebugAPI.give_all_resources(pid, 99999)
	GameManager.current_age = 6

	# Research all techs
	_research_all_in_order(pid)

	# Place GPU Foundry (needed for transformer_lab)
	_place_building("gpu_foundry", pid, Vector2i(3, 3))

	# AGI Core requires transformer_lab building — should be blocked
	assert_bool(_placer.is_building_unlocked("agi_core", pid)).is_false()

	# Place Transformer Lab
	_place_building("transformer_lab", pid, Vector2i(8, 3))

	# Now AGI Core should be unlocked
	assert_bool(_placer.is_building_unlocked("agi_core", pid)).is_true()


func test_singularity_buildings_locked_before_age_six() -> void:
	## All singularity chain buildings require age 6 — verify age gate.
	var pid: int = 0
	ResourceManager.init_player(pid, {})
	DebugAPI.give_all_resources(pid, 99999)

	for age: int in range(6):
		GameManager.current_age = age
		(
			assert_bool(_placer.is_building_unlocked("gpu_foundry", pid))
			. override_failure_message("gpu_foundry should be locked at age %d" % age)
			. is_false()
		)
		(
			assert_bool(_placer.is_building_unlocked("transformer_lab", pid))
			. override_failure_message("transformer_lab should be locked at age %d" % age)
			. is_false()
		)
		(
			assert_bool(_placer.is_building_unlocked("agi_core", pid))
			. override_failure_message("agi_core should be locked at age %d" % age)
			. is_false()
		)


func test_agi_core_placement_emits_agi_core_built_signal() -> void:
	## Verify VictoryManager emits agi_core_built when a completed AGI Core is placed.
	var pid: int = 0
	ResourceManager.init_player(pid, {})
	DebugAPI.give_all_resources(pid, 99999)
	GameManager.current_age = 6

	var agi_signals: Array = []
	var agi_cb := func(p: int) -> void: agi_signals.append(p)
	_vm.agi_core_built.connect(agi_cb)

	# Research all techs and place prerequisite buildings
	_research_all_in_order(pid)
	_place_building("gpu_foundry", pid, Vector2i(3, 3))
	_place_building("transformer_lab", pid, Vector2i(8, 3))
	_place_building("agi_core", pid, Vector2i(14, 3))

	assert_int(agi_signals.size()).is_equal(1)
	assert_int(int(agi_signals[0])).is_equal(pid)

	_vm.agi_core_built.disconnect(agi_cb)


func test_tech_research_order_resolves_all_prerequisites() -> void:
	## Verify every tech in the tree can be researched with no circular deps.
	var pid: int = 0
	ResourceManager.init_player(pid, {})
	DebugAPI.give_all_resources(pid, 99999)

	var researched := _research_all_in_order(pid)

	# Every tech in the tree should be researched
	var tech_tree: Variant = DataLoader.load_json("res://data/tech/tech_tree.json")
	assert_bool(tech_tree is Array).is_true()
	var tree_arr: Array = tech_tree
	for entry: Variant in tree_arr:
		if entry is Dictionary and "id" in entry:
			var tid: String = str(entry["id"])
			(
				assert_bool(_tm.is_tech_researched(tid, pid))
				. override_failure_message("Tech '%s' was not researched" % tid)
				. is_true()
			)

	# No techs should be left unresearched
	assert_int(researched.size()).is_equal(tree_arr.size())


func test_age_advance_triggers_singularity_victory() -> void:
	## Verify that reaching Singularity Age triggers victory.
	var pid: int = 0
	ResourceManager.init_player(pid, {})

	var victory_signals: Array = []
	var cb := func(p: int, condition: String) -> void: victory_signals.append({"player_id": p, "condition": condition})
	_vm.player_victorious.connect(cb)

	# Advance to Singularity Age
	for i: int in range(6):
		DebugAPI.advance_age(pid)

	assert_int(GameManager.current_age).is_equal(6)
	assert_int(victory_signals.size()).is_equal(1)
	assert_str(str(victory_signals[0]["condition"])).is_equal("singularity")
	assert_bool(_vm.is_game_over()).is_true()

	var result: Dictionary = _vm.get_game_result()
	assert_int(int(result["winner"])).is_equal(pid)
	assert_str(str(result["condition"])).is_equal("singularity")
	assert_str(str(result["condition_label"])).is_equal("Singularity Achieved")

	_vm.player_victorious.disconnect(cb)


func test_resources_non_negative_through_singularity_chain() -> void:
	## Verify resources never go negative during the full progression.
	var pid: int = 0
	ResourceManager.init_player(pid, {})
	DebugAPI.give_all_resources(pid, 99999)

	# Research all techs
	_research_all_in_order(pid)
	_assert_resources_non_negative(pid, "after research_all")

	# Advance through all ages
	for i: int in range(6):
		DebugAPI.give_all_resources(pid, 99999)
		DebugAPI.advance_age(pid)
		_assert_resources_non_negative(pid, "after advancing to age %d" % GameManager.current_age)


func _assert_resources_non_negative(player_id: int, context: String) -> void:
	for res_type: ResourceManager.ResourceType in ResourceManager.RESOURCE_KEYS:
		var amount: int = ResourceManager.get_amount(player_id, res_type)
		var key: String = ResourceManager.RESOURCE_KEYS[res_type]
		(
			assert_int(amount)
			. override_failure_message("%s: resource %s is negative (%d)" % [context, key, amount])
			. is_greater_equal(0)
		)

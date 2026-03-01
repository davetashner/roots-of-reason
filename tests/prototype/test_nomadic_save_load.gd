extends GdUnitTestSuite
## Integration tests for nomadic start save/load round-trip.
## Verifies that all nomadic-phase state (victory grace, AI spawn_position,
## gatherer waiting, player_difficulty, resources) survives save/load.

const VictoryManagerScript := preload("res://scripts/prototype/victory_manager.gd")
const AIEconomyScript := preload("res://scripts/ai/ai_economy.gd")
const GathererComponentScript := preload("res://scripts/prototype/gatherer_component.gd")
const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")
const PopManagerScript := preload("res://scripts/prototype/population_manager.gd")
const MockMap := preload("res://tests/helpers/mock_map.gd")
const MockPathfinder := preload("res://tests/helpers/mock_pathfinder.gd")

# --- Lifecycle ---


func before_test() -> void:
	GameManager.current_age = 0
	GameManager.game_speed = 1.0
	GameManager.player_difficulty = "hard"
	GameManager.ai_difficulty = "hard"


func after_test() -> void:
	GameManager.player_difficulty = "normal"
	GameManager.ai_difficulty = "normal"


# --- Helpers ---


## Minimal mock unit for GathererComponent tests — satisfies the move_to interface.
class _MockUnit:
	extends Node2D

	var owner_id: int = 0
	var _moving: bool = false
	var _path: Array[Vector2] = []
	var _path_index: int = 0
	var _scene_root: Node = null
	var _last_move_target: Vector2 = Vector2.ZERO

	func move_to(pos: Vector2) -> void:
		_last_move_target = pos
		_moving = true


# --- Victory manager nomadic grace round-trip ---


func test_nomadic_grace_survives_save_load() -> void:
	var mgr := Node.new()
	mgr.name = "VictoryManager"
	mgr.set_script(VictoryManagerScript)
	add_child(mgr)
	auto_free(mgr)
	mgr.setup(null)
	# Register both players as nomadic
	mgr.register_nomadic_player(0)
	mgr.register_nomadic_player(1)
	# Tick down some grace time
	mgr._tick_nomadic_grace(60.0)
	var state: Dictionary = mgr.save_state()
	# Create fresh manager
	var mgr2 := Node.new()
	mgr2.name = "VictoryManager2"
	mgr2.set_script(VictoryManagerScript)
	add_child(mgr2)
	auto_free(mgr2)
	mgr2.setup(null)
	mgr2.load_state(state)
	# Both players should still have grace remaining
	assert_bool(mgr2.check_defeat(0)).is_false()
	assert_bool(mgr2.check_defeat(1)).is_false()
	# Grace should be reduced by 60s from original 300s
	var remaining_p0: float = mgr2._nomadic_players.get(0, 0.0)
	assert_float(remaining_p0).is_equal_approx(240.0, 1.0)


# --- AI economy spawn_position round-trip ---


func test_ai_economy_nomadic_state_survives_save_load() -> void:
	(
		ResourceManager
		. init_player(
			1,
			{
				ResourceManager.ResourceType.FOOD: 1000,
				ResourceManager.ResourceType.WOOD: 1000,
				ResourceManager.ResourceType.STONE: 1000,
				ResourceManager.ResourceType.GOLD: 1000,
				ResourceManager.ResourceType.KNOWLEDGE: 0,
			}
		)
	)
	var pop_mgr := Node.new()
	pop_mgr.set_script(PopManagerScript)
	add_child(pop_mgr)
	auto_free(pop_mgr)
	var ai := Node.new()
	ai.name = "AIEconomy"
	ai.set_script(AIEconomyScript)
	ai.difficulty = "hard"
	add_child(ai)
	auto_free(ai)
	ai.setup(self, pop_mgr, null, null, null)
	ai._build_planner.spawn_position = Vector2i(30, 30)
	ai._build_order_index = 0  # First step is "build town_center"
	var state: Dictionary = ai.save_state()
	# Load into fresh instance
	var ai2 := Node.new()
	ai2.name = "AIEconomy2"
	ai2.set_script(AIEconomyScript)
	ai2.difficulty = "hard"
	add_child(ai2)
	auto_free(ai2)
	ai2.load_state(state)
	# Verify spawn_position preserved
	assert_int(ai2._build_planner.spawn_position.x).is_equal(30)
	assert_int(ai2._build_planner.spawn_position.y).is_equal(30)
	# Verify difficulty preserved
	assert_str(ai2.difficulty).is_equal("hard")
	# Verify build order starts with TC build
	var first_step: Dictionary = ai2._build_order[0]
	assert_str(str(first_step.get("action", ""))).is_equal("build")
	assert_str(str(first_step.get("building", ""))).is_equal("town_center")


# --- Gatherer WAITING_FOR_DROP_OFF round-trip ---


func test_gatherer_waiting_state_survives_save_load() -> void:
	var root := Node2D.new()
	add_child(root)
	auto_free(root)
	var unit := _MockUnit.new()
	unit._scene_root = root
	root.add_child(unit)
	auto_free(unit)
	var gc := GathererComponentScript.new(unit)
	gc.gather_state = GathererComponentScript.GatherState.WAITING_FOR_DROP_OFF
	gc.gather_type = "wood"
	gc.carried_amount = 7
	gc.gather_rate_multiplier = 1.5
	gc.gather_accumulator = 0.3
	var state: Dictionary = gc.save_state()
	# Load into fresh component
	var gc2 := GathererComponentScript.new(unit)
	gc2.load_state(state)
	assert_int(gc2.gather_state).is_equal(GathererComponentScript.GatherState.WAITING_FOR_DROP_OFF)
	assert_str(gc2.gather_type).is_equal("wood")
	assert_int(gc2.carried_amount).is_equal(7)
	assert_float(gc2.gather_rate_multiplier).is_equal_approx(1.5, 0.01)
	assert_float(gc2.gather_accumulator).is_equal_approx(0.3, 0.01)


# --- Player difficulty round-trip ---


func test_player_difficulty_survives_full_round_trip() -> void:
	GameManager.player_difficulty = "expert"
	GameManager.ai_difficulty = "hard"
	var gm_state: Dictionary = GameManager.save_state()
	GameManager.player_difficulty = "normal"
	GameManager.ai_difficulty = "normal"
	GameManager.load_state(gm_state)
	assert_str(GameManager.player_difficulty).is_equal("expert")
	assert_str(GameManager.ai_difficulty).is_equal("hard")


# --- Combined nomadic state snapshot ---


func test_combined_nomadic_state_roundtrip() -> void:
	# Set up game state as if in mid-nomadic phase
	GameManager.player_difficulty = "hard"
	GameManager.ai_difficulty = "expert"
	GameManager.game_time = 120.0
	# Resources should reflect hard start (with TC cost buffer)
	ResourceManager.init_player(0, null, "hard")
	# Verify resources match hard tier
	var food: int = ResourceManager.get_amount(0, ResourceManager.ResourceType.FOOD)
	var wood: int = ResourceManager.get_amount(0, ResourceManager.ResourceType.WOOD)
	assert_int(food).is_equal(150)
	assert_int(wood).is_equal(400)
	# Save GameManager state
	var gm_state: Dictionary = GameManager.save_state()
	# Reset and restore
	GameManager.reset_game_state()
	assert_str(GameManager.player_difficulty).is_equal("normal")
	GameManager.load_state(gm_state)
	assert_str(GameManager.player_difficulty).is_equal("hard")
	assert_str(GameManager.ai_difficulty).is_equal("expert")
	assert_float(GameManager.game_time).is_equal_approx(120.0, 0.1)


# --- Start config verification ---


func test_hard_start_config_has_no_tc() -> void:
	var data: Variant = DataLoader.load_json("res://data/settings/game/start_config.json")
	assert_bool(data is Dictionary).is_true()
	var hard: Dictionary = data.get("hard", {})
	assert_bool(hard.get("pre_built_tc", true)).is_false()
	assert_int(int(hard.get("starting_houses", -1))).is_equal(0)


func test_easy_start_config_has_tc_and_houses() -> void:
	var data: Variant = DataLoader.load_json("res://data/settings/game/start_config.json")
	assert_bool(data is Dictionary).is_true()
	var easy: Dictionary = data.get("easy", {})
	assert_bool(easy.get("pre_built_tc", false)).is_true()
	assert_int(int(easy.get("starting_houses", 0))).is_equal(2)


func test_expert_start_config_has_no_tc() -> void:
	var data: Variant = DataLoader.load_json("res://data/settings/game/start_config.json")
	assert_bool(data is Dictionary).is_true()
	var expert: Dictionary = data.get("expert", {})
	assert_bool(expert.get("pre_built_tc", true)).is_false()


# --- Victory grace + TC registration clears grace ---


func test_tc_registration_clears_nomadic_grace_after_load() -> void:
	var mgr := Node.new()
	mgr.name = "VictoryManager"
	mgr.set_script(VictoryManagerScript)
	add_child(mgr)
	auto_free(mgr)
	mgr.setup(null)
	mgr.register_nomadic_player(0)
	# Save mid-grace
	var state: Dictionary = mgr.save_state()
	# Load into fresh manager
	var mgr2 := Node.new()
	mgr2.name = "VictoryManager2"
	mgr2.set_script(VictoryManagerScript)
	add_child(mgr2)
	auto_free(mgr2)
	mgr2.setup(null)
	mgr2.load_state(state)
	# Player should still be in grace
	assert_bool(mgr2.check_defeat(0)).is_false()
	# Now register a TC — should clear grace
	var mock_tc := Node2D.new()
	add_child(mock_tc)
	auto_free(mock_tc)
	mgr2.register_town_center(0, mock_tc)
	# Player should now be subject to normal defeat checks
	assert_bool(mgr2._nomadic_players.has(0)).is_false()


# --- AI places TC near spawn after load ---


func test_ai_places_tc_near_spawn_after_load() -> void:
	(
		ResourceManager
		. init_player(
			1,
			{
				ResourceManager.ResourceType.FOOD: 1000,
				ResourceManager.ResourceType.WOOD: 1000,
				ResourceManager.ResourceType.STONE: 1000,
				ResourceManager.ResourceType.GOLD: 1000,
				ResourceManager.ResourceType.KNOWLEDGE: 0,
			}
		)
	)
	var pop_mgr := Node.new()
	pop_mgr.set_script(PopManagerScript)
	add_child(pop_mgr)
	auto_free(pop_mgr)
	var map_mock := MockMap.new()
	add_child(map_mock)
	auto_free(map_mock)
	var pf_mock := MockPathfinder.new()
	add_child(pf_mock)
	auto_free(pf_mock)
	# Create original AI economy with spawn_position
	var ai := Node.new()
	ai.name = "AIEconomy"
	ai.set_script(AIEconomyScript)
	ai.difficulty = "hard"
	add_child(ai)
	auto_free(ai)
	ai.setup(self, pop_mgr, pf_mock, map_mock, null)
	ai._build_planner.spawn_position = Vector2i(15, 15)
	var state: Dictionary = ai.save_state()
	# Load into fresh AI
	var ai2 := Node.new()
	ai2.name = "AIEconomy2"
	ai2.set_script(AIEconomyScript)
	ai2.difficulty = "hard"
	add_child(ai2)
	auto_free(ai2)
	ai2.setup(self, pop_mgr, pf_mock, map_mock, null)
	ai2.load_state(state)
	# Verify spawn_position restored
	assert_int(ai2._build_planner.spawn_position.x).is_equal(15)
	assert_int(ai2._build_planner.spawn_position.y).is_equal(15)
	# AI should be able to find valid TC placement near spawn
	var pos: Vector2i = ai2._build_planner._find_valid_placement(Vector2i(3, 3), "town_center", null)
	assert_bool(pos != Vector2i(-1, -1)).is_true()
	var dist: int = absi(pos.x - 15) + absi(pos.y - 15)
	assert_int(dist).is_less(20)

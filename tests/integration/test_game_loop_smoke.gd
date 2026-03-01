extends GdUnitTestSuite
## Integration smoke test: creates lightweight units, advances time, validates state.
##
## Avoids loading prototype_main.tscn to prevent Godot 4 destructor race
## (SIGSEGV in GDScriptInstance::~GDScriptInstance) that occurs in headless CI
## when tearing down the full scene tree.  Instead, tests game loop components
## in isolation: units process frames, resources stay valid, and save_state()
## round-trips through JSON.

const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")
const FRAME_DELTA: float = 0.016  # ~60 fps
const FRAME_COUNT: int = 10


func _create_unit(
	owner: int = 0,
	pos: Vector2 = Vector2.ZERO,
	utype: String = "villager",
) -> Node2D:
	var u := Node2D.new()
	u.set_script(UnitScript)
	u.unit_type = utype
	u.owner_id = owner
	u.position = pos
	add_child(u)
	auto_free(u)
	return u


func before() -> void:
	GameManager.set_player_civilization(0, "mesopotamia")
	GameManager.set_player_civilization(1, "rome")
	# Explicit zero-resource init avoids relying on config defaults
	var zero_res: Dictionary = {}
	for rt: ResourceManager.ResourceType in ResourceManager.ResourceType.values():
		zero_res[rt] = 0
	ResourceManager.init_player(0, zero_res)
	ResourceManager.init_player(1, zero_res)
	# Seed a bit of food so resource checks are interesting
	ResourceManager.add_resource(0, ResourceManager.ResourceType.FOOD, 200)
	ResourceManager.add_resource(1, ResourceManager.ResourceType.FOOD, 200)


func after() -> void:
	GameManager.set_player_civilization(0, "")
	GameManager.set_player_civilization(1, "")
	ResourceManager.reset()


# -- Phase 1: units survive multiple _process calls without crash --


func test_units_survive_process_frames() -> void:
	var units: Array[Node2D] = []
	for i: int in 3:
		units.append(_create_unit(0, Vector2(i * 50.0, 0.0)))
	units.append(_create_unit(1, Vector2(200.0, 100.0), "infantry"))
	# Advance frames
	for _frame: int in FRAME_COUNT:
		for u: Node2D in units:
			u._process(FRAME_DELTA)
	# All units still valid
	for u: Node2D in units:
		assert_bool(is_instance_valid(u)).is_true()


# -- Phase 2: resources are valid after frame ticks --


func test_resources_valid_after_frames() -> void:
	var u := _create_unit()
	for _frame: int in FRAME_COUNT:
		u._process(FRAME_DELTA)
	var issues: String = _check_resources(0)
	assert_str(issues).override_failure_message(issues).is_empty()


# -- Phase 3: unit save_state round-trips through JSON --


func test_unit_save_state_round_trip() -> void:
	var u := _create_unit(0, Vector2(42.0, 99.0))
	u.hp = 80
	u.max_hp = 100
	# Tick a few frames so internal state advances
	for _frame: int in FRAME_COUNT:
		u._process(FRAME_DELTA)
	var save_data: Dictionary = u.save_state()
	assert_bool(save_data.is_empty()).is_false()
	var json_str: String = JSON.stringify(save_data)
	assert_bool(json_str.is_empty()).is_false()
	var parsed: Variant = JSON.parse_string(json_str)
	assert_bool(parsed is Dictionary).is_true()
	# Verify key fields survived the round-trip
	var d: Dictionary = parsed as Dictionary
	assert_float(float(d.get("position_x", 0))).is_equal_approx(42.0, 0.1)
	assert_float(float(d.get("position_y", 0))).is_equal_approx(99.0, 0.1)


# -- Phase 4: second simulation pass stays stable --


func test_stable_after_second_simulation_pass() -> void:
	var u := _create_unit()
	# First pass
	for _frame: int in FRAME_COUNT:
		u._process(FRAME_DELTA)
	# Second pass
	for _frame: int in FRAME_COUNT:
		u._process(FRAME_DELTA)
	assert_bool(is_instance_valid(u)).is_true()
	var issues: String = _check_resources(0)
	assert_str(issues).override_failure_message("After second pass: %s" % issues).is_empty()


# -- Helpers --


func _check_resources(player_id: int) -> String:
	## Returns empty string if all resources are valid, or a description of the
	## first problem found.
	for res_type: ResourceManager.ResourceType in ResourceManager.RESOURCE_KEYS:
		var amount: int = ResourceManager.get_amount(player_id, res_type)
		var key: String = ResourceManager.RESOURCE_KEYS[res_type]
		if is_nan(float(amount)):
			return "Resource %s is NaN" % key
		if amount < 0:
			return "Resource %s is negative: %d" % [key, amount]
	return ""

extends GdUnitTestSuite
## Tests for the idle villager finder — round-robin cycling and idle count badge.

const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")
const IdleVillagerFinderScript := preload("res://scripts/prototype/idle_villager_finder.gd")


func _create_villager(pos: Vector2 = Vector2.ZERO, idle: bool = true) -> Node2D:
	var unit := Node2D.new()
	unit.set_script(UnitScript)
	unit.unit_type = "villager"
	unit.owner_id = 0
	unit.hp = 25
	unit.max_hp = 25
	unit.position = pos
	add_child(unit)
	unit._scene_root = self
	if not idle:
		unit.move_to(Vector2(9999, 9999))
	auto_free(unit)
	return unit


func _create_military(pos: Vector2 = Vector2.ZERO) -> Node2D:
	var unit := Node2D.new()
	unit.set_script(UnitScript)
	unit.unit_type = "archer"
	unit.owner_id = 0
	unit.hp = 30
	unit.max_hp = 30
	unit.position = pos
	add_child(unit)
	unit._scene_root = self
	auto_free(unit)
	return unit


# -- Idle count tests --


func test_idle_count_with_all_idle() -> void:
	var units: Array[Node] = []
	var v1 := _create_villager(Vector2(100, 100))
	var v2 := _create_villager(Vector2(200, 100))
	var v3 := _create_villager(Vector2(300, 100))
	units.append(v1)
	units.append(v2)
	units.append(v3)

	var finder := IdleVillagerFinderScript.new()
	finder.setup(units)

	assert_int(finder.get_idle_count()).is_equal(3)


func test_idle_count_excludes_busy_villagers() -> void:
	var units: Array[Node] = []
	var v1 := _create_villager(Vector2(100, 100), true)
	var v2 := _create_villager(Vector2(200, 100), false)  # moving
	units.append(v1)
	units.append(v2)

	var finder := IdleVillagerFinderScript.new()
	finder.setup(units)

	assert_int(finder.get_idle_count()).is_equal(1)


func test_idle_count_excludes_non_villagers() -> void:
	var units: Array[Node] = []
	var v1 := _create_villager(Vector2(100, 100))
	var archer := _create_military(Vector2(200, 100))
	units.append(v1)
	units.append(archer)

	var finder := IdleVillagerFinderScript.new()
	finder.setup(units)

	assert_int(finder.get_idle_count()).is_equal(1)


func test_idle_count_excludes_enemy_villagers() -> void:
	var units: Array[Node] = []
	var v1 := _create_villager(Vector2(100, 100))
	var enemy := _create_villager(Vector2(200, 100))
	enemy.owner_id = 1
	units.append(v1)
	units.append(enemy)

	var finder := IdleVillagerFinderScript.new()
	finder.setup(units)

	assert_int(finder.get_idle_count()).is_equal(1)


func test_idle_count_zero_when_all_busy() -> void:
	var units: Array[Node] = []
	var v1 := _create_villager(Vector2(100, 100), false)
	var v2 := _create_villager(Vector2(200, 100), false)
	units.append(v1)
	units.append(v2)

	var finder := IdleVillagerFinderScript.new()
	finder.setup(units)

	assert_int(finder.get_idle_count()).is_equal(0)


# -- Cycle tests --


func test_cycle_returns_first_idle_villager() -> void:
	var units: Array[Node] = []
	var v1 := _create_villager(Vector2(100, 100))
	var v2 := _create_villager(Vector2(200, 100))
	units.append(v1)
	units.append(v2)

	var finder := IdleVillagerFinderScript.new()
	finder.setup(units)

	var first: Node = finder.cycle_next()
	assert_object(first).is_not_null()
	assert_object(first).is_same(v1)


func test_cycle_round_robin() -> void:
	var units: Array[Node] = []
	var v1 := _create_villager(Vector2(100, 100))
	var v2 := _create_villager(Vector2(200, 100))
	var v3 := _create_villager(Vector2(300, 100))
	units.append(v1)
	units.append(v2)
	units.append(v3)

	var finder := IdleVillagerFinderScript.new()
	finder.setup(units)

	var first: Node = finder.cycle_next()
	var second: Node = finder.cycle_next()
	var third: Node = finder.cycle_next()
	var wrapped: Node = finder.cycle_next()

	assert_object(first).is_same(v1)
	assert_object(second).is_same(v2)
	assert_object(third).is_same(v3)
	assert_object(wrapped).is_same(v1)


func test_cycle_returns_null_when_no_idle() -> void:
	var units: Array[Node] = []
	var v1 := _create_villager(Vector2(100, 100), false)
	units.append(v1)

	var finder := IdleVillagerFinderScript.new()
	finder.setup(units)

	var result: Node = finder.cycle_next()
	assert_object(result).is_null()


func test_cycle_skips_busy_villager() -> void:
	var units: Array[Node] = []
	var v1 := _create_villager(Vector2(100, 100), true)
	var v2 := _create_villager(Vector2(200, 100), false)  # busy
	var v3 := _create_villager(Vector2(300, 100), true)
	units.append(v1)
	units.append(v2)
	units.append(v3)

	var finder := IdleVillagerFinderScript.new()
	finder.setup(units)

	var first: Node = finder.cycle_next()
	var second: Node = finder.cycle_next()
	var wrapped: Node = finder.cycle_next()

	assert_object(first).is_same(v1)
	assert_object(second).is_same(v3)
	assert_object(wrapped).is_same(v1)


func test_cycle_wraps_when_index_exceeds_shrunk_list() -> void:
	var units: Array[Node] = []
	var v1 := _create_villager(Vector2(100, 100))
	var v2 := _create_villager(Vector2(200, 100))
	var v3 := _create_villager(Vector2(300, 100))
	units.append(v1)
	units.append(v2)
	units.append(v3)

	var finder := IdleVillagerFinderScript.new()
	finder.setup(units)

	# Cycle to v3 (index 2)
	finder.cycle_next()
	finder.cycle_next()
	finder.cycle_next()

	# Now make v2 and v3 busy — only v1 remains idle
	v2.move_to(Vector2(9999, 9999))
	v3.move_to(Vector2(9999, 9999))

	# Next cycle should wrap to v1
	var result: Node = finder.cycle_next()
	assert_object(result).is_same(v1)


func test_reset_cycle_starts_from_beginning() -> void:
	var units: Array[Node] = []
	var v1 := _create_villager(Vector2(100, 100))
	var v2 := _create_villager(Vector2(200, 100))
	units.append(v1)
	units.append(v2)

	var finder := IdleVillagerFinderScript.new()
	finder.setup(units)

	finder.cycle_next()  # v1
	finder.cycle_next()  # v2
	finder.reset_cycle()

	var result: Node = finder.cycle_next()
	assert_object(result).is_same(v1)

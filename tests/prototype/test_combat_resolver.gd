extends GdUnitTestSuite
## Tests for CombatResolver — pure-function combat resolution logic.

var _mock_script: GDScript
var _combat_config: Dictionary = {
	"building_damage_reduction": 0.80,
	"armor_effectiveness":
	{
		"melee": {"none": 1.0, "light": 1.0, "heavy": 0.75, "siege": 1.5},
		"ranged": {"none": 1.0, "light": 1.2, "heavy": 0.5, "siege": 1.0},
		"siege": {"none": 1.0, "light": 1.0, "heavy": 1.0, "siege": 0.5},
	},
}


func before() -> void:
	_mock_script = GDScript.new()
	_mock_script.source_code = ('extends Node2D\nvar unit_category: String = ""\nvar owner_id: int = 0\n')
	_mock_script.reload()


func _make_stats(overrides: Dictionary = {}) -> Dictionary:
	var base: Dictionary = {
		"attack": 10,
		"defense": 2,
		"range": 0,
		"min_range": 0,
		"bonus_vs": {},
		"unit_category": "military",
		"unit_type": "infantry",
		"attack_type": "melee",
	}
	for key in overrides:
		base[key] = overrides[key]
	return base


func _make_mock_entity(category: String, owner: int = 1) -> Node2D:
	var node := Node2D.new()
	node.set_script(_mock_script)
	node.unit_category = category
	node.owner_id = owner
	return auto_free(node)


# -- calculate_damage --


func test_basic_damage_calculation() -> void:
	var attacker := _make_stats({"attack": 10, "defense": 0})
	var defender := _make_stats({"attack": 0, "defense": 2})
	var dmg := CombatResolver.calculate_damage(attacker, defender, _combat_config)
	assert_int(dmg).is_equal(8)


func test_minimum_damage_is_one() -> void:
	var attacker := _make_stats({"attack": 1})
	var defender := _make_stats({"defense": 10})
	var dmg := CombatResolver.calculate_damage(attacker, defender, _combat_config)
	assert_int(dmg).is_equal(1)


func test_bonus_vs_multiplier() -> void:
	var attacker := _make_stats(
		{
			"attack": 10,
			"bonus_vs": {"archer": 1.5},
		}
	)
	var defender := _make_stats(
		{
			"defense": 2,
			"unit_type": "archer",
		}
	)
	var dmg := CombatResolver.calculate_damage(attacker, defender, _combat_config)
	# (10 - 2) * 1.5 = 12
	assert_int(dmg).is_equal(12)


func test_bonus_vs_category() -> void:
	var attacker := _make_stats(
		{
			"attack": 40,
			"bonus_vs": {"building": 5.0},
			"building_damage_ignore_reduction": 0.80,
		}
	)
	var defender := _make_stats(
		{
			"defense": 3,
			"unit_category": "building",
			"unit_type": "siege_workshop",
		}
	)
	var dmg := CombatResolver.calculate_damage(attacker, defender, _combat_config)
	# (40 - 3) * 5.0 = 185; building reduction: 185 * (1.0 - 0.80 + 0.80) = 185
	assert_int(dmg).is_equal(185)


func test_building_damage_reduction() -> void:
	var attacker := _make_stats({"attack": 10})
	var defender := _make_stats(
		{
			"defense": 2,
			"unit_category": "building",
		}
	)
	var dmg := CombatResolver.calculate_damage(attacker, defender, _combat_config)
	# (10 - 2) * 1.0 * (1.0 - 0.80 + 0.0) = 8 * 0.2 = 1.6 -> int(1.6) = 1
	assert_int(dmg).is_equal(1)


func test_siege_ignores_building_reduction() -> void:
	var attacker := _make_stats(
		{
			"attack": 40,
			"defense": 0,
			"building_damage_ignore_reduction": 0.80,
		}
	)
	var defender := _make_stats(
		{
			"defense": 3,
			"unit_category": "building",
		}
	)
	var dmg := CombatResolver.calculate_damage(attacker, defender, _combat_config)
	# (40 - 3) * 1.0 * (1.0 - 0.80 + 0.80) = 37 * 1.0 = 37
	assert_int(dmg).is_equal(37)


func test_zero_attack_does_minimum_damage() -> void:
	var attacker := _make_stats({"attack": 0})
	var defender := _make_stats({"defense": 5})
	var dmg := CombatResolver.calculate_damage(attacker, defender, _combat_config)
	assert_int(dmg).is_equal(1)


# -- is_in_range --


func test_is_in_range_melee_adjacent() -> void:
	var result := CombatResolver.is_in_range(Vector2i(5, 5), Vector2i(6, 5), 0)
	assert_bool(result).is_true()


func test_is_in_range_melee_not_adjacent() -> void:
	var result := CombatResolver.is_in_range(Vector2i(5, 5), Vector2i(7, 5), 0)
	assert_bool(result).is_false()


func test_is_in_range_ranged() -> void:
	var result := CombatResolver.is_in_range(Vector2i(0, 0), Vector2i(4, 0), 5)
	assert_bool(result).is_true()


func test_is_in_range_ranged_too_far() -> void:
	var result := CombatResolver.is_in_range(Vector2i(0, 0), Vector2i(6, 0), 5)
	assert_bool(result).is_false()


# -- is_beyond_min_range --


func test_is_beyond_min_range_true() -> void:
	var result := CombatResolver.is_beyond_min_range(Vector2i(0, 0), Vector2i(3, 0), 2)
	assert_bool(result).is_true()


func test_is_beyond_min_range_false() -> void:
	var result := CombatResolver.is_beyond_min_range(Vector2i(0, 0), Vector2i(1, 0), 2)
	assert_bool(result).is_false()


func test_is_beyond_min_range_zero() -> void:
	var result := CombatResolver.is_beyond_min_range(Vector2i(0, 0), Vector2i(0, 0), 0)
	assert_bool(result).is_true()


# -- is_hostile --


func test_is_hostile_different_owners() -> void:
	var a := _make_mock_entity("military", 0)
	var b := _make_mock_entity("military", 1)
	assert_bool(CombatResolver.is_hostile(a, b)).is_true()


func test_is_hostile_same_owner() -> void:
	var a := _make_mock_entity("military", 1)
	var b := _make_mock_entity("military", 1)
	assert_bool(CombatResolver.is_hostile(a, b)).is_false()


func test_is_hostile_gaia_vs_player() -> void:
	var gaia := _make_mock_entity("fauna", -1)
	var player := _make_mock_entity("military", 0)
	assert_bool(CombatResolver.is_hostile(gaia, player)).is_true()


func test_is_hostile_gaia_vs_ai() -> void:
	var gaia := _make_mock_entity("fauna", -1)
	var ai := _make_mock_entity("military", 1)
	assert_bool(CombatResolver.is_hostile(gaia, ai)).is_true()


func test_is_hostile_gaia_vs_gaia() -> void:
	var a := _make_mock_entity("fauna", -1)
	var b := _make_mock_entity("fauna", -1)
	assert_bool(CombatResolver.is_hostile(a, b)).is_false()


func test_is_hostile_player_vs_ai_unchanged() -> void:
	var a := _make_mock_entity("military", 0)
	var b := _make_mock_entity("military", 1)
	assert_bool(CombatResolver.is_hostile(a, b)).is_true()


# -- sort_targets_by_priority --


func test_sort_targets_melee_priority() -> void:
	var priority := {"melee": ["military", "civilian", "building"]}
	var civ := _make_mock_entity("civilian")
	var mil := _make_mock_entity("military")
	var bld := _make_mock_entity("building")
	var result := CombatResolver.sort_targets_by_priority([bld, civ, mil], "melee", priority)
	assert_str(result[0].unit_category).is_equal("military")
	assert_str(result[1].unit_category).is_equal("civilian")
	assert_str(result[2].unit_category).is_equal("building")


func test_sort_targets_siege_priority() -> void:
	var priority := {"siege": ["building", "military", "civilian"]}
	var civ := _make_mock_entity("civilian")
	var mil := _make_mock_entity("military")
	var bld := _make_mock_entity("building")
	var result := CombatResolver.sort_targets_by_priority([civ, mil, bld], "siege", priority)
	assert_str(result[0].unit_category).is_equal("building")
	assert_str(result[1].unit_category).is_equal("military")
	assert_str(result[2].unit_category).is_equal("civilian")


# -- armor_effectiveness --


func test_armor_effectiveness_melee_vs_heavy() -> void:
	var attacker := _make_stats({"attack": 10, "attack_type": "melee"})
	var defender := _make_stats({"defense": 2, "armor_type": "heavy"})
	var dmg := CombatResolver.calculate_damage(attacker, defender, _combat_config)
	# (10 - 2) * 1.0 bonus * 0.75 armor = 6
	assert_int(dmg).is_equal(6)


func test_armor_effectiveness_ranged_vs_light() -> void:
	var attacker := _make_stats({"attack": 10, "attack_type": "ranged"})
	var defender := _make_stats({"defense": 2, "armor_type": "light"})
	var dmg := CombatResolver.calculate_damage(attacker, defender, _combat_config)
	# (10 - 2) * 1.0 bonus * 1.2 armor = 9.6 -> 9
	assert_int(dmg).is_equal(9)


func test_armor_effectiveness_ranged_vs_heavy() -> void:
	var attacker := _make_stats({"attack": 10, "attack_type": "ranged"})
	var defender := _make_stats({"defense": 2, "armor_type": "heavy"})
	var dmg := CombatResolver.calculate_damage(attacker, defender, _combat_config)
	# (10 - 2) * 1.0 bonus * 0.5 armor = 4
	assert_int(dmg).is_equal(4)


func test_armor_effectiveness_siege_vs_siege() -> void:
	var attacker := _make_stats({"attack": 20, "attack_type": "siege"})
	var defender := _make_stats({"defense": 2, "armor_type": "siege"})
	var dmg := CombatResolver.calculate_damage(attacker, defender, _combat_config)
	# (20 - 2) * 1.0 bonus * 0.5 armor = 9
	assert_int(dmg).is_equal(9)


func test_armor_effectiveness_missing_defaults_to_one() -> void:
	var attacker := _make_stats({"attack": 10, "attack_type": "melee"})
	var defender := _make_stats({"defense": 2, "armor_type": "unknown_type"})
	var dmg := CombatResolver.calculate_damage(attacker, defender, _combat_config)
	# (10 - 2) * 1.0 bonus * 1.0 default = 8
	assert_int(dmg).is_equal(8)


func test_armor_effectiveness_stacks_with_bonus_vs() -> void:
	var attacker := _make_stats(
		{
			"attack": 10,
			"attack_type": "melee",
			"bonus_vs": {"archer": 1.5},
		}
	)
	var defender := _make_stats(
		{
			"defense": 2,
			"unit_type": "archer",
			"armor_type": "heavy",
		}
	)
	var dmg := CombatResolver.calculate_damage(attacker, defender, _combat_config)
	# (10 - 2) * 1.5 bonus * 0.75 armor = 9
	assert_int(dmg).is_equal(9)

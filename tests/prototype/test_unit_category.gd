extends GdUnitTestSuite
## Tests for UnitCategory — command availability, capability checks, bonus damage.

# -- Command availability --


func test_villager_commands_include_gather_build() -> void:
	var data := {"unit_category": "civilian", "attack": 3}
	var cmds := UnitCategory.get_available_commands(data)
	assert_bool(cmds.has("gather")).is_true()
	assert_bool(cmds.has("build")).is_true()
	assert_bool(cmds.has("repair")).is_true()
	assert_bool(cmds.has("move")).is_true()
	assert_bool(cmds.has("stop")).is_true()


func test_infantry_commands_include_attack() -> void:
	var data := {"unit_category": "military", "attack": 6, "attack_type": "melee"}
	var cmds := UnitCategory.get_available_commands(data)
	assert_bool(cmds.has("attack")).is_true()
	assert_bool(cmds.has("patrol")).is_true()
	assert_bool(cmds.has("garrison")).is_true()
	assert_bool(cmds.has("gather")).is_false()


func test_archer_commands_include_stand_ground() -> void:
	var data := {"unit_category": "military", "attack": 5, "attack_type": "ranged"}
	var cmds := UnitCategory.get_available_commands(data)
	assert_bool(cmds.has("stand_ground")).is_true()
	assert_bool(cmds.has("attack")).is_true()


func test_melee_military_no_stand_ground() -> void:
	var data := {"unit_category": "military", "attack": 6, "attack_type": "melee"}
	var cmds := UnitCategory.get_available_commands(data)
	assert_bool(cmds.has("stand_ground")).is_false()


func test_naval_commands_include_transport() -> void:
	var data := {
		"unit_category": "military",
		"attack": 8,
		"attack_type": "ranged",
		"movement_type": "water",
	}
	var cmds := UnitCategory.get_available_commands(data)
	assert_bool(cmds.has("transport")).is_true()


func test_land_unit_no_transport() -> void:
	var data := {"unit_category": "military", "attack": 6, "movement_type": "land"}
	var cmds := UnitCategory.get_available_commands(data)
	assert_bool(cmds.has("transport")).is_false()


# -- Capability checks --


func test_can_gather_villager_true() -> void:
	var data := {"unit_category": "civilian"}
	assert_bool(UnitCategory.can_gather(data)).is_true()


func test_can_gather_infantry_false() -> void:
	var data := {"unit_category": "military"}
	assert_bool(UnitCategory.can_gather(data)).is_false()


func test_can_build_villager_true() -> void:
	var data := {"unit_category": "civilian"}
	assert_bool(UnitCategory.can_build(data)).is_true()


func test_can_build_cavalry_false() -> void:
	var data := {"unit_category": "military"}
	assert_bool(UnitCategory.can_build(data)).is_false()


func test_can_attack_infantry_true() -> void:
	var data := {"attack": 6}
	assert_bool(UnitCategory.can_attack(data)).is_true()


func test_can_attack_zero_attack_false() -> void:
	var data := {"attack": 0}
	assert_bool(UnitCategory.can_attack(data)).is_false()


func test_is_military_infantry_true() -> void:
	var data := {"unit_category": "military"}
	assert_bool(UnitCategory.is_military(data)).is_true()


func test_is_military_villager_false() -> void:
	var data := {"unit_category": "civilian"}
	assert_bool(UnitCategory.is_military(data)).is_false()


func test_get_movement_type_defaults_to_land() -> void:
	var data := {"unit_category": "military"}
	assert_str(UnitCategory.get_movement_type(data)).is_equal("land")


func test_get_movement_type_water() -> void:
	var data := {"movement_type": "water"}
	assert_str(UnitCategory.get_movement_type(data)).is_equal("water")


# -- Bonus damage --


func test_bonus_damage_infantry_vs_archer() -> void:
	var data := {"bonus_vs": {"archer": 1.5}}
	assert_float(UnitCategory.calculate_bonus_damage(data, "archer")).is_equal(1.5)


func test_bonus_damage_cavalry_vs_infantry() -> void:
	var data := {"bonus_vs": {"infantry": 1.5}}
	assert_float(UnitCategory.calculate_bonus_damage(data, "infantry")).is_equal(1.5)


func test_bonus_damage_archer_vs_cavalry() -> void:
	var data := {"bonus_vs": {"cavalry": 1.5}}
	assert_float(UnitCategory.calculate_bonus_damage(data, "cavalry")).is_equal(1.5)


func test_bonus_damage_no_bonus() -> void:
	var data := {"bonus_vs": {"archer": 1.5}}
	assert_float(UnitCategory.calculate_bonus_damage(data, "cavalry")).is_equal(1.0)


func test_bonus_damage_empty_bonus_vs() -> void:
	var data := {"bonus_vs": {}}
	assert_float(UnitCategory.calculate_bonus_damage(data, "infantry")).is_equal(1.0)


func test_bonus_damage_no_bonus_vs_key() -> void:
	var data := {}
	assert_float(UnitCategory.calculate_bonus_damage(data, "infantry")).is_equal(1.0)


func test_siege_bonus_vs_building() -> void:
	var data := {"bonus_vs": {"building": 5.0}}
	assert_float(UnitCategory.calculate_bonus_damage(data, "building")).is_equal(5.0)

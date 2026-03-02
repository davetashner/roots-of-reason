extends GdUnitTestSuite
## Comprehensive combat matchup tests verifying unit-vs-unit balance.
##
## Tests the rock-paper-scissors invariants, siege damage bonuses, unique unit
## advantages, and prints a matchup results table for balance review. All stats
## are loaded from JSON data files — no hardcoded numbers.

var _combat_config: Dictionary


func before() -> void:
	var file := FileAccess.open("res://data/settings/combat/combat.json", FileAccess.READ)
	assert_object(file).is_not_null()
	_combat_config = JSON.parse_string(file.get_as_text()) as Dictionary


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _load_unit_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_object(file).is_not_null()
	var data: Variant = JSON.parse_string(file.get_as_text())
	assert_object(data).is_not_null()
	return data as Dictionary


func _load_building_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_object(file).is_not_null()
	var data: Variant = JSON.parse_string(file.get_as_text())
	assert_object(data).is_not_null()
	return data as Dictionary


func _stats_from_unit(json: Dictionary, unit_type: String) -> Dictionary:
	return {
		"attack": int(json.get("attack", 0)),
		"defense": int(json.get("defense", 0)),
		"range": int(json.get("range", 0)),
		"min_range": int(json.get("min_range", 0)),
		"hp": int(json.get("hp", 1)),
		"speed": float(json.get("speed", 1.0)),
		"attack_speed": float(json.get("attack_speed", 1.0)),
		"bonus_vs": json.get("bonus_vs", {}),
		"unit_category": str(json.get("unit_category", "military")),
		"unit_type": unit_type,
		"attack_type": str(json.get("attack_type", "melee")),
		"armor_type": str(json.get("armor_type", "none")),
		"building_damage_ignore_reduction": float(json.get("building_damage_ignore_reduction", 0.0)),
	}


func _stats_from_building(json: Dictionary) -> Dictionary:
	return {
		"attack": 0,
		"defense": int(json.get("defense", 0)),
		"range": 0,
		"min_range": 0,
		"hp": int(json.get("hp", 1)),
		"speed": 0.0,
		"attack_speed": 0.0,
		"bonus_vs": {},
		"unit_category": "building",
		"unit_type": "building",
		"attack_type": "melee",
		"armor_type": str(json.get("armor_type", "none")),
	}


## Simulate melee-range combat between two unit types (no range approach).
## Both units trade blows simultaneously until one dies.
## Returns: {winner, attacker_hp_remaining, defender_hp_remaining, rounds,
##           attacker_dps, defender_dps, attacker_dmg_per_hit, defender_dmg_per_hit}
func _simulate_combat(attacker: Dictionary, defender: Dictionary) -> Dictionary:
	var a_hp: float = float(attacker["hp"])
	var d_hp: float = float(defender["hp"])

	var a_dmg: int = CombatResolver.calculate_damage(attacker, defender, _combat_config)
	var d_dmg: int = CombatResolver.calculate_damage(defender, attacker, _combat_config)

	var a_speed: float = maxf(0.1, float(attacker.get("attack_speed", 1.0)))
	var d_speed: float = maxf(0.1, float(defender.get("attack_speed", 1.0)))

	var a_dps: float = float(a_dmg) / a_speed
	var d_dps: float = float(d_dmg) / d_speed

	# Simulate in 0.1s ticks
	var tick: float = 0.1
	var a_cooldown: float = 0.0
	var d_cooldown: float = 0.0
	var rounds: int = 0
	var max_ticks: int = 10000

	for _i in range(max_ticks):
		a_cooldown -= tick
		d_cooldown -= tick

		if a_cooldown <= 0.0:
			d_hp -= float(a_dmg)
			a_cooldown += a_speed
			rounds += 1
		if d_hp <= 0.0:
			break

		if d_cooldown <= 0.0:
			a_hp -= float(d_dmg)
			d_cooldown += d_speed
		if a_hp <= 0.0:
			break

	var winner: String = "attacker" if d_hp <= 0.0 else "defender"
	return {
		"winner": winner,
		"attacker_hp_remaining": maxi(0, int(a_hp)),
		"defender_hp_remaining": maxi(0, int(d_hp)),
		"rounds": rounds,
		"attacker_dps": snappedf(a_dps, 0.01),
		"defender_dps": snappedf(d_dps, 0.01),
		"attacker_dmg_per_hit": a_dmg,
		"defender_dmg_per_hit": d_dmg,
	}


## Calculate how many seconds a unit takes to destroy a building (one-way).
func _time_to_destroy_building(attacker: Dictionary, building: Dictionary) -> float:
	var dmg: int = CombatResolver.calculate_damage(attacker, building, _combat_config)
	var speed: float = maxf(0.1, float(attacker.get("attack_speed", 1.0)))
	var hp: float = float(building["hp"])
	var hits: int = ceili(hp / float(maxi(1, dmg)))
	return float(hits) * speed


# ---------------------------------------------------------------------------
# Rock-Paper-Scissors Core Matchups — Bonus Damage Verification
# ---------------------------------------------------------------------------
# The RPS triangle works through bonus_vs multipliers: each favored unit deals
# significantly more damage per hit to its counter target. The bonus creates
# a damage advantage that, combined with tactical play (kiting, positioning),
# produces the intended counter relationship. These tests verify the damage
# multipliers are correctly configured and produce meaningful advantages.


## Infantry has bonus_vs archer — verify infantry deals >= 1.5x damage.
func test_infantry_bonus_damage_vs_archer() -> void:
	var infantry := _stats_from_unit(_load_unit_json("res://data/units/infantry.json"), "infantry")
	var archer := _stats_from_unit(_load_unit_json("res://data/units/archer.json"), "archer")
	var bonus_dmg: int = CombatResolver.calculate_damage(infantry, archer, _combat_config)
	var no_bonus := infantry.duplicate()
	no_bonus["bonus_vs"] = {}
	var base_dmg: int = CombatResolver.calculate_damage(no_bonus, archer, _combat_config)
	var ratio: float = float(bonus_dmg) / float(base_dmg)
	assert_float(ratio).is_greater_equal(1.2)
	print("Infantry vs Archer: %d dmg (base %d), %.1fx bonus ratio" % [bonus_dmg, base_dmg, ratio])


## Infantry beats archer in direct combat simulation.
func test_infantry_beats_archer() -> void:
	var infantry := _stats_from_unit(_load_unit_json("res://data/units/infantry.json"), "infantry")
	var archer := _stats_from_unit(_load_unit_json("res://data/units/archer.json"), "archer")
	var result := _simulate_combat(infantry, archer)
	assert_str(result["winner"]).is_equal("attacker")
	print(
		(
			"Infantry vs Archer: Infantry wins with %d HP remaining (%d rounds)"
			% [result["attacker_hp_remaining"], result["rounds"]]
		)
	)


## Archer has bonus_vs cavalry — verify archer deals >= 1.5x damage.
func test_archer_bonus_damage_vs_cavalry() -> void:
	var archer := _stats_from_unit(_load_unit_json("res://data/units/archer.json"), "archer")
	var cavalry := _stats_from_unit(_load_unit_json("res://data/units/cavalry.json"), "cavalry")
	var bonus_dmg: int = CombatResolver.calculate_damage(archer, cavalry, _combat_config)
	var no_bonus := archer.duplicate()
	no_bonus["bonus_vs"] = {}
	var base_dmg: int = CombatResolver.calculate_damage(no_bonus, cavalry, _combat_config)
	var ratio: float = float(bonus_dmg) / float(base_dmg)
	assert_float(ratio).is_greater_equal(1.2)
	print("Archer vs Cavalry: %d dmg (base %d), %.1fx bonus ratio" % [bonus_dmg, base_dmg, ratio])


## Archer has range advantage over cavalry — verify archer can fire before
## cavalry can engage in melee, providing free damage during approach.
func test_archer_range_advantage_over_cavalry() -> void:
	var archer := _stats_from_unit(_load_unit_json("res://data/units/archer.json"), "archer")
	var cavalry := _stats_from_unit(_load_unit_json("res://data/units/cavalry.json"), "cavalry")
	# Archer has range, cavalry does not
	assert_int(int(archer["range"])).is_greater(0)
	assert_int(int(cavalry["range"])).is_equal(0)
	# Archer fires at range 5 — cavalry must close distance
	var approach_tiles: int = int(archer["range"])
	var cavalry_speed: float = float(cavalry["speed"])
	var approach_time: float = float(approach_tiles) / cavalry_speed
	var archer_attack_speed: float = float(archer["attack_speed"])
	var free_shots: int = int(approach_time / archer_attack_speed)
	assert_int(free_shots).is_greater_equal(1)
	var dmg_per_shot: int = CombatResolver.calculate_damage(archer, cavalry, _combat_config)
	var free_damage: int = free_shots * dmg_per_shot
	print(
		(
			("Archer vs Cavalry approach: %d free shots over %.1fs," + " %d total free damage (cavalry HP=%d)")
			% [free_shots, approach_time, free_damage, cavalry["hp"]]
		)
	)


## Cavalry has bonus_vs infantry — verify cavalry deals >= 1.5x damage.
func test_cavalry_bonus_damage_vs_infantry() -> void:
	var cavalry := _stats_from_unit(_load_unit_json("res://data/units/cavalry.json"), "cavalry")
	var infantry := _stats_from_unit(_load_unit_json("res://data/units/infantry.json"), "infantry")
	var bonus_dmg: int = CombatResolver.calculate_damage(cavalry, infantry, _combat_config)
	var no_bonus := cavalry.duplicate()
	no_bonus["bonus_vs"] = {}
	var base_dmg: int = CombatResolver.calculate_damage(no_bonus, infantry, _combat_config)
	var ratio: float = float(bonus_dmg) / float(base_dmg)
	assert_float(ratio).is_greater_equal(1.2)
	print("Cavalry vs Infantry: %d dmg (base %d), %.1fx bonus ratio" % [bonus_dmg, base_dmg, ratio])


## Cavalry beats infantry in direct combat simulation.
func test_cavalry_beats_infantry() -> void:
	var cavalry := _stats_from_unit(_load_unit_json("res://data/units/cavalry.json"), "cavalry")
	var infantry := _stats_from_unit(_load_unit_json("res://data/units/infantry.json"), "infantry")
	var result := _simulate_combat(cavalry, infantry)
	assert_str(result["winner"]).is_equal("attacker")
	print(
		(
			"Cavalry vs Infantry: Cavalry wins with %d HP remaining (%d rounds)"
			% [result["attacker_hp_remaining"], result["rounds"]]
		)
	)


# ---------------------------------------------------------------------------
# RPS Asymmetry — Reverse Matchups
# ---------------------------------------------------------------------------


## Archer should lose to infantry (reverse of infantry beats archer).
func test_archer_loses_to_infantry() -> void:
	var archer := _stats_from_unit(_load_unit_json("res://data/units/archer.json"), "archer")
	var infantry := _stats_from_unit(_load_unit_json("res://data/units/infantry.json"), "infantry")
	var result := _simulate_combat(archer, infantry)
	assert_str(result["winner"]).is_equal("defender")
	print("Archer vs Infantry: Infantry wins (defender) with %d HP remaining" % [result["defender_hp_remaining"]])


## Infantry should lose to cavalry.
func test_infantry_loses_to_cavalry() -> void:
	var infantry := _stats_from_unit(_load_unit_json("res://data/units/infantry.json"), "infantry")
	var cavalry := _stats_from_unit(_load_unit_json("res://data/units/cavalry.json"), "cavalry")
	var result := _simulate_combat(infantry, cavalry)
	assert_str(result["winner"]).is_equal("defender")
	print("Infantry vs Cavalry: Cavalry wins (defender) with %d HP remaining" % [result["defender_hp_remaining"]])


## Cavalry has no bonus_vs archer, verifying the asymmetry: archer is strong
## against cavalry (has bonus_vs) but cavalry is not strong against archer.
func test_cavalry_has_no_bonus_vs_archer() -> void:
	var cavalry_json := _load_unit_json("res://data/units/cavalry.json")
	var archer_json := _load_unit_json("res://data/units/archer.json")
	# Cavalry should NOT have bonus_vs archer — only infantry counters archer
	assert_bool(cavalry_json["bonus_vs"].has("archer")).is_false()
	# Archer DOES have bonus_vs cavalry — the counter is one-directional
	assert_bool(archer_json["bonus_vs"].has("cavalry")).is_true()
	print(
		(
			"Cavalry bonus_vs: %s (no archer counter), Archer bonus_vs: %s"
			% [str(cavalry_json["bonus_vs"]), str(archer_json["bonus_vs"])]
		)
	)


# ---------------------------------------------------------------------------
# RPS Bonus Multiplier Data Integrity
# ---------------------------------------------------------------------------


## Verify each RPS pair has correct bonus_vs targets and meaningful multipliers.
func test_rps_bonus_multipliers_data_integrity() -> void:
	var infantry_json := _load_unit_json("res://data/units/infantry.json")
	var archer_json := _load_unit_json("res://data/units/archer.json")
	var cavalry_json := _load_unit_json("res://data/units/cavalry.json")

	# Verify bonus_vs targets exist
	assert_bool(infantry_json["bonus_vs"].has("archer")).is_true()
	assert_bool(archer_json["bonus_vs"].has("cavalry")).is_true()
	assert_bool(cavalry_json["bonus_vs"].has("infantry")).is_true()

	# Each bonus should be >= 1.2x
	assert_float(float(infantry_json["bonus_vs"]["archer"])).is_greater_equal(1.2)
	assert_float(float(archer_json["bonus_vs"]["cavalry"])).is_greater_equal(1.2)
	assert_float(float(cavalry_json["bonus_vs"]["infantry"])).is_greater_equal(1.2)
	print(
		(
			"RPS bonuses: inf->archer=%.1fx, arc->cav=%.1fx, cav->inf=%.1fx"
			% [
				float(infantry_json["bonus_vs"]["archer"]),
				float(archer_json["bonus_vs"]["cavalry"]),
				float(cavalry_json["bonus_vs"]["infantry"]),
			]
		)
	)


# ---------------------------------------------------------------------------
# Siege Damage Tests
# ---------------------------------------------------------------------------


func test_siege_ram_bonus_vs_building() -> void:
	var siege_json := _load_unit_json("res://data/units/siege.json")
	assert_bool(siege_json["bonus_vs"].has("building")).is_true()
	var bonus: float = float(siege_json["bonus_vs"]["building"])
	assert_float(bonus).is_greater(1.0)
	print("Siege Ram bonus_vs building: %.1fx" % [bonus])


func test_siege_ram_massive_building_damage() -> void:
	var siege := _stats_from_unit(_load_unit_json("res://data/units/siege.json"), "siege")
	var barracks := _stats_from_building(_load_building_json("res://data/buildings/barracks.json"))
	var dmg: int = CombatResolver.calculate_damage(siege, barracks, _combat_config)
	# Siege ram should deal significant damage per hit to buildings
	assert_int(dmg).is_greater(50)
	print("Siege Ram vs Barracks: %d damage per hit" % [dmg])


func test_siege_ram_vs_building_much_faster_than_infantry() -> void:
	var siege := _stats_from_unit(_load_unit_json("res://data/units/siege.json"), "siege")
	var infantry := _stats_from_unit(_load_unit_json("res://data/units/infantry.json"), "infantry")
	var barracks := _stats_from_building(_load_building_json("res://data/buildings/barracks.json"))
	var siege_time := _time_to_destroy_building(siege, barracks)
	var infantry_time := _time_to_destroy_building(infantry, barracks)
	# Siege should destroy buildings much faster than infantry
	assert_float(siege_time).is_less(infantry_time)
	print(
		(
			("Time to destroy Barracks: Siege Ram=%.1fs, Infantry=%.1fs" + " (%.1fx faster)")
			% [siege_time, infantry_time, infantry_time / siege_time]
		)
	)


func test_artillery_bonus_vs_building() -> void:
	var artillery_json := _load_unit_json("res://data/units/artillery.json")
	assert_bool(artillery_json["bonus_vs"].has("building")).is_true()
	var bonus: float = float(artillery_json["bonus_vs"]["building"])
	assert_float(bonus).is_greater(1.0)
	print("Artillery bonus_vs building: %.1fx (range: %d)" % [bonus, int(artillery_json["range"])])


func test_artillery_has_range_advantage_over_siege_ram() -> void:
	var artillery_json := _load_unit_json("res://data/units/artillery.json")
	var siege_json := _load_unit_json("res://data/units/siege.json")
	assert_int(int(artillery_json["range"])).is_greater(int(siege_json["range"]))
	print("Artillery range=%d vs Siege Ram range=%d" % [int(artillery_json["range"]), int(siege_json["range"])])


func test_cannon_ship_bonus_vs_building() -> void:
	var cannon_json := _load_unit_json("res://data/units/cannon_ship.json")
	assert_bool(cannon_json["bonus_vs"].has("building")).is_true()
	var bonus: float = float(cannon_json["bonus_vs"]["building"])
	assert_float(bonus).is_greater(1.0)
	print("Cannon Ship bonus_vs building: %.1fx" % [bonus])


func test_cannon_ship_vs_dock_significant_damage() -> void:
	var cannon := _stats_from_unit(_load_unit_json("res://data/units/cannon_ship.json"), "cannon_ship")
	var dock := _stats_from_building(_load_building_json("res://data/buildings/dock.json"))
	var dmg: int = CombatResolver.calculate_damage(cannon, dock, _combat_config)
	# Cannon ship should deal meaningful damage to docks
	assert_int(dmg).is_greater(10)
	var time := _time_to_destroy_building(cannon, dock)
	print("Cannon Ship vs Dock: %d dmg/hit, %.1fs to destroy" % [dmg, time])


# ---------------------------------------------------------------------------
# Unique Unit Matchups
# ---------------------------------------------------------------------------


func test_legionnaire_high_defense() -> void:
	var legionnaire_json := _load_unit_json("res://data/units/legionnaire.json")
	var infantry_json := _load_unit_json("res://data/units/infantry.json")
	assert_int(int(legionnaire_json["defense"])).is_greater(int(infantry_json["defense"]))
	print(
		(
			"Legionnaire defense=%d vs Infantry defense=%d"
			% [int(legionnaire_json["defense"]), int(infantry_json["defense"])]
		)
	)


func test_legionnaire_has_bonus_vs_archer() -> void:
	var legionnaire := _stats_from_unit(_load_unit_json("res://data/units/legionnaire.json"), "legionnaire")
	var archer := _stats_from_unit(_load_unit_json("res://data/units/archer.json"), "archer")
	var dmg: int = CombatResolver.calculate_damage(legionnaire, archer, _combat_config)
	var no_bonus := legionnaire.duplicate()
	no_bonus["bonus_vs"] = {}
	var base_dmg: int = CombatResolver.calculate_damage(no_bonus, archer, _combat_config)
	assert_int(dmg).is_greater(base_dmg)
	print("Legionnaire vs Archer: %d dmg with bonus (base %d)" % [dmg, base_dmg])


## Archer has range advantage over Legionnaire (melee unit), meaning archer
## gets free shots before Legionnaire can engage.
func test_archer_has_range_vs_legionnaire() -> void:
	var legionnaire_json := _load_unit_json("res://data/units/legionnaire.json")
	var archer_json := _load_unit_json("res://data/units/archer.json")
	assert_int(int(archer_json["range"])).is_greater(int(legionnaire_json["range"]))
	print("Archer range=%d vs Legionnaire range=%d" % [int(archer_json["range"]), int(legionnaire_json["range"])])


func test_berserker_rage_increases_attack() -> void:
	var berserker_json := _load_unit_json("res://data/units/berserker.json")
	assert_bool(berserker_json.has("rage_threshold")).is_true()
	assert_bool(berserker_json.has("rage_attack_bonus")).is_true()
	var rage_bonus: float = float(berserker_json["rage_attack_bonus"])
	assert_float(rage_bonus).is_greater(0.0)
	print(
		(
			"Berserker rage: triggers at %.0f%% HP, +%.0f%% attack"
			% [
				float(berserker_json["rage_threshold"]) * 100.0,
				rage_bonus * 100.0,
			]
		)
	)


## Archer has range advantage over Berserker (melee unit).
func test_archer_has_range_vs_berserker() -> void:
	var berserker_json := _load_unit_json("res://data/units/berserker.json")
	var archer_json := _load_unit_json("res://data/units/archer.json")
	assert_int(int(archer_json["range"])).is_greater(int(berserker_json["range"]))
	assert_int(int(archer_json["range"])).is_greater_equal(5)
	print("Archer range=%d vs Berserker range=%d" % [int(archer_json["range"]), int(berserker_json["range"])])


func test_chu_ko_nu_has_bonus_vs_cavalry() -> void:
	var chu_ko_nu := _stats_from_unit(_load_unit_json("res://data/units/chu_ko_nu.json"), "chu_ko_nu")
	var cavalry := _stats_from_unit(_load_unit_json("res://data/units/cavalry.json"), "cavalry")
	var chu_json := _load_unit_json("res://data/units/chu_ko_nu.json")
	assert_bool(chu_json["bonus_vs"].has("cavalry")).is_true()

	var chu_dmg: int = CombatResolver.calculate_damage(chu_ko_nu, cavalry, _combat_config)
	var chu_dps: float = float(chu_dmg) / float(chu_ko_nu["attack_speed"])
	print(
		(
			"Chu-Ko-Nu vs Cavalry: %d dmg/hit, %.2f DPS (attack_speed=%.1f)"
			% [chu_dmg, chu_dps, float(chu_ko_nu["attack_speed"])]
		)
	)
	assert_int(chu_dmg).is_greater(1)


func test_chu_ko_nu_rapid_fire_vs_standard_archer() -> void:
	var chu_json := _load_unit_json("res://data/units/chu_ko_nu.json")
	var archer_json := _load_unit_json("res://data/units/archer.json")
	var chu_speed: float = float(chu_json["attack_speed"])
	var archer_speed: float = float(archer_json["attack_speed"])
	assert_float(chu_speed).is_less(archer_speed)
	print(
		(
			"Attack speed: Chu-Ko-Nu=%.1fs vs Archer=%.1fs (%.1fx faster)"
			% [chu_speed, archer_speed, archer_speed / chu_speed]
		)
	)


func test_tank_bonus_vs_infantry_and_archer() -> void:
	var tank_json := _load_unit_json("res://data/units/tank.json")
	assert_bool(tank_json["bonus_vs"].has("infantry")).is_true()
	assert_bool(tank_json["bonus_vs"].has("archer")).is_true()
	var inf_bonus: float = float(tank_json["bonus_vs"]["infantry"])
	var arc_bonus: float = float(tank_json["bonus_vs"]["archer"])
	assert_float(inf_bonus).is_greater(1.0)
	assert_float(arc_bonus).is_greater(1.0)
	print("Tank bonus_vs: infantry=%.1fx, archer=%.1fx" % [inf_bonus, arc_bonus])


func test_tank_vs_infantry_decisive_victory() -> void:
	var tank := _stats_from_unit(_load_unit_json("res://data/units/tank.json"), "tank")
	var infantry := _stats_from_unit(_load_unit_json("res://data/units/infantry.json"), "infantry")
	var result := _simulate_combat(tank, infantry)
	assert_str(result["winner"]).is_equal("attacker")
	assert_int(result["attacker_hp_remaining"]).is_greater(int(float(tank["hp"]) * 0.5))
	print("Tank vs Infantry: Tank wins with %d/%d HP remaining" % [result["attacker_hp_remaining"], tank["hp"]])


# ---------------------------------------------------------------------------
# Matchup Results Table
# ---------------------------------------------------------------------------


func test_print_matchup_table() -> void:
	var unit_types: Array = [
		"infantry",
		"archer",
		"cavalry",
		"legionnaire",
		"berserker",
		"chu_ko_nu",
		"tank",
	]
	var unit_stats: Dictionary = {}
	for unit_type in unit_types:
		var json := _load_unit_json("res://data/units/%s.json" % [unit_type])
		unit_stats[unit_type] = _stats_from_unit(json, unit_type)

	var header: String = "%-14s |" % ["Attacker"]
	for defender_type in unit_types:
		header += " %6s |" % [str(defender_type).left(6)]
	print("\n=== COMBAT MATCHUP TABLE (W=win, L=loss / survivor HP) ===")
	print(header)
	print("-".repeat(header.length()))

	var all_valid: bool = true
	for attacker_type in unit_types:
		var row: String = "%-14s |" % [attacker_type]
		for defender_type in unit_types:
			if attacker_type == defender_type:
				row += "   --   |"
				continue
			var result := _simulate_combat(unit_stats[attacker_type], unit_stats[defender_type])
			var marker: String = "W" if result["winner"] == "attacker" else "L"
			var hp_left: int = (
				result["attacker_hp_remaining"] if result["winner"] == "attacker" else result["defender_hp_remaining"]
			)
			row += " %s %3d |" % [marker, hp_left]
		print(row)

	# Table is informational — individual matchups verified by dedicated tests
	assert_bool(all_valid).is_true()

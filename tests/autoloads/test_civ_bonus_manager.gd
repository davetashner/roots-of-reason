extends GdUnitTestSuite
## Tests for CivBonusManager autoload.

var _original_active_civs: Dictionary
var _original_civ_cache: Dictionary
var _original_stockpiles: Dictionary
var _original_gather_multipliers: Dictionary
var _original_corruption_rates: Dictionary


func before_test() -> void:
	_original_active_civs = CivBonusManager._active_civs.duplicate(true)
	_original_civ_cache = CivBonusManager._civ_cache.duplicate(true)
	_original_stockpiles = ResourceManager._stockpiles.duplicate(true)
	_original_gather_multipliers = ResourceManager._gather_multipliers.duplicate(true)
	_original_corruption_rates = ResourceManager._corruption_rates.duplicate(true)
	CivBonusManager._active_civs.clear()
	CivBonusManager._civ_cache.clear()


func after_test() -> void:
	CivBonusManager._active_civs = _original_active_civs.duplicate(true)
	CivBonusManager._civ_cache = _original_civ_cache.duplicate(true)
	ResourceManager._stockpiles = _original_stockpiles.duplicate(true)
	ResourceManager._gather_multipliers = _original_gather_multipliers.duplicate(true)
	ResourceManager._corruption_rates = _original_corruption_rates.duplicate(true)


# --- Data Loading ---


func test_mesopotamia_loads() -> void:
	CivBonusManager.apply_civ_bonuses(0, "mesopotamia")
	assert_str(CivBonusManager.get_active_civ(0)).is_equal("mesopotamia")


func test_rome_loads() -> void:
	CivBonusManager.apply_civ_bonuses(0, "rome")
	assert_str(CivBonusManager.get_active_civ(0)).is_equal("rome")


func test_polynesia_loads() -> void:
	CivBonusManager.apply_civ_bonuses(0, "polynesia")
	assert_str(CivBonusManager.get_active_civ(0)).is_equal("polynesia")


func test_unknown_civ_warns_and_does_not_assign() -> void:
	CivBonusManager.apply_civ_bonuses(0, "atlantis")
	assert_str(CivBonusManager.get_active_civ(0)).is_equal("")


func test_get_active_civ_unassigned_returns_empty() -> void:
	assert_str(CivBonusManager.get_active_civ(99)).is_equal("")


# --- get_bonus_value ---


func test_mesopotamia_build_speed() -> void:
	CivBonusManager.apply_civ_bonuses(0, "mesopotamia")
	assert_float(CivBonusManager.get_bonus_value(0, "build_speed")).is_equal_approx(1.15, 0.001)


func test_rome_military_attack() -> void:
	CivBonusManager.apply_civ_bonuses(0, "rome")
	assert_float(CivBonusManager.get_bonus_value(0, "military_attack")).is_equal_approx(1.10, 0.001)


func test_rome_military_defense() -> void:
	CivBonusManager.apply_civ_bonuses(0, "rome")
	assert_float(CivBonusManager.get_bonus_value(0, "military_defense")).is_equal_approx(1.10, 0.001)


func test_polynesia_naval_speed() -> void:
	CivBonusManager.apply_civ_bonuses(0, "polynesia")
	assert_float(CivBonusManager.get_bonus_value(0, "naval_speed")).is_equal_approx(1.20, 0.001)


func test_missing_bonus_returns_1() -> void:
	CivBonusManager.apply_civ_bonuses(0, "mesopotamia")
	assert_float(CivBonusManager.get_bonus_value(0, "military_attack")).is_equal_approx(1.0, 0.001)


func test_no_civ_bonus_returns_1() -> void:
	assert_float(CivBonusManager.get_bonus_value(99, "build_speed")).is_equal_approx(1.0, 0.001)


# --- get_build_speed_multiplier ---


func test_build_speed_multiplier_mesopotamia() -> void:
	CivBonusManager.apply_civ_bonuses(0, "mesopotamia")
	assert_float(CivBonusManager.get_build_speed_multiplier(0)).is_equal_approx(1.15, 0.001)


func test_build_speed_multiplier_rome_returns_1() -> void:
	CivBonusManager.apply_civ_bonuses(0, "rome")
	assert_float(CivBonusManager.get_build_speed_multiplier(0)).is_equal_approx(1.0, 0.001)


# --- Military bonuses (Rome) ---


func test_rome_attack_applied_to_infantry() -> void:
	CivBonusManager.apply_civ_bonuses(0, "rome")
	var stats := UnitStats.new("infantry", {"attack": 10.0, "defense": 5.0})
	CivBonusManager.apply_bonus_to_unit(stats, "infantry", 0)
	# 10% attack bonus: 10 * 1.10 = 11
	assert_float(stats.get_stat("attack")).is_equal_approx(11.0, 0.1)
	# 10% defense bonus: 5 * 1.10 = 5.5
	assert_float(stats.get_stat("defense")).is_equal_approx(5.5, 0.1)


func test_rome_bonus_not_applied_to_villager() -> void:
	CivBonusManager.apply_civ_bonuses(0, "rome")
	var stats := UnitStats.new("villager", {"attack": 3.0, "defense": 0.0})
	CivBonusManager.apply_bonus_to_unit(stats, "villager", 0)
	# Villager is not military — no bonus
	assert_float(stats.get_stat("attack")).is_equal_approx(3.0, 0.1)


# --- Naval bonus (Polynesia) ---


func test_polynesia_speed_applied_to_naval() -> void:
	CivBonusManager.apply_civ_bonuses(0, "polynesia")
	var stats := UnitStats.new("war_galley", {"speed": 1.8})
	CivBonusManager.apply_bonus_to_unit(stats, "war_galley", 0)
	# 20% speed bonus: 1.8 * 1.20 = 2.16
	assert_float(stats.get_stat("speed")).is_equal_approx(2.16, 0.01)


func test_polynesia_speed_not_applied_to_infantry() -> void:
	CivBonusManager.apply_civ_bonuses(0, "polynesia")
	var stats := UnitStats.new("infantry", {"speed": 1.2})
	CivBonusManager.apply_bonus_to_unit(stats, "infantry", 0)
	# Infantry is land — no naval bonus
	assert_float(stats.get_stat("speed")).is_equal_approx(1.2, 0.01)


# --- Removal ---


func test_remove_clears_active_civ() -> void:
	CivBonusManager.apply_civ_bonuses(0, "rome")
	CivBonusManager.remove_civ_bonuses(0)
	assert_str(CivBonusManager.get_active_civ(0)).is_equal("")


func test_reapply_removes_old_first() -> void:
	var removed_ids: Array = []
	var applied_ids: Array = []
	CivBonusManager.bonuses_removed.connect(func(_pid: int, cid: String) -> void: removed_ids.append(cid))
	CivBonusManager.bonuses_applied.connect(func(_pid: int, cid: String) -> void: applied_ids.append(cid))
	CivBonusManager.apply_civ_bonuses(0, "rome")
	CivBonusManager.apply_civ_bonuses(0, "polynesia")
	assert_str(CivBonusManager.get_active_civ(0)).is_equal("polynesia")
	assert_array(removed_ids).contains(["rome"])
	assert_array(applied_ids).contains(["rome", "polynesia"])
	# Disconnect signals to avoid leaking into other tests
	for conn in CivBonusManager.bonuses_removed.get_connections():
		CivBonusManager.bonuses_removed.disconnect(conn.callable)
	for conn in CivBonusManager.bonuses_applied.get_connections():
		CivBonusManager.bonuses_applied.disconnect(conn.callable)


# --- Starting bonuses ---


func test_starting_bonuses_empty_is_noop() -> void:
	ResourceManager.init_player(50)
	var before_food: int = ResourceManager.get_amount(50, ResourceManager.ResourceType.FOOD)
	CivBonusManager.apply_civ_bonuses(50, "mesopotamia")
	CivBonusManager.apply_starting_bonuses(50)
	assert_int(ResourceManager.get_amount(50, ResourceManager.ResourceType.FOOD)).is_equal(before_food)


func test_starting_bonuses_require_init_player_first() -> void:
	# Verifies that apply_starting_bonuses requires ResourceManager to be
	# initialized for the player. The assertion in apply_starting_bonuses
	# guards against the fragile ordering bug where init_player() could wipe
	# bonus resources if called afterward.
	ResourceManager.init_player(51)
	assert_bool(ResourceManager.has_player(51)).is_true()
	CivBonusManager.apply_civ_bonuses(51, "mesopotamia")
	# Should not assert — player 51 is initialized
	CivBonusManager.apply_starting_bonuses(51)


func test_starting_bonuses_survive_when_init_before_bonuses() -> void:
	# Simulates the correct init order: init_player first, then civ bonuses.
	# Any extra_resources added by apply_starting_bonuses must persist.
	ResourceManager.init_player(52, {ResourceManager.ResourceType.FOOD: 200})
	var food_before: int = ResourceManager.get_amount(52, ResourceManager.ResourceType.FOOD)
	CivBonusManager.apply_civ_bonuses(52, "mesopotamia")
	CivBonusManager.apply_starting_bonuses(52)
	# Current civs have empty starting_bonuses, so resources should be unchanged.
	assert_int(ResourceManager.get_amount(52, ResourceManager.ResourceType.FOOD)).is_equal(food_before)


# --- Save/Load ---


func test_save_load_round_trip() -> void:
	CivBonusManager.apply_civ_bonuses(0, "mesopotamia")
	CivBonusManager.apply_civ_bonuses(1, "rome")
	var state: Dictionary = CivBonusManager.save_state()
	CivBonusManager._active_civs.clear()
	CivBonusManager.load_state(state)
	assert_str(CivBonusManager.get_active_civ(0)).is_equal("mesopotamia")
	assert_str(CivBonusManager.get_active_civ(1)).is_equal("rome")


# --- Signals ---


func test_bonuses_applied_signal() -> void:
	var signal_data: Array = []
	CivBonusManager.bonuses_applied.connect(func(pid: int, cid: String) -> void: signal_data.append([pid, cid]))
	CivBonusManager.apply_civ_bonuses(0, "mesopotamia")
	assert_array(signal_data).has_size(1)
	assert_int(signal_data[0][0]).is_equal(0)
	assert_str(signal_data[0][1]).is_equal("mesopotamia")
	for conn in CivBonusManager.bonuses_applied.get_connections():
		CivBonusManager.bonuses_applied.disconnect(conn.callable)


func test_bonuses_removed_signal() -> void:
	CivBonusManager.apply_civ_bonuses(0, "rome")
	var signal_data: Array = []
	CivBonusManager.bonuses_removed.connect(func(pid: int, cid: String) -> void: signal_data.append([pid, cid]))
	CivBonusManager.remove_civ_bonuses(0)
	assert_array(signal_data).has_size(1)
	assert_int(signal_data[0][0]).is_equal(0)
	assert_str(signal_data[0][1]).is_equal("rome")
	for conn in CivBonusManager.bonuses_removed.get_connections():
		CivBonusManager.bonuses_removed.disconnect(conn.callable)


# --- Null safety ---


func test_apply_bonus_to_null_stats_is_noop() -> void:
	CivBonusManager.apply_civ_bonuses(0, "rome")
	CivBonusManager.apply_bonus_to_unit(null, "infantry", 0)
	# Should not crash


func test_apply_bonus_no_civ_assigned() -> void:
	var stats := UnitStats.new("infantry", {"attack": 10.0})
	CivBonusManager.apply_bonus_to_unit(stats, "infantry", 99)
	assert_float(stats.get_stat("attack")).is_equal_approx(10.0, 0.1)


# --- Building swap ---


func test_mesopotamia_library_resolves_to_ziggurat() -> void:
	CivBonusManager.apply_civ_bonuses(0, "mesopotamia")
	var resolved := CivBonusManager.get_resolved_building_id(0, "library")
	assert_str(resolved).is_equal("ziggurat")


func test_mesopotamia_non_replaced_building_unchanged() -> void:
	CivBonusManager.apply_civ_bonuses(0, "mesopotamia")
	var resolved := CivBonusManager.get_resolved_building_id(0, "barracks")
	assert_str(resolved).is_equal("barracks")


func test_no_civ_building_passthrough() -> void:
	var resolved := CivBonusManager.get_resolved_building_id(99, "library")
	assert_str(resolved).is_equal("library")


func test_rome_library_unchanged() -> void:
	CivBonusManager.apply_civ_bonuses(0, "rome")
	var resolved := CivBonusManager.get_resolved_building_id(0, "library")
	assert_str(resolved).is_equal("library")


func test_rome_market_resolves_to_colosseum() -> void:
	CivBonusManager.apply_civ_bonuses(0, "rome")
	var resolved := CivBonusManager.get_resolved_building_id(0, "market")
	assert_str(resolved).is_equal("colosseum")


func test_polynesia_library_resolves_to_marae() -> void:
	CivBonusManager.apply_civ_bonuses(0, "polynesia")
	var resolved := CivBonusManager.get_resolved_building_id(0, "library")
	assert_str(resolved).is_equal("marae")


# --- Unit swap ---


func test_mesopotamia_infantry_resolves_to_immortal_guard() -> void:
	CivBonusManager.apply_civ_bonuses(0, "mesopotamia")
	var resolved := CivBonusManager.get_resolved_unit_id(0, "infantry")
	assert_str(resolved).is_equal("immortal_guard")


func test_mesopotamia_non_replaced_unit_unchanged() -> void:
	CivBonusManager.apply_civ_bonuses(0, "mesopotamia")
	var resolved := CivBonusManager.get_resolved_unit_id(0, "villager")
	assert_str(resolved).is_equal("villager")


func test_no_civ_unit_passthrough() -> void:
	var resolved := CivBonusManager.get_resolved_unit_id(99, "infantry")
	assert_str(resolved).is_equal("infantry")


func test_rome_infantry_resolves_to_legionnaire() -> void:
	CivBonusManager.apply_civ_bonuses(0, "rome")
	var resolved := CivBonusManager.get_resolved_unit_id(0, "infantry")
	assert_str(resolved).is_equal("legionnaire")


func test_polynesia_naval_resolves_to_war_canoe() -> void:
	CivBonusManager.apply_civ_bonuses(0, "polynesia")
	var resolved := CivBonusManager.get_resolved_unit_id(0, "war_galley")
	assert_str(resolved).is_equal("war_canoe")

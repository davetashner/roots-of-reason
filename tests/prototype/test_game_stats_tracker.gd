extends GdUnitTestSuite
## Tests for game_stats_tracker.gd — cumulative stat tracking per player.

const TrackerScript := preload("res://scripts/prototype/game_stats_tracker.gd")


func _create_tracker(snapshot_interval: float = 30.0) -> Node:
	var tracker := Node.new()
	tracker.name = "GameStatsTracker"
	tracker.set_script(TrackerScript)
	add_child(tracker)
	auto_free(tracker)
	tracker.setup({"snapshot_interval_seconds": snapshot_interval})
	return tracker


func test_init_player_creates_empty_stats() -> void:
	var tracker := _create_tracker()
	tracker.init_player(0)
	var stats: Dictionary = tracker.get_player_stats(0)
	assert_that(stats["resources_gathered"]).is_equal({})
	assert_that(stats["units_produced"]).is_equal({})
	assert_that(stats["units_killed"]).is_equal(0)
	assert_that(stats["units_lost"]).is_equal(0)
	assert_that(stats["buildings_built"]).is_equal({})
	assert_that(stats["buildings_lost"]).is_equal(0)
	assert_that(stats["techs_researched"]).is_equal([])
	assert_that(stats["age_timestamps"]).is_equal({})
	assert_that(stats["time_snapshots"]).is_equal([])


func test_record_resource_gained() -> void:
	var tracker := _create_tracker()
	tracker.init_player(0)
	tracker.record_resource_change(0, "food", 100, 150)
	var stats: Dictionary = tracker.get_player_stats(0)
	assert_that(stats["resources_gathered"]["food"]).is_equal(50)


func test_record_resource_spent() -> void:
	var tracker := _create_tracker()
	tracker.init_player(0)
	tracker.record_resource_change(0, "gold", 200, 150)
	var stats: Dictionary = tracker.get_player_stats(0)
	assert_that(stats["resources_spent"]["gold"]).is_equal(50)


func test_record_resource_multiple_types() -> void:
	var tracker := _create_tracker()
	tracker.init_player(0)
	tracker.record_resource_change(0, "food", 0, 100)
	tracker.record_resource_change(0, "wood", 0, 200)
	tracker.record_resource_change(0, "food", 100, 250)
	var stats: Dictionary = tracker.get_player_stats(0)
	assert_that(stats["resources_gathered"]["food"]).is_equal(250)
	assert_that(stats["resources_gathered"]["wood"]).is_equal(200)


func test_record_unit_produced_per_type() -> void:
	var tracker := _create_tracker()
	tracker.init_player(0)
	tracker.record_unit_produced(0, "villager")
	tracker.record_unit_produced(0, "villager")
	tracker.record_unit_produced(0, "archer")
	var stats: Dictionary = tracker.get_player_stats(0)
	assert_that(stats["units_produced"]["villager"]).is_equal(2)
	assert_that(stats["units_produced"]["archer"]).is_equal(1)


func test_record_unit_kill() -> void:
	var tracker := _create_tracker()
	tracker.init_player(0)
	tracker.record_unit_kill(0)
	tracker.record_unit_kill(0)
	var stats: Dictionary = tracker.get_player_stats(0)
	assert_that(stats["units_killed"]).is_equal(2)


func test_record_unit_lost() -> void:
	var tracker := _create_tracker()
	tracker.init_player(0)
	tracker.record_unit_lost(0)
	var stats: Dictionary = tracker.get_player_stats(0)
	assert_that(stats["units_lost"]).is_equal(1)


func test_record_building_built() -> void:
	var tracker := _create_tracker()
	tracker.init_player(0)
	tracker.record_building_built(0, "house")
	tracker.record_building_built(0, "house")
	tracker.record_building_built(0, "barracks")
	var stats: Dictionary = tracker.get_player_stats(0)
	assert_that(stats["buildings_built"]["house"]).is_equal(2)
	assert_that(stats["buildings_built"]["barracks"]).is_equal(1)


func test_record_building_lost() -> void:
	var tracker := _create_tracker()
	tracker.init_player(0)
	tracker.record_building_lost(0)
	tracker.record_building_lost(0)
	var stats: Dictionary = tracker.get_player_stats(0)
	assert_that(stats["buildings_lost"]).is_equal(2)


func test_record_tech_researched() -> void:
	var tracker := _create_tracker()
	tracker.init_player(0)
	tracker.record_tech_researched(0, "agriculture", {})
	tracker.record_tech_researched(0, "writing", {})
	var stats: Dictionary = tracker.get_player_stats(0)
	assert_that(stats["techs_researched"]).is_equal(["agriculture", "writing"])


func test_record_tech_no_duplicates() -> void:
	var tracker := _create_tracker()
	tracker.init_player(0)
	tracker.record_tech_researched(0, "agriculture", {})
	tracker.record_tech_researched(0, "agriculture", {})
	var stats: Dictionary = tracker.get_player_stats(0)
	assert_that(stats["techs_researched"]).is_equal(["agriculture"])


func test_record_age_change() -> void:
	var tracker := _create_tracker()
	tracker.init_player(0)
	tracker._game_time = 120.0
	tracker.record_age_change(1, 0)
	tracker._game_time = 300.0
	tracker.record_age_change(2, 0)
	var stats: Dictionary = tracker.get_player_stats(0)
	assert_that(stats["age_timestamps"][1]).is_equal(120.0)
	assert_that(stats["age_timestamps"][2]).is_equal(300.0)


func test_multiple_players_isolated() -> void:
	var tracker := _create_tracker()
	tracker.init_player(0)
	tracker.init_player(1)
	tracker.record_unit_kill(0)
	tracker.record_unit_produced(1, "archer")
	var p0: Dictionary = tracker.get_player_stats(0)
	var p1: Dictionary = tracker.get_player_stats(1)
	assert_that(p0["units_killed"]).is_equal(1)
	assert_that(p0["units_produced"]).is_equal({})
	assert_that(p1["units_killed"]).is_equal(0)
	assert_that(p1["units_produced"]["archer"]).is_equal(1)


func test_ignores_unregistered_player() -> void:
	var tracker := _create_tracker()
	tracker.init_player(0)
	# These should not crash
	tracker.record_unit_kill(99)
	tracker.record_resource_change(99, "food", 0, 100)
	var stats: Dictionary = tracker.get_player_stats(99)
	assert_that(stats).is_equal({})


func test_snapshot_captures_state() -> void:
	var tracker := _create_tracker(1.0)
	tracker.init_player(0)
	tracker.record_resource_change(0, "food", 0, 500)
	tracker.record_unit_kill(0)
	# Manually trigger snapshot
	tracker._game_time = 1.0
	tracker._take_snapshot()
	var stats: Dictionary = tracker.get_player_stats(0)
	assert_that(stats["time_snapshots"].size()).is_equal(1)
	var snap: Dictionary = stats["time_snapshots"][0]
	assert_that(snap["resources_gathered_total"]).is_equal(500)
	assert_that(snap["units_killed"]).is_equal(1)
	assert_that(snap["time"]).is_equal(1.0)


func test_save_load_round_trip() -> void:
	var tracker := _create_tracker()
	tracker.init_player(0)
	tracker.init_player(1)
	tracker._game_time = 60.0
	tracker.record_resource_change(0, "food", 0, 300)
	tracker.record_unit_produced(1, "villager")
	tracker.record_tech_researched(0, "agriculture", {})
	var saved: Dictionary = tracker.save_state()

	var tracker2 := _create_tracker()
	tracker2.load_state(saved)
	var p0: Dictionary = tracker2.get_player_stats(0)
	assert_that(p0["resources_gathered"]["food"]).is_equal(300)
	assert_that(p0["techs_researched"]).is_equal(["agriculture"])
	assert_that(tracker2.get_game_time()).is_equal(60.0)
	var p1: Dictionary = tracker2.get_player_stats(1)
	assert_that(p1["units_produced"]["villager"]).is_equal(1)


func test_reset_clears_all() -> void:
	var tracker := _create_tracker()
	tracker.init_player(0)
	tracker._game_time = 120.0
	tracker.record_unit_kill(0)
	tracker.reset()
	assert_that(tracker.get_all_stats()).is_equal({})
	assert_that(tracker.get_game_time()).is_equal(0.0)


func test_get_all_stats_returns_copy() -> void:
	var tracker := _create_tracker()
	tracker.init_player(0)
	tracker.record_unit_kill(0)
	var all_stats: Dictionary = tracker.get_all_stats()
	all_stats[0]["units_killed"] = 999
	# Original should be unchanged
	assert_that(tracker.get_player_stats(0)["units_killed"]).is_equal(1)

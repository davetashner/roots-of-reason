extends GdUnitTestSuite
## Tests for postgame_stats_screen.gd — post-game stats overlay.

const ScreenScript := preload("res://scripts/ui/postgame_stats_screen.gd")


func _create_screen() -> PanelContainer:
	var screen := PanelContainer.new()
	screen.name = "PostGameStatsScreen"
	screen.set_script(ScreenScript)
	add_child(screen)
	auto_free(screen)
	return screen


func _make_sample_stats() -> Dictionary:
	return {
		0:
		{
			"resources_gathered": {"food": 500, "wood": 300},
			"resources_spent": {"food": 200},
			"units_produced": {"villager": 10, "archer": 5},
			"units_killed": 8,
			"units_lost": 3,
			"buildings_built": {"house": 4, "barracks": 1},
			"buildings_lost": 0,
			"techs_researched": ["agriculture", "writing"],
			"age_timestamps": {0: 0.0, 1: 120.0},
			"time_snapshots":
			[
				{
					"time": 30.0,
					"resources_gathered_total": 100,
					"resources_spent_total": 20,
					"units_killed": 0,
					"units_lost": 0,
					"buildings_built_total": 1,
					"buildings_lost": 0,
					"techs_count": 0
				},
				{
					"time": 60.0,
					"resources_gathered_total": 300,
					"resources_spent_total": 80,
					"units_killed": 3,
					"units_lost": 1,
					"buildings_built_total": 3,
					"buildings_lost": 0,
					"techs_count": 1
				},
			],
		},
		1:
		{
			"resources_gathered": {"food": 400, "wood": 250},
			"resources_spent": {"food": 150},
			"units_produced": {"villager": 8, "swordsman": 3},
			"units_killed": 3,
			"units_lost": 8,
			"buildings_built": {"house": 3},
			"buildings_lost": 1,
			"techs_researched": ["agriculture"],
			"age_timestamps": {0: 0.0, 1: 150.0},
			"time_snapshots":
			[
				{
					"time": 30.0,
					"resources_gathered_total": 80,
					"resources_spent_total": 10,
					"units_killed": 0,
					"units_lost": 0,
					"buildings_built_total": 1,
					"buildings_lost": 0,
					"techs_count": 0
				},
				{
					"time": 60.0,
					"resources_gathered_total": 200,
					"resources_spent_total": 50,
					"units_killed": 1,
					"units_lost": 3,
					"buildings_built_total": 2,
					"buildings_lost": 0,
					"techs_count": 1
				},
			],
		},
	}


func test_screen_starts_hidden() -> void:
	var screen := _create_screen()
	assert_that(screen.visible).is_false()


func test_show_stats_makes_visible() -> void:
	var screen := _create_screen()
	screen.show_stats(_make_sample_stats(), 180.0)
	assert_that(screen.visible).is_true()


func test_summary_tab_has_comparison_rows() -> void:
	var screen := _create_screen()
	screen.show_stats(_make_sample_stats(), 180.0)
	# Summary tab should have comparison rows (HBoxContainers named Row_*)
	var content: VBoxContainer = screen._tab_containers[0]
	var row_count := 0
	for child in content.get_children():
		if child is HBoxContainer and child.name.begins_with("Row_"):
			row_count += 1
	assert_that(row_count).is_greater(0)


func test_tab_switching() -> void:
	var screen := _create_screen()
	screen.show_stats(_make_sample_stats(), 180.0)
	# Initially tab 0 visible
	assert_that(screen._tab_containers[0].visible).is_true()
	assert_that(screen._tab_containers[1].visible).is_false()
	# Switch to economy tab
	screen._on_tab_pressed(1)
	assert_that(screen._tab_containers[0].visible).is_false()
	assert_that(screen._tab_containers[1].visible).is_true()


func test_close_button_hides() -> void:
	var screen := _create_screen()
	var closed_detected: Array = [false]
	screen.closed.connect(func() -> void: closed_detected[0] = true)
	screen.show_stats(_make_sample_stats(), 180.0)
	assert_that(screen.visible).is_true()
	screen._on_close_pressed()
	assert_that(screen.visible).is_false()
	assert_that(closed_detected[0]).is_true()


func test_handles_empty_stats() -> void:
	var screen := _create_screen()
	var empty_stats := {
		0:
		{
			"resources_gathered": {},
			"resources_spent": {},
			"units_produced": {},
			"units_killed": 0,
			"units_lost": 0,
			"buildings_built": {},
			"buildings_lost": 0,
			"techs_researched": [],
			"age_timestamps": {},
			"time_snapshots": [],
		},
		1:
		{
			"resources_gathered": {},
			"resources_spent": {},
			"units_produced": {},
			"units_killed": 0,
			"units_lost": 0,
			"buildings_built": {},
			"buildings_lost": 0,
			"techs_researched": [],
			"age_timestamps": {},
			"time_snapshots": [],
		},
	}
	# Should not crash with empty data
	screen.show_stats(empty_stats, 0.0)
	assert_that(screen.visible).is_true()

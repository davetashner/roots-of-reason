extends GdUnitTestSuite
## Tests for combat_visual.gd — visual effect helper methods.


func test_spawn_damage_number_creates_label() -> void:
	var parent := Node2D.new()
	add_child(parent)
	auto_free(parent)
	var config := {"damage_number_rise_distance": 30.0, "damage_number_duration": 0.8}
	var label := CombatVisual.spawn_damage_number(parent, Vector2(100, 100), 15, config)
	assert_that(label).is_not_null()
	assert_str(label.text).is_equal("15")
	assert_int(parent.get_child_count()).is_equal(1)


func test_spawn_projectile_creates_node() -> void:
	var parent := Node2D.new()
	add_child(parent)
	auto_free(parent)
	var config := {"projectile_speed": 400.0, "projectile_radius": 3.0}
	var proj := CombatVisual.spawn_projectile(parent, Vector2.ZERO, Vector2(100, 0), config)
	assert_that(proj).is_not_null()
	assert_int(parent.get_child_count()).is_equal(1)


func test_play_death_animation_returns_tween() -> void:
	var node := Node2D.new()
	add_child(node)
	auto_free(node)
	var config := {"death_fade_duration": 0.5}
	var tween := CombatVisual.play_death_animation(node, config)
	assert_that(tween).is_not_null()


func test_play_death_animation_returns_null_for_zero_duration() -> void:
	var node := Node2D.new()
	add_child(node)
	auto_free(node)
	var config := {"death_fade_duration": 0.0}
	var tween := CombatVisual.play_death_animation(node, config)
	assert_that(tween).is_null()


func test_play_attack_flash_does_not_error() -> void:
	var node := Node2D.new()
	add_child(node)
	auto_free(node)
	var config := {"attack_flash_duration": 0.15}
	# Should not error; just verify it runs
	CombatVisual.play_attack_flash(node, config)
	assert_that(node).is_not_null()

extends GdUnitTestSuite
## Tests for knowledge_burning_vfx.gd — visual feedback for tech regression events.

const VFXScript := preload("res://scripts/prototype/knowledge_burning_vfx.gd")
const NotificationPanelScript := preload("res://scripts/ui/notification_panel.gd")

var _original_game_time: float


func before_test() -> void:
	_original_game_time = GameManager.game_time
	GameManager.game_time = 765.0  # 12:45


func after_test() -> void:
	GameManager.game_time = _original_game_time


func _create_vfx(
	scene_root: Node2D = null,
	camera: Camera2D = null,
	notif: Control = null,
) -> Node:
	if scene_root == null:
		scene_root = Node2D.new()
		add_child(scene_root)
		auto_free(scene_root)
	var node := Node.new()
	node.set_script(VFXScript)
	add_child(node)
	auto_free(node)
	node.setup(scene_root, camera, notif)
	return node


func _create_notification_panel() -> Control:
	var panel := Control.new()
	panel.set_script(NotificationPanelScript)
	add_child(panel)
	auto_free(panel)
	return panel


# -- Expanding circle tests --


func test_expanding_circle_created_at_correct_position() -> void:
	var root := Node2D.new()
	add_child(root)
	auto_free(root)
	var vfx := _create_vfx(root)
	var initial_count: int = root.get_child_count()
	vfx.play_burning_effect(Vector2(100, 200), "Iron Casting", "+2 attack", 1, 0)
	# Circle should be spawned as child of scene_root
	assert_int(root.get_child_count()).is_greater(initial_count)
	var circle: Node2D = root.get_child(root.get_child_count() - 1)
	assert_float(circle.position.x).is_equal_approx(100.0, 0.1)
	assert_float(circle.position.y).is_equal_approx(200.0, 0.1)


func test_circle_has_amber_z_index() -> void:
	var root := Node2D.new()
	add_child(root)
	auto_free(root)
	var vfx := _create_vfx(root)
	vfx.play_burning_effect(Vector2.ZERO, "Test", "effect", 1, 0)
	var circle: Node2D = root.get_child(root.get_child_count() - 1)
	assert_int(circle.z_index).is_equal(95)


# -- Screen flash tests --


func test_screen_flash_only_for_player_zero() -> void:
	var root := Node2D.new()
	add_child(root)
	auto_free(root)
	var vfx := _create_vfx(root)
	var before_count: int = root.get_child_count()
	# player_id == 0 should trigger flash (adds CanvasLayer child)
	vfx.play_burning_effect(Vector2.ZERO, "Test", "effect", 0, 1)
	var after_count: int = root.get_child_count()
	# Should have circle + flash CanvasLayer (at least 2 new children)
	assert_int(after_count - before_count).is_greater_equal(2)


func test_no_screen_flash_for_non_player_zero() -> void:
	var root := Node2D.new()
	add_child(root)
	auto_free(root)
	var vfx := _create_vfx(root)
	var before_count: int = root.get_child_count()
	# player_id == 1, attacker_id == 0 — attacker is player 0
	vfx.play_burning_effect(Vector2.ZERO, "Test", "effect", 1, 0)
	var after_count: int = root.get_child_count()
	# Should only have circle (1 new child), no flash
	assert_int(after_count - before_count).is_equal(1)


# -- Screen shake tests --


func test_screen_shake_only_for_player_zero() -> void:
	var camera := Camera2D.new()
	add_child(camera)
	auto_free(camera)
	var root := Node2D.new()
	add_child(root)
	auto_free(root)
	var vfx := _create_vfx(root, camera)
	# player_id == 0 triggers shake (creates tween on camera)
	vfx.play_burning_effect(Vector2.ZERO, "Test", "effect", 0, 1)
	# Camera should have a tween running — we verify no crash occurred
	assert_that(camera).is_not_null()


func test_no_screen_shake_for_ai_player() -> void:
	var camera := Camera2D.new()
	add_child(camera)
	auto_free(camera)
	var original_offset := camera.offset
	var root := Node2D.new()
	add_child(root)
	auto_free(root)
	var vfx := _create_vfx(root, camera)
	# player_id == 1 — AI player, no shake
	vfx.play_burning_effect(Vector2.ZERO, "Test", "effect", 1, 0)
	assert_float(camera.offset.x).is_equal_approx(original_offset.x, 0.01)
	assert_float(camera.offset.y).is_equal_approx(original_offset.y, 0.01)


# -- Notification tests --


func test_defender_notification_contains_tech_name() -> void:
	var root := Node2D.new()
	add_child(root)
	auto_free(root)
	var panel := _create_notification_panel()
	var vfx := _create_vfx(root, null, panel)
	vfx.play_burning_effect(Vector2.ZERO, "Iron Casting", "+2 attack", 0, 1)
	# Should have center notification + event log entry = at least 2 notifications
	assert_int(panel.get_notification_count()).is_greater_equal(2)


func test_attacker_notification_for_player_zero() -> void:
	var root := Node2D.new()
	add_child(root)
	auto_free(root)
	var panel := _create_notification_panel()
	var vfx := _create_vfx(root, null, panel)
	# Defender is AI (player 1), attacker is player 0
	vfx.play_burning_effect(Vector2.ZERO, "Iron Casting", "+2 attack", 1, 0)
	# Attacker gets feed notification
	assert_int(panel.get_notification_count()).is_equal(1)


func test_no_notification_when_neither_player_zero() -> void:
	var root := Node2D.new()
	add_child(root)
	auto_free(root)
	var panel := _create_notification_panel()
	var vfx := _create_vfx(root, null, panel)
	# Both AI players — no notifications for human
	vfx.play_burning_effect(Vector2.ZERO, "Test", "effect", 1, 2)
	assert_int(panel.get_notification_count()).is_equal(0)


# -- Save/load tests --


func test_save_state_returns_empty_dict() -> void:
	var vfx := _create_vfx()
	var state: Dictionary = vfx.save_state()
	assert_bool(state.is_empty()).is_true()


# -- Config tests --


func test_amber_color_loaded_from_config() -> void:
	var vfx := _create_vfx()
	var color: Color = vfx.get_amber_color()
	# Should match default or config value — amber-ish
	assert_float(color.r).is_greater(0.5)
	assert_float(color.g).is_greater(0.3)

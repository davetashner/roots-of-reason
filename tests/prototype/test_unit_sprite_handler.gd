extends GdUnitTestSuite

const UnitSpriteHandlerScript := preload("res://scripts/prototype/unit_sprite_handler.gd")

const ARCHER_CONFIG := "res://data/units/sprites/archer.json"
const DIRECTIONS := ["s", "se", "e", "ne", "n", "nw", "w", "sw"]
const FACING_VECTORS := {
	"s": Vector2(0, 1),
	"se": Vector2(1, 1),
	"e": Vector2(1, 0),
	"ne": Vector2(1, -1),
	"n": Vector2(0, -1),
	"nw": Vector2(-1, -1),
	"w": Vector2(-1, 0),
	"sw": Vector2(-1, 1),
}

var _unit: Node2D
var _handler: RefCounted


func before_test() -> void:
	_unit = Node2D.new()
	add_child(_unit)


func after_test() -> void:
	if _handler != null:
		_handler.cleanup()
		_handler = null
	if _unit != null and is_instance_valid(_unit):
		_unit.queue_free()
		_unit = null


func _create_handler(config_path: String = ARCHER_CONFIG) -> RefCounted:
	_handler = UnitSpriteHandlerScript.new(_unit, "archer", Color.RED, config_path)
	return _handler


# -- Config loading --


func test_archer_config_loads_frame_duration() -> void:
	_create_handler()
	assert_float(_handler._frame_duration).is_equal(0.3)


func test_archer_config_loads_scale() -> void:
	_create_handler()
	var sprite: Sprite2D = _handler.get_sprite()
	assert_float(sprite.scale.x).is_equal(0.5)
	assert_float(sprite.scale.y).is_equal(0.5)


func test_archer_config_loads_offset_y() -> void:
	_create_handler()
	var sprite: Sprite2D = _handler.get_sprite()
	assert_float(sprite.offset.y).is_equal(-16.0)


# -- Manifest / texture loading --


func test_archer_textures_populated() -> void:
	_create_handler()
	# 6 game states mapped from 4 manifest anims:
	#   attack(6) + death(6) + idle(4) + walk(8) + gather(4) + build(4) = 32 per dir
	# 32 * 8 dirs = 256 total textures
	assert_int(_handler._textures.size()).is_equal(256)


func test_archer_idle_sequence_has_four_frames() -> void:
	_create_handler()
	for dir: String in DIRECTIONS:
		var seq: Array = _handler._anim_sequences.get("idle_" + dir, [])
		assert_int(seq.size()).is_equal(4)


func test_archer_attack_sequence_has_six_frames() -> void:
	_create_handler()
	for dir: String in DIRECTIONS:
		var seq: Array = _handler._anim_sequences.get("attack_" + dir, [])
		assert_int(seq.size()).is_equal(6)


func test_archer_walk_sequence_has_eight_frames() -> void:
	_create_handler()
	for dir: String in DIRECTIONS:
		var seq: Array = _handler._anim_sequences.get("walk_" + dir, [])
		assert_int(seq.size()).is_equal(8)


func test_archer_death_sequence_has_six_frames() -> void:
	_create_handler()
	for dir: String in DIRECTIONS:
		var seq: Array = _handler._anim_sequences.get("death_" + dir, [])
		assert_int(seq.size()).is_equal(6)


# -- Animation state mapping --


func test_gather_has_own_sequences() -> void:
	_create_handler()
	# Archer config maps gather -> ["idle"], so gather gets its own sequences
	# with the same textures as idle (4 frames per direction)
	for dir: String in DIRECTIONS:
		var seq: Array = _handler._anim_sequences.get("gather_" + dir, [])
		assert_int(seq.size()).is_equal(4)


func test_build_has_own_sequences() -> void:
	_create_handler()
	# Archer config maps build -> ["idle"], so build gets its own sequences
	for dir: String in DIRECTIONS:
		var seq: Array = _handler._anim_sequences.get("build_" + dir, [])
		assert_int(seq.size()).is_equal(4)


func test_gather_renders_texture() -> void:
	_create_handler()
	_handler.update("gather", FACING_VECTORS["s"], 0.0)
	var sprite: Sprite2D = _handler.get_sprite()
	assert_object(sprite.texture).is_not_null()


func test_build_renders_texture() -> void:
	_create_handler()
	_handler.update("build", FACING_VECTORS["s"], 0.0)
	var sprite: Sprite2D = _handler.get_sprite()
	assert_object(sprite.texture).is_not_null()


# -- Direction lookup --


func test_all_directions_produce_idle_texture() -> void:
	_create_handler()
	for dir: String in DIRECTIONS:
		_handler.update("idle", FACING_VECTORS[dir], 0.0)
		var sprite: Sprite2D = _handler.get_sprite()
		assert_object(sprite.texture).is_not_null()


func test_all_directions_produce_walk_texture() -> void:
	_create_handler()
	for dir: String in DIRECTIONS:
		_handler.update("walk", FACING_VECTORS[dir], 0.0)
		var sprite: Sprite2D = _handler.get_sprite()
		assert_object(sprite.texture).is_not_null()


func test_all_directions_produce_attack_texture() -> void:
	_create_handler()
	for dir: String in DIRECTIONS:
		_handler.update("attack", FACING_VECTORS[dir], 0.0)
		var sprite: Sprite2D = _handler.get_sprite()
		assert_object(sprite.texture).is_not_null()


# -- Death animation clamping --


func test_death_clamps_to_last_frame() -> void:
	_create_handler()
	var facing := FACING_VECTORS["s"]
	# Advance well past the last frame (6 frames * 0.3s = 1.8s, advance 3.0s)
	_handler.update("death", facing, 0.0)
	for i in range(20):
		_handler.update("death", facing, 0.3)
	# Frame should be clamped to 5 (last index of 6-frame sequence)
	assert_int(_handler._current_frame).is_equal(5)


# -- has_death_animation --


func test_has_death_animation_true_for_archer() -> void:
	_create_handler()
	assert_bool(_handler.has_death_animation()).is_true()


# -- Sprite child management --


func test_sprite_added_as_child_of_unit() -> void:
	_create_handler()
	var sprite: Sprite2D = _handler.get_sprite()
	assert_object(sprite.get_parent()).is_same(_unit)


func test_cleanup_frees_sprite() -> void:
	_create_handler()
	var sprite: Sprite2D = _handler.get_sprite()
	_handler.cleanup()
	# After cleanup, sprite should be queued for free
	assert_object(_handler.get_sprite()).is_null()


# -- Graceful missing manifest --


func test_missing_config_does_not_crash() -> void:
	_handler = UnitSpriteHandlerScript.new(
		_unit, "nonexistent_unit", Color.RED, "res://data/units/sprites/nonexistent.json"
	)
	assert_int(_handler._textures.size()).is_equal(0)
	assert_bool(_handler.has_death_animation()).is_false()


func test_missing_manifest_still_creates_sprite() -> void:
	_handler = UnitSpriteHandlerScript.new(
		_unit, "nonexistent_unit", Color.RED, "res://data/units/sprites/nonexistent.json"
	)
	var sprite: Sprite2D = _handler.get_sprite()
	assert_object(sprite).is_not_null()


# -- Frame advancement --


func test_frame_advances_after_duration() -> void:
	_create_handler()
	var facing := FACING_VECTORS["s"]
	_handler.update("idle", facing, 0.0)
	assert_int(_handler._current_frame).is_equal(0)
	_handler.update("idle", facing, 0.3)
	assert_int(_handler._current_frame).is_equal(1)


func test_frame_wraps_around() -> void:
	_create_handler()
	var facing := FACING_VECTORS["s"]
	_handler.update("idle", facing, 0.0)
	# idle has 4 frames, advance past frame 3
	for i in range(4):
		_handler.update("idle", facing, 0.3)
	assert_int(_handler._current_frame).is_equal(0)


func test_animation_change_resets_frame() -> void:
	_create_handler()
	var facing := FACING_VECTORS["s"]
	_handler.update("idle", facing, 0.0)
	_handler.update("idle", facing, 0.3)
	assert_int(_handler._current_frame).is_equal(1)
	# Switch to walk — frame should reset
	_handler.update("walk", facing, 0.0)
	assert_int(_handler._current_frame).is_equal(0)


# -- Fallback chain --


func test_unknown_anim_falls_back_to_idle() -> void:
	_create_handler()
	_handler.update("nonexistent_state", FACING_VECTORS["s"], 0.0)
	var sprite: Sprite2D = _handler.get_sprite()
	assert_object(sprite.texture).is_not_null()


func test_chop_falls_back_through_gather_to_idle() -> void:
	_create_handler()
	# _ANIM_FALLBACKS maps chop -> gather, and archer has no gather sequences
	# (gather is mapped to idle at config level, but stored as idle keys)
	# So chop -> gather (miss) -> idle (hit)
	_handler.update("chop", FACING_VECTORS["e"], 0.0)
	var sprite: Sprite2D = _handler.get_sprite()
	assert_object(sprite.texture).is_not_null()

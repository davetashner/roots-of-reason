extends RefCounted
## UnitSpriteHandler — manages a Sprite2D child on a unit node, loading textures
## from a manifest-based sprite set and swapping frames for animation.
##
## Follows the same RefCounted component pattern as GathererComponent and
## CombatantComponent.

const SHADER_PATH := "res://assets/shaders/player_color.gdshader"
## Fallback map: if an animation has no frames for a direction, try this animation first.
const _ANIM_FALLBACKS := {"chop": "gather"}

var _unit: Node2D = null
var _sprite: Sprite2D = null
var _textures: Dictionary = {}  # "anim_dir_frame" -> Texture2D
var _anim_sequences: Dictionary = {}  # "anim_dir" -> Array[String] (texture keys)
var _current_anim: String = "idle"
var _current_dir: String = "s"
var _current_frame: int = 0
var _frame_timer: float = 0.0
var _frame_duration: float = 0.3
var _variant: String = ""
var _config: Dictionary = {}
var _has_death_anim: bool = false


func _init(unit: Node2D, variant: String, player_color: Color, config_path: String = "") -> void:
	_unit = unit
	_variant = variant
	_load_config(config_path)
	_create_sprite(player_color)
	_load_textures()


func _load_config(config_path: String = "") -> void:
	var path := config_path if config_path != "" else "res://data/units/sprites/villager.json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_config = parsed
		_frame_duration = float(_config.get("frame_duration", 0.3))


func _create_sprite(player_color: Color) -> void:
	_sprite = Sprite2D.new()
	_sprite.z_index = 0
	_sprite.centered = true
	var offset_y: float = float(_config.get("offset_y", -16.0))
	_sprite.offset = Vector2(0.0, offset_y)
	var sprite_scale: float = float(_config.get("scale", 0.5))
	_sprite.scale = Vector2(sprite_scale, sprite_scale)
	# Apply player color shader
	var shader: Shader = load(SHADER_PATH) as Shader
	if shader != null:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("player_color", player_color)
		_sprite.material = mat
	_unit.add_child(_sprite)


func _load_textures() -> void:
	var base_path: String = _config.get("base_path", "res://assets/sprites/units")
	var manifest_path := base_path + "/" + _variant + "/manifest.json"
	var file := FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null or not (parsed is Dictionary):
		return
	var manifest: Dictionary = parsed
	var sprites: Array = manifest.get("sprites", [])
	# Build animation map for this variant
	var anim_map: Dictionary = {}
	var all_anim_maps: Dictionary = _config.get("animation_map", {})
	if all_anim_maps.has(_variant):
		anim_map = all_anim_maps[_variant]
	# Check if this variant has death animations
	var death_anims: Array = anim_map.get("death", [])
	_has_death_anim = not death_anims.is_empty()
	# Build reverse map: manifest_anim -> game_state
	var manifest_to_game: Dictionary = {}  # manifest anim name -> game state
	for game_state: String in anim_map.keys():
		var manifest_anims: Array = anim_map[game_state]
		for ma: String in manifest_anims:
			manifest_to_game[ma] = game_state
	# Load all sprite textures
	for entry: Dictionary in sprites:
		var filename: String = entry.get("filename", "")
		var anim: String = entry.get("animation", "")
		var direction: String = entry.get("direction", "")
		var frame: int = int(entry.get("frame", 1))
		if filename == "" or anim == "" or direction == "":
			continue
		# Map manifest animation to game state
		var game_state: String = manifest_to_game.get(anim, "")
		if game_state == "":
			continue
		var tex_path := base_path + "/" + _variant + "/" + filename
		var tex: Texture2D = load(tex_path) as Texture2D
		if tex == null:
			continue
		# For animations with multiple manifest anims (e.g., build_a, build_b),
		# we chain them into one sequence. Use a sub-index based on manifest anim order.
		var manifest_anims: Array = anim_map.get(game_state, [])
		var anim_offset: int = manifest_anims.find(anim)
		if anim_offset < 0:
			anim_offset = 0
		# Compute a global frame index that chains sub-animations
		var prev_frames := _count_prev_frames(
			sprites, manifest_anims, anim_offset, direction, manifest_to_game, game_state
		)
		var global_frame: int = prev_frames + frame - 1
		var key := game_state + "_" + direction + "_" + str(global_frame)
		_textures[key] = tex
	# Build sequences: for each "anim_dir", store the ordered list of keys
	_build_sequences()


func _count_prev_frames(
	sprites: Array,
	manifest_anims: Array,
	anim_offset: int,
	direction: String,
	manifest_to_game: Dictionary,
	game_state: String,
) -> int:
	var count: int = 0
	for i in range(anim_offset):
		var prev_anim: String = manifest_anims[i]
		for entry: Dictionary in sprites:
			if entry.get("animation", "") == prev_anim and entry.get("direction", "") == direction:
				var gs: String = manifest_to_game.get(prev_anim, "")
				if gs == game_state:
					count += 1
	return count


func _build_sequences() -> void:
	_anim_sequences.clear()
	for key: String in _textures.keys():
		# key format: "state_dir_frame"
		var parts := key.rsplit("_", true, 1)  # Split off frame number
		if parts.size() < 2:
			continue
		var seq_key: String = parts[0]  # "state_dir"
		if not _anim_sequences.has(seq_key):
			_anim_sequences[seq_key] = []
		_anim_sequences[seq_key].append(key)
	# Sort each sequence by frame index
	for seq_key: String in _anim_sequences.keys():
		var arr: Array = _anim_sequences[seq_key]
		arr.sort()


func update(state: String, facing: Vector2, delta: float) -> void:
	var dir := DirectionUtils.facing_to_direction(facing)
	var anim_changed := state != _current_anim or dir != _current_dir
	_current_anim = state
	_current_dir = dir
	if anim_changed:
		_current_frame = 0
		_frame_timer = 0.0
	# Advance frame timer
	_frame_timer += delta
	if _frame_timer >= _frame_duration:
		_frame_timer -= _frame_duration
		_current_frame += 1
	# Get the sequence for current state + direction
	var seq_key := _current_anim + "_" + _current_dir
	var seq: Array = _anim_sequences.get(seq_key, [])
	# Fallback: resource-specific anims fall back to generic gather, then idle
	if seq.is_empty() and _current_anim != "idle":
		var fallback: String = _ANIM_FALLBACKS.get(_current_anim, "idle")
		seq_key = fallback + "_" + _current_dir
		seq = _anim_sequences.get(seq_key, [])
	if seq.is_empty() and _current_anim != "idle":
		seq_key = "idle_" + _current_dir
		seq = _anim_sequences.get(seq_key, [])
	if seq.is_empty():
		# Last resort: try idle_s
		seq = _anim_sequences.get("idle_s", [])
	if seq.is_empty():
		return
	# For death animation, clamp to last frame instead of looping
	if _current_anim == "death":
		_current_frame = mini(_current_frame, seq.size() - 1)
	else:
		_current_frame = _current_frame % seq.size()
	var tex_key: String = seq[_current_frame]
	var tex: Texture2D = _textures.get(tex_key)
	if tex != null:
		_sprite.texture = tex
	# Handle mirrored directions: flip_h for opposite facing
	_sprite.flip_h = _is_mirrored_direction(dir)


func _is_mirrored_direction(_dir: String) -> bool:
	# All directions have their own PNG files — no runtime flipping needed.
	return false


func has_death_animation() -> bool:
	return _has_death_anim


func get_sprite() -> Sprite2D:
	return _sprite


func cleanup() -> void:
	if _sprite != null and is_instance_valid(_sprite):
		_sprite.queue_free()
		_sprite = null

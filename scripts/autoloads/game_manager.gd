extends Node
## Global game state manager.
## Manages game clock, pause state, and game-wide events.

signal game_paused
signal game_resumed
signal game_speed_changed(speed: float)
signal age_advanced(new_age: int)

const AGE_NAMES: Array[String] = [
	"Stone Age", "Bronze Age", "Iron Age", "Medieval Age", "Industrial Age", "Information Age", "Singularity Age"
]

var is_paused: bool = false
var game_speed: float = 1.0
var game_time: float = 0.0
var current_age: int = 0  # 0=Stone, 1=Bronze, ..., 6=Singularity
var ai_difficulty: String = "normal"

## {player_id: String} — civilization ID per player (e.g. "mesopotamia")
var player_civilizations: Dictionary = {}

var _speed_steps: Array = [1.0, 1.5, 2.0, 3.0]
var _speed_index: int = 0
var _pause_action: String = "ui_pause"
var _speed_up_action: String = "ui_speed_up"
var _speed_down_action: String = "ui_speed_down"


func _ready() -> void:
	_load_config()


func _load_config() -> void:
	var config: Dictionary = DataLoader.get_settings("game_clock")
	if config.is_empty():
		return
	if config.has("speed_steps"):
		_speed_steps = config["speed_steps"]
		game_speed = _speed_steps[0]
		_speed_index = 0
	if config.has("pause_action"):
		_pause_action = config["pause_action"]
	if config.has("speed_up_action"):
		_speed_up_action = config["speed_up_action"]
	if config.has("speed_down_action"):
		_speed_down_action = config["speed_down_action"]


func _process(delta: float) -> void:
	if not is_paused:
		game_time += delta * game_speed


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if InputMap.has_action(_pause_action) and event.is_action_pressed(_pause_action):
		toggle_pause()
		get_viewport().set_input_as_handled()
	elif InputMap.has_action(_speed_up_action) and event.is_action_pressed(_speed_up_action):
		step_speed(1)
		get_viewport().set_input_as_handled()
	elif InputMap.has_action(_speed_down_action) and event.is_action_pressed(_speed_down_action):
		step_speed(-1)
		get_viewport().set_input_as_handled()


func get_game_delta(delta: float) -> float:
	if is_paused:
		return 0.0
	return delta * game_speed


func toggle_pause() -> void:
	if is_paused:
		resume()
	else:
		pause()


func pause() -> void:
	is_paused = true
	game_paused.emit()


func resume() -> void:
	is_paused = false
	game_resumed.emit()


func step_speed(direction: int) -> void:
	var new_index := clampi(_speed_index + direction, 0, _speed_steps.size() - 1)
	if new_index == _speed_index:
		return
	_speed_index = new_index
	game_speed = _speed_steps[_speed_index]
	game_speed_changed.emit(game_speed)


func set_speed(speed: float) -> void:
	for i in range(_speed_steps.size()):
		if is_equal_approx(_speed_steps[i], speed):
			_speed_index = i
			game_speed = speed
			game_speed_changed.emit(game_speed)
			return
	push_warning("GameManager: speed %.1f not in speed_steps, ignoring" % speed)


func get_clock_display() -> String:
	var total_seconds: int = int(game_time)
	@warning_ignore("integer_division")
	var minutes: int = total_seconds / 60
	@warning_ignore("integer_division")
	var seconds: int = total_seconds % 60
	return "%02d:%02d" % [minutes, seconds]


func get_speed_display() -> String:
	if is_equal_approx(game_speed, floorf(game_speed)):
		return "%dx" % int(game_speed)
	return "%sx" % str(game_speed)


func get_age_name() -> String:
	assert(current_age >= 0 and current_age < AGE_NAMES.size(), "current_age %d out of range" % current_age)
	if current_age < 0 or current_age >= AGE_NAMES.size():
		push_error("GameManager: current_age %d out of range [0, %d]" % [current_age, AGE_NAMES.size() - 1])
		return AGE_NAMES[0]
	return AGE_NAMES[current_age]


func advance_age(new_age: int) -> void:
	if new_age < 0 or new_age >= AGE_NAMES.size():
		push_error("GameManager: advance_age(%d) out of range [0, %d]" % [new_age, AGE_NAMES.size() - 1])
		return
	current_age = new_age
	age_advanced.emit(new_age)


func set_player_civilization(player_id: int, civ_id: String) -> void:
	## Assigns a civilization to a player.
	player_civilizations[player_id] = civ_id


func get_player_civilization(player_id: int) -> String:
	## Returns the civilization ID for a player, or "" if unset.
	return player_civilizations.get(player_id, "")


func save_state() -> Dictionary:
	return {
		"game_time": game_time,
		"game_speed": game_speed,
		"speed_index": _speed_index,
		"is_paused": is_paused,
		"current_age": current_age,
		"ai_difficulty": ai_difficulty,
		"player_civilizations": player_civilizations.duplicate(),
	}


func load_state(data: Dictionary) -> void:
	game_time = float(data.get("game_time", 0.0))
	game_speed = float(data.get("game_speed", 1.0))
	_speed_index = int(data.get("speed_index", 0))
	is_paused = bool(data.get("is_paused", false))
	var age: int = int(data.get("current_age", 0))
	if age < 0 or age >= AGE_NAMES.size():
		push_warning("GameManager: Invalid current_age %d in save data, defaulting to 0" % age)
		age = 0
	current_age = age
	ai_difficulty = str(data.get("ai_difficulty", "normal"))
	# Restore player civilizations (JSON round-trip gives string keys)
	player_civilizations = {}
	var raw_civs: Dictionary = data.get("player_civilizations", {})
	for key: Variant in raw_civs:
		player_civilizations[int(key)] = str(raw_civs[key])

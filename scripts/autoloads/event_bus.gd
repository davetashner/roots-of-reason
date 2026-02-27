extends Node
## Global event bus for cross-system communication.
## Provides typed signals so systems can communicate without direct references.
## Toggle debug_logging to see all events in the output console.

# --- Resource events ---
signal resource_changed(player_id: int, resource_type: String, old_amount: int, new_amount: int)

# --- Unit events ---
signal unit_spawned(unit: Node2D, owner_id: int, unit_type: String)
signal unit_died(unit: Node2D, killer: Node2D, owner_id: int)

# --- Building events ---
signal building_placed(building: Node2D, owner_id: int, building_type: String)
signal building_destroyed(building: Node2D, owner_id: int)

# --- Tech events ---
signal tech_completed(player_id: int, tech_id: String, effects: Dictionary)
signal tech_regressed(player_id: int, tech_id: String)

# --- Combat events ---
signal combat_event(attacker: Node2D, defender: Node2D, damage: int)
signal knowledge_burned(attacker_id: int, defender_id: int, regressed_techs: Array)

# --- Victory events ---
signal victory_condition_met(player_id: int, condition: String)
signal player_defeated(player_id: int)

# --- Age events ---
signal age_advanced(player_id: int, new_age: int)

const MAX_LOG_SIZE: int = 200

## When true, all emitted events are printed to the console for debugging.
var debug_logging: bool = false

## Rolling buffer of recent events for debugging and replay.
var _event_log: Array[Dictionary] = []


func _ready() -> void:
	_connect_resource_relay()


func _connect_resource_relay() -> void:
	## Automatically relay ResourceManager.resources_changed through the bus.
	if ResourceManager != null:
		ResourceManager.resources_changed.connect(_on_resource_changed)


func _on_resource_changed(player_id: int, resource_type: String, old_amount: int, new_amount: int) -> void:
	emit_resource_changed(player_id, resource_type, old_amount, new_amount)


# --- Typed emit helpers ---


func emit_resource_changed(player_id: int, resource_type: String, old_amount: int, new_amount: int) -> void:
	var data: Dictionary = {
		"player_id": player_id,
		"resource_type": resource_type,
		"old": old_amount,
		"new": new_amount,
	}
	_log_event("resource_changed", data)
	resource_changed.emit(player_id, resource_type, old_amount, new_amount)


func emit_unit_spawned(unit: Node2D, owner_id: int, unit_type: String) -> void:
	_log_event("unit_spawned", {"owner_id": owner_id, "unit_type": unit_type})
	unit_spawned.emit(unit, owner_id, unit_type)


func emit_unit_died(unit: Node2D, killer: Node2D, owner_id: int) -> void:
	_log_event("unit_died", {"owner_id": owner_id, "killer": killer})
	unit_died.emit(unit, killer, owner_id)


func emit_building_placed(building: Node2D, owner_id: int, building_type: String) -> void:
	_log_event(
		"building_placed",
		{"owner_id": owner_id, "building_type": building_type},
	)
	building_placed.emit(building, owner_id, building_type)


func emit_building_destroyed(building: Node2D, owner_id: int) -> void:
	_log_event("building_destroyed", {"owner_id": owner_id})
	building_destroyed.emit(building, owner_id)


func emit_tech_completed(player_id: int, tech_id: String, effects: Dictionary) -> void:
	_log_event(
		"tech_completed",
		{"player_id": player_id, "tech_id": tech_id},
	)
	tech_completed.emit(player_id, tech_id, effects)


func emit_tech_regressed(player_id: int, tech_id: String) -> void:
	_log_event(
		"tech_regressed",
		{"player_id": player_id, "tech_id": tech_id},
	)
	tech_regressed.emit(player_id, tech_id)


func emit_combat_event(attacker: Node2D, defender: Node2D, damage: int) -> void:
	_log_event("combat_event", {"damage": damage})
	combat_event.emit(attacker, defender, damage)


func emit_knowledge_burned(attacker_id: int, defender_id: int, regressed_techs: Array) -> void:
	_log_event(
		"knowledge_burned",
		{
			"attacker_id": attacker_id,
			"defender_id": defender_id,
			"count": regressed_techs.size(),
		},
	)
	knowledge_burned.emit(attacker_id, defender_id, regressed_techs)


func emit_victory_condition_met(player_id: int, condition: String) -> void:
	_log_event(
		"victory_condition_met",
		{"player_id": player_id, "condition": condition},
	)
	victory_condition_met.emit(player_id, condition)


func emit_player_defeated(player_id: int) -> void:
	_log_event("player_defeated", {"player_id": player_id})
	player_defeated.emit(player_id)


func emit_age_advanced(player_id: int, new_age: int) -> void:
	_log_event(
		"age_advanced",
		{"player_id": player_id, "new_age": new_age},
	)
	age_advanced.emit(player_id, new_age)


# --- Logging ---


func _log_event(event_name: String, data: Dictionary) -> void:
	var entry: Dictionary = {
		"event": event_name,
		"data": data,
		"time": Time.get_ticks_msec(),
	}
	_event_log.append(entry)
	if _event_log.size() > MAX_LOG_SIZE:
		_event_log.pop_front()
	if debug_logging:
		print("[EventBus] %s: %s" % [event_name, str(data)])


func get_event_log() -> Array[Dictionary]:
	## Returns a copy of the event log.
	return _event_log.duplicate()


func clear_event_log() -> void:
	_event_log.clear()


func get_events_by_type(event_name: String) -> Array[Dictionary]:
	## Returns all logged events matching the given name.
	var result: Array[Dictionary] = []
	for entry: Dictionary in _event_log:
		if entry["event"] == event_name:
			result.append(entry)
	return result


# --- Save/Load ---


func save_state() -> Dictionary:
	return {"debug_logging": debug_logging}


func load_state(data: Dictionary) -> void:
	debug_logging = bool(data.get("debug_logging", false))


func reset() -> void:
	debug_logging = false
	_event_log.clear()

## Chainable helper for building complex game scenarios in integration tests.
## Delegates to DebugAPI for all state manipulation — never touches singletons directly.
##
## Usage:
##   const ScenarioBuilder = preload("res://tests/helpers/scenario_builder.gd")
##   var sb := ScenarioBuilder.new()
##   sb.set_civ(0, "rome").give_resources(0, {"food": 500, "wood": 300}).execute()
extends RefCounted

const DebugApiScript := preload("res://scripts/debug/debug_api.gd")

## Internal record of deferred operations, applied in order on execute().
var _steps: Array[Dictionary] = []

## Scene root override — if null, DebugAPI will use the current scene.
var _scene_root: Node = null


## Set the scene root node used for spawning units and buildings.
func with_scene_root(root: Node) -> RefCounted:
	_scene_root = root
	return self


## Configure a player's civilization, applying all bonuses.
func set_civ(player_id: int, civ_name: String) -> RefCounted:
	(
		_steps
		. append(
			{
				"type": "set_civ",
				"player_id": player_id,
				"civ_name": civ_name,
			}
		)
	)
	return self


## Advance a player to the specified age, auto-researching prerequisites.
func set_age(player_id: int, age_name: String) -> RefCounted:
	(
		_steps
		. append(
			{
				"type": "set_age",
				"player_id": player_id,
				"age_name": age_name,
			}
		)
	)
	return self


## Set exact resource amounts for a player.
## resource_dict maps lowercase resource name strings to integer amounts,
## e.g. {"food": 500, "wood": 300, "stone": 200, "gold": 100, "knowledge": 0}.
func give_resources(player_id: int, resource_dict: Dictionary) -> RefCounted:
	(
		_steps
		. append(
			{
				"type": "give_resources",
				"player_id": player_id,
				"resources": resource_dict,
			}
		)
	)
	return self


## Spawn units of a given type at a grid position.
func spawn_units(player_id: int, unit_type: String, count: int, grid_pos: Vector2i) -> RefCounted:
	(
		_steps
		. append(
			{
				"type": "spawn_units",
				"player_id": player_id,
				"unit_type": unit_type,
				"count": count,
				"grid_pos": grid_pos,
			}
		)
	)
	return self


## Place a fully-constructed building at a grid position.
func build(player_id: int, building_type: String, grid_pos: Vector2i) -> RefCounted:
	(
		_steps
		. append(
			{
				"type": "build",
				"player_id": player_id,
				"building_type": building_type,
				"grid_pos": grid_pos,
			}
		)
	)
	return self


## Apply all deferred steps in order. Returns self for further chaining.
func execute() -> RefCounted:
	for step: Dictionary in _steps:
		_apply_step(step)
	_steps.clear()
	return self


## Return the number of pending (unexecuted) steps.
func pending_step_count() -> int:
	return _steps.size()


func _apply_step(step: Dictionary) -> void:
	match step["type"]:
		"set_civ":
			_apply_set_civ(step)
		"set_age":
			_apply_set_age(step)
		"give_resources":
			_apply_give_resources(step)
		"spawn_units":
			_apply_spawn_units(step)
		"build":
			_apply_build(step)
		_:
			push_warning("ScenarioBuilder: unknown step type '%s'" % str(step["type"]))


func _apply_set_civ(step: Dictionary) -> void:
	var pid: int = int(step["player_id"])
	var civ: String = str(step["civ_name"])
	# Ensure player exists in ResourceManager before applying civ bonuses
	if not ResourceManager.has_player(pid):
		ResourceManager.init_player(pid, {})
	GameManager.set_player_civilization(pid, civ)
	CivBonusManager.apply_civ_bonuses(pid, civ)
	CivBonusManager.apply_starting_bonuses(pid)


func _apply_set_age(step: Dictionary) -> void:
	var pid: int = int(step["player_id"])
	var age: String = str(step["age_name"])
	DebugApiScript.set_age(age, pid)


func _apply_give_resources(step: Dictionary) -> void:
	var pid: int = int(step["player_id"])
	var resources: Dictionary = step["resources"]
	if not ResourceManager.has_player(pid):
		ResourceManager.init_player(pid, {})
	for key: String in resources:
		var lower := key.to_lower()
		if lower not in DebugApiScript.RESOURCE_STRING_TO_TYPE:
			push_warning("ScenarioBuilder: unknown resource '%s'" % key)
			continue
		var rt: ResourceManager.ResourceType = DebugApiScript.RESOURCE_STRING_TO_TYPE[lower]
		ResourceManager.set_resource(pid, rt, int(resources[key]))


func _apply_spawn_units(step: Dictionary) -> void:
	var pid: int = int(step["player_id"])
	var utype: String = str(step["unit_type"])
	var count: int = int(step["count"])
	var gpos: Vector2i = step["grid_pos"]
	DebugApiScript.spawn_unit(utype, pid, gpos, count, _scene_root)


func _apply_build(step: Dictionary) -> void:
	var pid: int = int(step["player_id"])
	var btype: String = str(step["building_type"])
	var gpos: Vector2i = step["grid_pos"]
	DebugApiScript.spawn_building(btype, pid, gpos, _scene_root)

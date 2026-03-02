extends RefCounted
## Tracks idle villagers and provides round-robin cycling through them.
## Used by the HUD button and period-key hotkey to locate idle villagers.

var _units_ref: Array[Node] = []
var _cycle_index: int = -1


func setup(units: Array[Node]) -> void:
	_units_ref = units


func get_idle_villagers() -> Array[Node]:
	var result: Array[Node] = []
	for unit in _units_ref:
		if not is_instance_valid(unit):
			continue
		if not ("unit_type" in unit and unit.unit_type == "villager"):
			continue
		if "owner_id" in unit and unit.owner_id != 0:
			continue
		if unit.has_method("is_idle") and unit.is_idle():
			result.append(unit)
	return result


func get_idle_count() -> int:
	return get_idle_villagers().size()


func cycle_next() -> Node:
	## Returns the next idle villager in round-robin order, or null if none.
	var idle := get_idle_villagers()
	if idle.is_empty():
		_cycle_index = -1
		return null
	_cycle_index += 1
	if _cycle_index >= idle.size():
		_cycle_index = 0
	return idle[_cycle_index]


func reset_cycle() -> void:
	_cycle_index = -1

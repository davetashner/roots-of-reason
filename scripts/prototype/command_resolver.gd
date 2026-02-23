class_name CommandResolver
extends RefCounted
## Pure-function resolver: maps (unit_type, target_category) to a command string
## using a JSON-driven lookup table. No side effects.


## Resolve a command from unit type and target category using the command table.
## Lookup order: table[unit_type][target_category] → table["default"][target_category] → "move"
static func resolve(unit_type: String, target_category: String, command_table: Dictionary) -> String:
	if command_table.has(unit_type):
		var type_table: Dictionary = command_table[unit_type]
		if type_table.has(target_category):
			return type_table[target_category]
	if command_table.has("default"):
		var default_table: Dictionary = command_table["default"]
		if default_table.has(target_category):
			return default_table[target_category]
	return "move"


## Extract the entity category from a target node.
## Returns "ground" for null targets.
static func get_target_category(target: Node) -> String:
	if target == null:
		return "ground"
	if target.has_method("get_entity_category"):
		return target.get_entity_category()
	if "entity_category" in target:
		return target.entity_category
	return "ground"


## Determine primary unit type from selected units.
## All same unit_type → return it; mixed or empty → "default".
static func get_primary_unit_type(selected_units: Array) -> String:
	if selected_units.is_empty():
		return "default"
	var first_type: String = ""
	for unit in selected_units:
		if not is_instance_valid(unit):
			continue
		var ut: String = unit.unit_type if "unit_type" in unit else "default"
		if first_type == "":
			first_type = ut
		elif ut != first_type:
			return "default"
	if first_type == "":
		return "default"
	return first_type

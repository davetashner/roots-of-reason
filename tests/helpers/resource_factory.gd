## Shared resource node factory for tests. Returns unparented nodes — caller
## must add_child() and auto_free().
##
## Usage:
##   const ResourceFactory = preload("res://tests/helpers/resource_factory.gd")
##   var bush := ResourceFactory.create_resource_node()
##   _root.add_child(bush)
##   auto_free(bush)

const ResourceNodeScript := preload("res://scripts/prototype/prototype_resource_node.gd")


## Create a resource node (berry bush by default).
## Common overrides: position, resource_type, total_yield, name, regenerates,
## resource_name, regen_rate, regen_delay.
static func create_resource_node(overrides: Dictionary = {}) -> Node2D:
	var n := Node2D.new()
	n.set_script(ResourceNodeScript)
	n.resource_name = str(overrides.get("resource_name", "berry_bush"))
	n.resource_type = str(overrides.get("resource_type", "food"))
	var yield_amt: int = int(overrides.get("total_yield", 150))
	n.total_yield = yield_amt
	n.current_yield = int(overrides.get("current_yield", yield_amt))
	n.position = overrides.get("position", Vector2(50, 0))
	n.regenerates = bool(overrides.get("regenerates", false))
	n.regen_rate = float(overrides.get("regen_rate", 0.0))
	n.regen_delay = float(overrides.get("regen_delay", 0.0))
	if overrides.has("name"):
		n.name = str(overrides.get("name"))
	return n

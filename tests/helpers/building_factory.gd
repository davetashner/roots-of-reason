## Shared building factory for tests. Returns unparented nodes — caller must
## add_child() and auto_free().
##
## Usage:
##   const BuildingFactory = preload("res://tests/helpers/building_factory.gd")
##   var tc := BuildingFactory.create_drop_off({position = Vector2(-50, 0)})
##   _root.add_child(tc)
##   auto_free(tc)

const BuildingScript := preload("res://scripts/prototype/prototype_building.gd")


## Create a completed drop-off building (town center by default).
static func create_drop_off(overrides: Dictionary = {}) -> Node2D:
	var b := Node2D.new()
	b.set_script(BuildingScript)
	b.building_name = str(overrides.get("building_name", "town_center"))
	b.is_drop_off = true
	b.drop_off_types = overrides.get("drop_off_types", ["food", "wood", "stone", "gold"] as Array[String])
	b.under_construction = false
	b.build_progress = 1.0
	b.max_hp = int(overrides.get("max_hp", 2400))
	b.hp = int(overrides.get("hp", 2400))
	b.footprint = overrides.get("footprint", Vector2i(3, 3))
	b.grid_pos = overrides.get("grid_pos", Vector2i(4, 4))
	b.position = overrides.get("position", Vector2.ZERO)
	b.owner_id = int(overrides.get("owner_id", 0))
	if overrides.has("name"):
		b.name = str(overrides.get("name"))
	return b


## Create a building under construction (house by default).
static func create_construction(overrides: Dictionary = {}) -> Node2D:
	var b := Node2D.new()
	b.set_script(BuildingScript)
	b.building_name = str(overrides.get("building_name", "house"))
	b.max_hp = int(overrides.get("max_hp", 550))
	b.hp = int(overrides.get("hp", 0))
	b.under_construction = true
	b.build_progress = float(overrides.get("build_progress", 0.0))
	b._build_time = float(overrides.get("build_time", 25.0))
	b.footprint = overrides.get("footprint", Vector2i(2, 2))
	b.grid_pos = overrides.get("grid_pos", Vector2i(5, 5))
	b.position = overrides.get("position", Vector2.ZERO)
	b.owner_id = int(overrides.get("owner_id", 0))
	if overrides.has("name"):
		b.name = str(overrides.get("name"))
	return b


## Create a completed building (house by default, not a drop-off).
static func create_building(overrides: Dictionary = {}) -> Node2D:
	var b := Node2D.new()
	b.set_script(BuildingScript)
	b.building_name = str(overrides.get("building_name", "house"))
	b.max_hp = int(overrides.get("max_hp", 550))
	b.hp = int(overrides.get("hp", 550))
	b.under_construction = false
	b.build_progress = 1.0
	b.footprint = overrides.get("footprint", Vector2i(2, 2))
	b.grid_pos = overrides.get("grid_pos", Vector2i(5, 5))
	b.position = overrides.get("position", Vector2.ZERO)
	b.owner_id = int(overrides.get("owner_id", 0))
	b.entity_category = str(overrides.get("entity_category", "own_building"))
	if overrides.has("name"):
		b.name = str(overrides.get("name"))
	return b

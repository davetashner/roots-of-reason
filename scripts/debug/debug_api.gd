class_name DebugAPI
extends RefCounted
## Static-like API for automated integration tests and the debug console.
## All methods delegate to existing game managers (ResourceManager, GameManager, etc.).
## Not a true autoload — instantiate or call via class methods.

const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")
const BuildingScript := preload("res://scripts/prototype/prototype_building.gd")

## Map of resource name strings to ResourceManager.ResourceType enum values.
const RESOURCE_STRING_TO_TYPE: Dictionary = {
	"food": ResourceManager.ResourceType.FOOD,
	"wood": ResourceManager.ResourceType.WOOD,
	"stone": ResourceManager.ResourceType.STONE,
	"gold": ResourceManager.ResourceType.GOLD,
	"knowledge": ResourceManager.ResourceType.KNOWLEDGE,
}


static func spawn_unit(
	unit_type: String,
	owner_id: int,
	grid_pos: Vector2i,
	count: int = 1,
	scene_root: Node = null,
) -> Array[Node2D]:
	## Spawns one or more units at the given grid position, bypassing cost/pop checks.
	## Returns array of created unit nodes.
	var root: Node = scene_root
	if root == null:
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			root = tree.current_scene
	if root == null:
		push_warning("DebugAPI.spawn_unit: no scene root available")
		return []
	var stats: Dictionary = DataLoader.get_unit_stats(unit_type)
	if stats.is_empty():
		push_warning("DebugAPI.spawn_unit: unknown unit type '%s'" % unit_type)
		return []
	var results: Array[Node2D] = []
	for i: int in range(count):
		var wp := IsoUtils.grid_to_screen(Vector2(grid_pos))
		var u := Node2D.new()
		u.name = "DebugUnit_%s_%d" % [unit_type, root.get_child_count()]
		u.set_script(UnitScript)
		u.unit_type = unit_type
		u.owner_id = owner_id
		u.position = wp
		if owner_id == 1:
			u.unit_color = Color(0.9, 0.2, 0.2)
		root.add_child(u)
		u._scene_root = root
		_register_unit_with_systems(u, root, owner_id)
		results.append(u)
	return results


static func spawn_building(
	building_name: String,
	owner_id: int,
	grid_pos: Vector2i,
	scene_root: Node = null,
) -> Node2D:
	## Spawns a fully-constructed building at the given grid position.
	## Bypasses resource cost checks. Returns the building node or null on failure.
	var root: Node = scene_root
	if root == null:
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			root = tree.current_scene
	if root == null:
		push_warning("DebugAPI.spawn_building: no scene root available")
		return null
	var st: Dictionary = DataLoader.get_building_stats(building_name)
	if st.is_empty():
		push_warning("DebugAPI.spawn_building: unknown building '%s'" % building_name)
		return null
	var mhp: int = int(st.get("hp", 100))
	var fp_arr: Array = st.get("footprint", [1, 1])
	var fp := Vector2i(int(fp_arr[0]), int(fp_arr[1]))
	var b := Node2D.new()
	b.name = "Building_%s_%d_%d" % [building_name, grid_pos.x, grid_pos.y]
	b.set_script(BuildingScript)
	b.position = IsoUtils.grid_to_screen(Vector2(grid_pos))
	b.owner_id = owner_id
	b.building_name = building_name
	b.footprint = fp
	b.grid_pos = grid_pos
	b.max_hp = mhp
	b.entity_category = "own_building" if owner_id == 0 else "enemy_building"
	b.hp = mhp
	b.under_construction = false
	b.build_progress = 1.0
	root.add_child(b)
	_register_building_with_systems(b, root, owner_id, grid_pos, fp)
	return b


static func give_resources(player_id: int, resource_type: String, amount: int) -> void:
	## Adds the specified amount of a resource to the player's stockpile.
	var lower := resource_type.to_lower()
	if lower not in RESOURCE_STRING_TO_TYPE:
		push_warning("DebugAPI.give_resources: unknown resource type '%s'" % resource_type)
		return
	var rt: ResourceManager.ResourceType = RESOURCE_STRING_TO_TYPE[lower]
	if not ResourceManager.has_player(player_id):
		ResourceManager.init_player(player_id, {})
	ResourceManager.add_resource(player_id, rt, amount)


static func give_all_resources(player_id: int, amount: int) -> void:
	## Sets all 5 resource types to the given amount for the player.
	if not ResourceManager.has_player(player_id):
		ResourceManager.init_player(player_id, {})
	for rt: ResourceManager.ResourceType in ResourceManager.ResourceType.values():
		ResourceManager.set_resource(player_id, rt, amount)


static func research_tech(tech_id: String, player_id: int = 0) -> bool:
	## Instantly completes a tech for the player, triggering all effects.
	## Returns true if successful, false if tech not found or already researched.
	var tech_data: Dictionary = DataLoader.get_tech_data(tech_id)
	if tech_data.is_empty():
		push_warning("DebugAPI.research_tech: unknown tech '%s'" % tech_id)
		return false
	var root: Node = null
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		root = tree.current_scene
	var tm: Node = _get_tech_manager(root)
	if tm != null and tm.has_method("is_tech_researched"):
		if tm.is_tech_researched(tech_id, player_id):
			return false
	# Directly add to researched list if TechManager is available
	if tm != null and "_researched_techs" in tm:
		if player_id not in tm._researched_techs:
			tm._researched_techs[player_id] = []
		tm._researched_techs[player_id].append(tech_id)
		var effects: Dictionary = tech_data.get("effects", {})
		if tm.has_signal("tech_researched"):
			tm.tech_researched.emit(player_id, tech_id, effects)
		if tm.has_signal("research_queue_changed"):
			tm.research_queue_changed.emit(player_id)
		# Handle singularity chain techs
		if tech_data.get("singularity_chain", false) and tm.has_signal("singularity_tech_researched"):
			var tech_name: String = str(tech_data.get("name", tech_id))
			tm.singularity_tech_researched.emit(player_id, tech_id, tech_name)
		# Handle victory techs
		if tech_data.get("victory_tech", false) and tm.has_signal("victory_tech_completed"):
			tm.victory_tech_completed.emit(player_id, tech_id)
		return true
	# Fallback: no TechManager, just emit on GameManager if it has the signal
	push_warning("DebugAPI.research_tech: no TechManager found, tech not registered")
	return false


static func research_all(player_id: int = 0) -> void:
	## Researches every tech in prerequisite order for the player.
	var tech_tree: Variant = DataLoader.load_json("res://data/tech/tech_tree.json")
	if tech_tree == null or not (tech_tree is Array):
		push_warning("DebugAPI.research_all: could not load tech tree")
		return
	# Build dependency graph and research in order
	var researched: Array[String] = []
	var remaining: Array[Dictionary] = []
	for entry: Variant in tech_tree:
		if entry is Dictionary and "id" in entry:
			remaining.append(entry)
	# Iteratively resolve prerequisites
	var max_iterations: int = remaining.size() * 2
	var iterations: int = 0
	while not remaining.is_empty() and iterations < max_iterations:
		iterations += 1
		var progressed := false
		var still_remaining: Array[Dictionary] = []
		for tech: Dictionary in remaining:
			var prereqs: Array = tech.get("prerequisites", [])
			var met := true
			for prereq: Variant in prereqs:
				if str(prereq) not in researched:
					met = false
					break
			if met:
				research_tech(str(tech["id"]), player_id)
				researched.append(str(tech["id"]))
				progressed = true
			else:
				still_remaining.append(tech)
		remaining = still_remaining
		if not progressed:
			# Circular dependency or unresolvable — force remaining
			for tech: Dictionary in remaining:
				research_tech(str(tech["id"]), player_id)
			break


static func advance_age(_player_id: int = 0) -> void:
	## Advances to the next age, no cost. Player ID reserved for future per-player age.
	var next_age: int = GameManager.current_age + 1
	if next_age >= GameManager.AGE_NAMES.size():
		push_warning("DebugAPI.advance_age: already at max age")
		return
	GameManager.advance_age(next_age)


static func set_age(age_name: String, player_id: int = 0) -> void:
	## Jumps to the specified age by name, auto-researching prerequisites.
	var target_idx: int = -1
	for i: int in range(GameManager.AGE_NAMES.size()):
		if GameManager.AGE_NAMES[i].to_lower() == age_name.to_lower():
			target_idx = i
			break
		# Also accept short names like "bronze", "iron" etc.
		var short := GameManager.AGE_NAMES[i].to_lower().replace(" age", "")
		if short == age_name.to_lower():
			target_idx = i
			break
	if target_idx < 0:
		push_warning("DebugAPI.set_age: unknown age '%s'" % age_name)
		return
	# Research techs required for ages up to target
	var tech_tree: Variant = DataLoader.load_json("res://data/tech/tech_tree.json")
	if tech_tree != null and tech_tree is Array:
		var root: Node = null
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			root = tree.current_scene
		var tm: Node = _get_tech_manager(root)
		# Research all techs in ages up to target_idx
		for age_idx: int in range(target_idx + 1):
			for entry: Variant in tech_tree:
				if entry is Dictionary and "id" in entry:
					var tech_age: int = int(entry.get("age", 0))
					if tech_age <= age_idx:
						if tm != null and tm.has_method("is_tech_researched"):
							if not tm.is_tech_researched(str(entry["id"]), player_id):
								research_tech(str(entry["id"]), player_id)
						else:
							research_tech(str(entry["id"]), player_id)
	GameManager.advance_age(target_idx)


static func _get_tech_manager(root: Node) -> Node:
	## Tries to find TechManager from the scene root.
	if root != null and "_tech_manager" in root and root._tech_manager != null:
		return root._tech_manager
	return null


static func _register_unit_with_systems(u: Node2D, root: Node, owner_id: int) -> void:
	## Registers a spawned unit with all scene systems (mirrors debug_server.gd logic).
	if "_pathfinder" in root:
		u._pathfinder = root._pathfinder
	if "_visibility_manager" in root and root._visibility_manager != null:
		u._visibility_manager = root._visibility_manager
	if "_war_survival" in root and root._war_survival != null:
		u._war_survival = root._war_survival
	if "_input_handler" in root and root._input_handler != null:
		if root._input_handler.has_method("register_unit"):
			root._input_handler.register_unit(u)
	if "_target_detector" in root and root._target_detector != null:
		root._target_detector.register_entity(u)
	if "_population_manager" in root and root._population_manager != null:
		root._population_manager.register_unit(u, owner_id)
	if "_entity_registry" in root:
		root._entity_registry.register(u)
	if u.has_signal("unit_died") and root.has_method("_on_unit_died"):
		u.unit_died.connect(root._on_unit_died)


static func _register_building_with_systems(
	b: Node2D, root: Node, owner_id: int, grid_pos: Vector2i, fp: Vector2i
) -> void:
	## Registers a spawned building with all scene systems.
	if "_target_detector" in root and root._target_detector != null:
		root._target_detector.register_entity(b)
	if "_population_manager" in root and root._population_manager != null:
		root._population_manager.register_building(b, owner_id)
	if "_entity_registry" in root:
		root._entity_registry.register(b)
	if b.has_signal("building_destroyed") and root.has_method("_on_building_destroyed"):
		b.building_destroyed.connect(root._on_building_destroyed)
	if "_pathfinder" in root and root._pathfinder != null:
		for cell: Vector2i in BuildingValidator.get_footprint_cells(grid_pos, fp):
			root._pathfinder.set_cell_solid(cell, true)

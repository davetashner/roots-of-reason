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


# -- Fog of war commands --


static func reveal_map(scene_root: Node = null) -> String:
	## Disables fog and marks all tiles visible for all players.
	var root: Node = scene_root if scene_root != null else _get_scene_root()
	if root == null:
		return "Error: no scene root available"
	if not ("_visibility_manager" in root) or root._visibility_manager == null:
		return "Error: no VisibilityManager in scene"
	var vm: Node = root._visibility_manager
	vm.set_fog_enabled(false)
	vm.reveal_all(0)
	# Also hide the fog layer if present
	if "_fog_layer" in root and root._fog_layer != null:
		root._fog_layer.visible = false
	return "Map revealed — fog of war disabled"


static func set_fog(enabled: bool, scene_root: Node = null) -> String:
	## Toggles fog of war on or off.
	var root: Node = scene_root if scene_root != null else _get_scene_root()
	if root == null:
		return "Error: no scene root available"
	if not ("_visibility_manager" in root) or root._visibility_manager == null:
		return "Error: no VisibilityManager in scene"
	var vm: Node = root._visibility_manager
	vm.set_fog_enabled(enabled)
	if "_fog_layer" in root and root._fog_layer != null:
		root._fog_layer.visible = enabled
	if enabled:
		return "Fog of war enabled"
	vm.reveal_all(0)
	return "Fog of war disabled"


static func show_ai(scene_root: Node = null) -> String:
	## Reveals AI player entities through fog by marking their tiles visible.
	var root: Node = scene_root if scene_root != null else _get_scene_root()
	if root == null:
		return "Error: no scene root available"
	if not ("_visibility_manager" in root) or root._visibility_manager == null:
		return "Error: no VisibilityManager in scene"
	if not ("_entity_registry" in root) or root._entity_registry == null:
		return "Error: no EntityRegistry in scene"
	var vm: Node = root._visibility_manager
	# Reveal tiles around all non-player-0 entities
	var count: int = 0
	for owner_id: int in range(1, 8):  # AI players 1-7
		var entities: Array = root._entity_registry.get_by_owner(owner_id)
		for entity in entities:
			if not is_instance_valid(entity):
				continue
			if entity is Node2D:
				var grid_pos: Vector2i = vm._screen_to_grid(entity.global_position)
				if not vm._explored.has(0):
					vm._explored[0] = {}
				if not vm._visible.has(0):
					vm._visible[0] = {}
				# Reveal a small area around each AI entity
				for dy: int in range(-2, 3):
					for dx: int in range(-2, 3):
						var tile := Vector2i(grid_pos.x + dx, grid_pos.y + dy)
						vm._explored[0][tile] = true
						vm._visible[0][tile] = true
				count += 1
	vm._dirty[0] = true
	vm.visibility_changed.emit(0)
	return "Revealed %d AI entities through fog" % count


# -- Time control commands --


static func set_speed(multiplier: float) -> String:
	## Sets the game speed via Engine.time_scale.
	if multiplier < 0.0:
		return "Error: speed multiplier must be >= 0"
	Engine.time_scale = multiplier
	return "Game speed set to %.1fx" % multiplier


static func pause_game() -> String:
	## Pauses the game by setting time_scale to 0.
	Engine.time_scale = 0.0
	return "Game paused (time_scale = 0)"


static func unpause_game() -> String:
	## Resumes the game at normal speed.
	Engine.time_scale = 1.0
	return "Game resumed (time_scale = 1)"


static func step_frame(count: int = 1) -> String:
	## Advances the given number of physics frames when paused.
	## Briefly sets time_scale to 1 then back to 0 after the frames.
	if count < 1:
		return "Error: frame count must be >= 1"
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return "Error: no SceneTree available"
	# Temporarily unpause for the requested frames
	var prev_scale: float = Engine.time_scale
	Engine.time_scale = 1.0
	# We can't actually wait for frames in a static method, so we schedule
	# a deferred callback to re-pause after the frames
	var frames_remaining := [count]
	var cb: Callable
	cb = func() -> void:
		frames_remaining[0] -= 1
		if frames_remaining[0] <= 0:
			Engine.time_scale = 0.0
			tree.physics_frame.disconnect(cb)
	tree.physics_frame.connect(cb)
	return "Stepping %d frame(s) (was time_scale=%.1f)" % [count, prev_scale]


static func skip_time(seconds: float) -> String:
	## Fast-forwards game time by running at max speed for the given duration.
	if seconds <= 0.0:
		return "Error: seconds must be > 0"
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return "Error: no SceneTree available"
	var prev_scale: float = Engine.time_scale
	var target_scale: float = 20.0
	Engine.time_scale = target_scale
	# Schedule restoration after the real-time equivalent
	var real_seconds: float = seconds / target_scale
	tree.create_timer(real_seconds).timeout.connect(func() -> void: Engine.time_scale = prev_scale)
	return "Fast-forwarding %.1fs of game time (%.2fs real time)" % [seconds, real_seconds]


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


# -- Unit control commands --


static func _get_scene_root() -> Node:
	## Returns the current scene root or null.
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		return tree.current_scene
	return null


static func find_entity(entity_name: String, scene_root: Node = null) -> Node:
	## Finds an entity node by name in the scene tree. Returns null if not found.
	var root: Node = scene_root if scene_root != null else _get_scene_root()
	if root == null:
		return null
	return root.get_node_or_null(NodePath(entity_name))


static func move_unit(unit_name: String, x: float, y: float, scene_root: Node = null) -> String:
	## Issues a move command to a unit through its move_to method.
	var root: Node = scene_root if scene_root != null else _get_scene_root()
	var unit: Node = find_entity(unit_name, root)
	if unit == null:
		return "Error: unit '%s' not found" % unit_name
	if not unit.has_method("move_to"):
		return "Error: '%s' does not support move commands" % unit_name
	var world_pos := Vector2(x, y)
	unit.move_to(world_pos)
	return "Moved '%s' toward (%.0f, %.0f)" % [unit_name, x, y]


static func attack_unit(unit_name: String, target_name: String, scene_root: Node = null) -> String:
	## Issues an attack command — unit engages the target.
	var root: Node = scene_root if scene_root != null else _get_scene_root()
	var unit: Node = find_entity(unit_name, root)
	if unit == null:
		return "Error: unit '%s' not found" % unit_name
	var target: Node = find_entity(target_name, root)
	if target == null:
		return "Error: target '%s' not found" % target_name
	if not unit.has_method("assign_attack_target"):
		return "Error: '%s' does not support attack commands" % unit_name
	unit.assign_attack_target(target)
	return "'%s' attacking '%s'" % [unit_name, target_name]


static func gather_unit(unit_name: String, resource_name: String, scene_root: Node = null) -> String:
	## Issues a gather command — unit gathers from the resource node.
	var root: Node = scene_root if scene_root != null else _get_scene_root()
	var unit: Node = find_entity(unit_name, root)
	if unit == null:
		return "Error: unit '%s' not found" % unit_name
	var resource: Node = find_entity(resource_name, root)
	if resource == null:
		return "Error: resource '%s' not found" % resource_name
	if not unit.has_method("assign_gather_target"):
		return "Error: '%s' does not support gather commands" % unit_name
	unit.assign_gather_target(resource)
	return "'%s' gathering from '%s'" % [unit_name, resource_name]


static func set_unit_hp(unit_name: String, new_hp: int, scene_root: Node = null) -> String:
	## Sets a unit's HP, clamped to [0, max_hp].
	var root: Node = scene_root if scene_root != null else _get_scene_root()
	var unit: Node = find_entity(unit_name, root)
	if unit == null:
		return "Error: unit '%s' not found" % unit_name
	if "hp" not in unit or "max_hp" not in unit:
		return "Error: '%s' does not have HP" % unit_name
	var clamped: int = clampi(new_hp, 0, unit.max_hp)
	unit.hp = clamped
	if clamped <= 0 and unit.has_method("_die"):
		unit._die()
	return "Set '%s' HP to %d/%d" % [unit_name, clamped, unit.max_hp]


static func kill_unit(unit_name: String, scene_root: Node = null) -> String:
	## Immediately destroys a unit, triggering death signals.
	var root: Node = scene_root if scene_root != null else _get_scene_root()
	var unit: Node = find_entity(unit_name, root)
	if unit == null:
		return "Error: unit '%s' not found" % unit_name
	if unit.has_method("_die"):
		unit.hp = 0
		unit._die()
		return "Killed '%s'" % unit_name
	return "Error: '%s' does not support kill" % unit_name


static func teleport_unit(unit_name: String, x: float, y: float, scene_root: Node = null) -> String:
	## Instantly moves a unit to the given position (no pathfinding).
	var root: Node = scene_root if scene_root != null else _get_scene_root()
	var unit: Node = find_entity(unit_name, root)
	if unit == null:
		return "Error: unit '%s' not found" % unit_name
	if not (unit is Node2D):
		return "Error: '%s' is not a Node2D" % unit_name
	(unit as Node2D).position = Vector2(x, y)
	return "Teleported '%s' to (%.0f, %.0f)" % [unit_name, x, y]

extends Node2D
## Main prototype scene — assembles map, camera, units, input, and HUD
## programmatically at runtime.

const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")
const ProductionQueueScript := preload("res://scripts/prototype/production_queue.gd")
const AIEconomyScript := preload("res://scripts/ai/ai_economy.gd")
const AIMilitaryScript := preload("res://scripts/ai/ai_military.gd")
const AITechScript := preload("res://scripts/ai/ai_tech.gd")
const BuildingScript := preload("res://scripts/prototype/prototype_building.gd")

var _camera: Camera2D
var _input_handler: Node
var _map_node: Node
var _pathfinder: Node
var _target_detector: Node
var _cursor_overlay: Node
var _building_placer: Node
var _info_panel: PanelContainer
var _population_manager: Node
var _resource_bar: PanelContainer
var _tech_manager: Node
var _war_bonus: Node
var _ai_economy: Node = null
var _ai_military: Node = null
var _ai_tech: Node = null
var _visibility_manager: Node = null
var _fog_layer: Node = null


func _ready() -> void:
	_setup_map()
	_setup_fog_of_war()
	_setup_camera()
	_setup_pathfinding()
	_setup_target_detection()
	_setup_input()
	_setup_building_placer()
	_setup_population()
	_setup_units()
	_setup_demo_entities()
	_setup_fauna()
	_setup_tech()
	_setup_ai()
	_setup_hud()
	# Initial visibility update after all units are placed
	_update_fog_of_war()


func _setup_map() -> void:
	var map_layer := TileMapLayer.new()
	map_layer.name = "Map"
	map_layer.set_script(load("res://scripts/map/tilemap_terrain.gd"))
	add_child(map_layer)
	_map_node = map_layer


func _setup_fog_of_war() -> void:
	var dims: Vector2i = _map_node.get_map_dimensions()
	var blocks_fn := func(pos: Vector2i) -> bool: return _map_node.blocks_los(pos)

	_visibility_manager = Node.new()
	_visibility_manager.name = "VisibilityManager"
	_visibility_manager.set_script(load("res://scripts/prototype/visibility_manager.gd"))
	add_child(_visibility_manager)
	_visibility_manager.setup(dims.x, dims.y, blocks_fn)

	_fog_layer = TileMapLayer.new()
	_fog_layer.name = "FogOfWar"
	_fog_layer.set_script(load("res://scripts/map/fog_of_war_layer.gd"))
	add_child(_fog_layer)
	_fog_layer.setup(dims.x, dims.y, 0)

	_visibility_manager.visibility_changed.connect(_on_visibility_changed)


func _update_fog_of_war() -> void:
	if _visibility_manager == null:
		return
	var player_units: Array = []
	for child in get_children():
		if not (child is Node2D):
			continue
		if "owner_id" not in child:
			continue
		if child.owner_id != 0:
			continue
		if "hp" in child and child.hp <= 0:
			continue
		player_units.append(child)
	_visibility_manager.update_visibility(0, player_units)


func _on_visibility_changed(player_id: int) -> void:
	if player_id != 0 or _fog_layer == null or _visibility_manager == null:
		return
	(
		_fog_layer
		. update_fog(
			_visibility_manager.get_visible_tiles(0),
			_visibility_manager.get_explored_tiles(0),
			_visibility_manager.get_prev_visible_tiles(0),
		)
	)


func _setup_camera() -> void:
	_camera = Camera2D.new()
	_camera.name = "Camera"
	_camera.set_script(load("res://scripts/prototype/prototype_camera.gd"))
	var map_size: int = _map_node.get_map_size()
	var half_size := map_size / 2
	var center := IsoUtils.grid_to_screen(Vector2(half_size, half_size))
	_camera.position = center
	_camera.enabled = true
	add_child(_camera)
	# Compute map bounds from corner grid positions and pass to camera
	var corners: Array[Vector2] = [
		IsoUtils.grid_to_screen(Vector2(0, 0)),
		IsoUtils.grid_to_screen(Vector2(map_size, 0)),
		IsoUtils.grid_to_screen(Vector2(0, map_size)),
		IsoUtils.grid_to_screen(Vector2(map_size, map_size)),
	]
	var min_pos := corners[0]
	var max_pos := corners[0]
	for corner in corners:
		min_pos.x = minf(min_pos.x, corner.x)
		min_pos.y = minf(min_pos.y, corner.y)
		max_pos.x = maxf(max_pos.x, corner.x)
		max_pos.y = maxf(max_pos.y, corner.y)
	var bounds := Rect2(min_pos, max_pos - min_pos)
	_camera.setup(bounds)


func _setup_pathfinding() -> void:
	_pathfinder = Node.new()
	_pathfinder.name = "PathfindingGrid"
	_pathfinder.set_script(load("res://scripts/prototype/pathfinding_grid.gd"))
	add_child(_pathfinder)
	_pathfinder.build(_map_node.get_map_size(), _map_node.get_tile_grid(), {})


func _setup_target_detection() -> void:
	_target_detector = Node.new()
	_target_detector.name = "TargetDetector"
	_target_detector.set_script(load("res://scripts/prototype/target_detector.gd"))
	add_child(_target_detector)
	if _visibility_manager != null:
		_target_detector.set_visibility_manager(_visibility_manager)


func _setup_input() -> void:
	_input_handler = Node.new()
	_input_handler.name = "InputHandler"
	_input_handler.set_script(load("res://scripts/prototype/prototype_input.gd"))
	add_child(_input_handler)
	if _input_handler.has_method("setup"):
		_input_handler.setup(_camera, _pathfinder, _target_detector)


func _setup_population() -> void:
	_population_manager = Node.new()
	_population_manager.name = "PopulationManager"
	_population_manager.set_script(load("res://scripts/prototype/population_manager.gd"))
	add_child(_population_manager)


func _setup_building_placer() -> void:
	_building_placer = Node.new()
	_building_placer.name = "BuildingPlacer"
	_building_placer.set_script(load("res://scripts/prototype/building_placer.gd"))
	add_child(_building_placer)
	_building_placer.setup(_camera, _pathfinder, _map_node, _target_detector)
	_building_placer.building_placed.connect(_on_building_placed)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_B:
			if _building_placer != null and not _building_placer.is_active():
				_building_placer.start_placement("house", 0)


func _setup_units() -> void:
	var offsets := _get_villager_offsets()
	var tc_pos := _get_player_start_position()
	for i in offsets.size():
		var unit := Node2D.new()
		unit.name = "Unit_%d" % i
		unit.set_script(UnitScript)
		var offset: Vector2i = offsets[i]
		var spawn_pos: Vector2i = tc_pos + offset
		unit.position = IsoUtils.grid_to_screen(Vector2(spawn_pos))
		unit.unit_type = "villager"
		add_child(unit)
		unit._scene_root = self
		if _visibility_manager != null:
			unit._visibility_manager = _visibility_manager
		# Register with input handler after both are in tree
		if _input_handler.has_method("register_unit"):
			_input_handler.register_unit(unit)
		if _target_detector != null:
			_target_detector.register_entity(unit)
		if _population_manager != null:
			_population_manager.register_unit(unit, 0)


func _setup_demo_entities() -> void:
	# Resource nodes — generated by map system
	var all_resource_positions: Dictionary = _map_node.get_resource_positions()
	var ResourceNodeScript: GDScript = load("res://scripts/prototype/prototype_resource_node.gd")
	var res_index := 0
	for res_name: String in all_resource_positions:
		var positions: Array = all_resource_positions[res_name]
		for pos in positions:
			var grid_pos: Vector2i = pos as Vector2i
			var res_node := Node2D.new()
			res_node.name = "Resource_%s_%d" % [res_name, res_index]
			res_node.set_script(ResourceNodeScript)
			res_node.position = IsoUtils.grid_to_screen(Vector2(grid_pos))
			add_child(res_node)
			res_node.setup(res_name)
			res_node.depleted.connect(_on_resource_depleted)
			res_node.regen_started.connect(_on_resource_regen_started)
			_target_detector.register_entity(res_node)
			res_index += 1
	# Own building (blue, 3x3 town center) — fully built
	var building := Node2D.new()
	building.name = "Building_0"
	building.set_script(BuildingScript)
	var bld_pos := _get_player_start_position()
	building.position = IsoUtils.grid_to_screen(Vector2(bld_pos))
	building.owner_id = 0
	building.building_name = "town_center"
	building.footprint = Vector2i(3, 3)
	building.grid_pos = bld_pos
	building.hp = 2400
	building.max_hp = 2400
	building.under_construction = false
	building.build_progress = 1.0
	add_child(building)
	_target_detector.register_entity(building)
	if _population_manager != null:
		_population_manager.register_building(building, building.owner_id)
	_try_attach_production_queue(building)
	# Mark footprint cells solid
	var cells := BuildingValidator.get_footprint_cells(bld_pos, Vector2i(3, 3))
	for cell in cells:
		_pathfinder.set_cell_solid(cell, true)


func _setup_fauna() -> void:
	var all_fauna: Dictionary = _map_node.get_fauna_positions()
	var fauna_index := 0
	for fauna_name: String in all_fauna:
		var packs: Array = all_fauna[fauna_name]
		for pack in packs:
			var pack_dict: Dictionary = pack as Dictionary
			var grid_pos: Vector2i = pack_dict.get("position", Vector2i.ZERO)
			var pack_size: int = int(pack_dict.get("pack_size", 2))
			for i in pack_size:
				var unit := Node2D.new()
				unit.name = "Fauna_%s_%d" % [fauna_name, fauna_index]
				unit.set_script(UnitScript)
				# Offset pack members slightly
				var offset := Vector2i(i % 2, i / 2)
				var spawn_pos: Vector2i = grid_pos + offset
				unit.position = IsoUtils.grid_to_screen(Vector2(spawn_pos))
				unit.unit_type = fauna_name
				unit.owner_id = -1  # Gaia faction
				unit.unit_color = Color(0.5, 0.5, 0.5)  # Gray
				add_child(unit)
				unit._scene_root = self
				if _target_detector != null:
					_target_detector.register_entity(unit)
				fauna_index += 1


func _on_building_placed(building: Node2D) -> void:
	if building.has_signal("construction_complete"):
		building.construction_complete.connect(_on_building_construction_complete)
	var idle_unit := _find_nearest_idle_unit(building.global_position)
	if idle_unit != null and idle_unit.has_method("assign_build_target"):
		idle_unit.assign_build_target(building)


func _on_building_construction_complete(building: Node2D) -> void:
	if _population_manager != null and "owner_id" in building:
		_population_manager.register_building(building, building.owner_id)
	_try_attach_production_queue(building)


func _setup_ai() -> void:
	var difficulty: String = GameManager.ai_difficulty
	var tier_config: Dictionary = _load_ai_tier_config(difficulty)
	ResourceManager.init_player(1, null, difficulty)
	var multiplier: float = tier_config.get("gather_rate_multiplier", 1.0)
	if not is_equal_approx(multiplier, 1.0):
		ResourceManager.set_gather_multiplier(1, multiplier)
	var ai_tc := _create_ai_town_center()
	var villager_count: int = tier_config.get("starting_villagers", 3)
	_create_ai_starting_villagers(ai_tc, villager_count)
	_ai_economy = Node.new()
	_ai_economy.name = "AIEconomy"
	_ai_economy.set_script(AIEconomyScript)
	_ai_economy.difficulty = difficulty
	add_child(_ai_economy)
	_ai_economy.setup(self, _population_manager, _pathfinder, _map_node, _target_detector, _tech_manager)
	_ai_military = Node.new()
	_ai_military.name = "AIMilitary"
	_ai_military.set_script(AIMilitaryScript)
	_ai_military.difficulty = difficulty
	add_child(_ai_military)
	_ai_military.setup(self, _population_manager, _target_detector, _ai_economy)
	_ai_tech = Node.new()
	_ai_tech.name = "AITech"
	_ai_tech.set_script(AITechScript)
	_ai_tech.difficulty = difficulty
	_ai_tech.personality = tier_config.get("personality", "balanced")
	add_child(_ai_tech)
	_ai_tech.setup(_tech_manager)


func _load_ai_tier_config(difficulty: String) -> Dictionary:
	var data: Dictionary = DataLoader.load_json("res://data/ai/ai_difficulty.json")
	if data == null:
		return {}
	var tiers: Dictionary = data.get("tiers", {})
	if difficulty in tiers:
		return tiers[difficulty]
	var default_tier: String = data.get("default", "normal")
	return tiers.get(default_tier, {})


func _create_ai_town_center() -> Node2D:
	var tc_pos := _get_ai_start_position()
	var building := Node2D.new()
	building.name = "AI_TownCenter"
	building.set_script(BuildingScript)
	building.position = IsoUtils.grid_to_screen(Vector2(tc_pos))
	building.owner_id = 1
	building.building_name = "town_center"
	building.footprint = Vector2i(3, 3)
	building.grid_pos = tc_pos
	building.hp = 2400
	building.max_hp = 2400
	building.under_construction = false
	building.build_progress = 1.0
	building.entity_category = "enemy_building"
	add_child(building)
	_target_detector.register_entity(building)
	if _population_manager != null:
		_population_manager.register_building(building, building.owner_id)
	_try_attach_production_queue(building)
	# Mark footprint cells solid
	var cells := BuildingValidator.get_footprint_cells(tc_pos, Vector2i(3, 3))
	for cell in cells:
		_pathfinder.set_cell_solid(cell, true)
	return building


func _create_ai_starting_villagers(tc: Node2D, count: int) -> void:
	var offsets := _get_villager_offsets()
	for i in count:
		var unit := Node2D.new()
		unit.name = "AIVillager_%d" % i
		unit.set_script(UnitScript)
		unit.unit_type = "villager"
		unit.owner_id = 1
		unit.unit_color = Color(0.9, 0.2, 0.2)
		var offset := offsets[i % offsets.size()]
		var spawn_pos: Vector2i = tc.grid_pos + offset
		unit.position = IsoUtils.grid_to_screen(Vector2(spawn_pos))
		add_child(unit)
		unit._scene_root = self
		if _target_detector != null:
			_target_detector.register_entity(unit)
		if _population_manager != null:
			_population_manager.register_unit(unit, 1)


func _find_nearest_idle_unit(target_pos: Vector2) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for child in get_children():
		if not child.has_method("is_idle"):
			continue
		if "owner_id" in child and child.owner_id != 0:
			continue
		if not child.is_idle():
			continue
		var dist: float = child.global_position.distance_to(target_pos)
		if dist < best_dist:
			best_dist = dist
			best = child
	return best


func _try_attach_production_queue(building: Node2D) -> void:
	if not "building_name" in building:
		return
	var building_name: String = building.building_name
	if building_name == "":
		return
	var stats: Dictionary = DataLoader.get_building_stats(building_name)
	var units_produced: Array = stats.get("units_produced", [])
	if units_produced.is_empty():
		return
	var pq := Node.new()
	pq.name = "ProductionQueue"
	pq.set_script(ProductionQueueScript)
	building.add_child(pq)
	var owner_id: int = building.owner_id if "owner_id" in building else 0
	pq.setup(building, owner_id, _population_manager)
	pq.unit_produced.connect(_on_unit_produced)


func _on_unit_produced(unit_type: String, building: Node2D) -> void:
	var unit := Node2D.new()
	var unit_count := get_child_count()
	unit.name = "Unit_%d" % unit_count
	unit.set_script(UnitScript)
	unit.unit_type = unit_type
	var owner_id: int = building.owner_id if "owner_id" in building else 0
	unit.owner_id = owner_id
	# Spawn at building position offset by rally point
	var pq: Node = building.get_node_or_null("ProductionQueue")
	var offset := Vector2i(1, 1)
	if pq != null and pq.has_method("get_rally_point_offset"):
		offset = pq.get_rally_point_offset()
	var spawn_grid: Vector2i = Vector2i.ZERO
	if "grid_pos" in building:
		spawn_grid = building.grid_pos + offset
	unit.position = IsoUtils.grid_to_screen(Vector2(spawn_grid))
	add_child(unit)
	unit._scene_root = self
	if _visibility_manager != null:
		unit._visibility_manager = _visibility_manager
	if _input_handler != null and _input_handler.has_method("register_unit"):
		_input_handler.register_unit(unit)
	if _target_detector != null:
		_target_detector.register_entity(unit)
	if _population_manager != null:
		_population_manager.register_unit(unit, owner_id)


func _on_resource_depleted(node: Node2D) -> void:
	if _target_detector != null and _target_detector.has_method("unregister_entity"):
		_target_detector.unregister_entity(node)


func _on_resource_regen_started(_node: Node2D) -> void:
	pass


func _setup_tech() -> void:
	_tech_manager = Node.new()
	_tech_manager.name = "TechManager"
	_tech_manager.set_script(load("res://scripts/prototype/tech_manager.gd"))
	add_child(_tech_manager)
	# War research bonus node — tracks combat state and provides speed multiplier
	_war_bonus = Node.new()
	_war_bonus.name = "WarResearchBonus"
	_war_bonus.set_script(load("res://scripts/prototype/war_research_bonus.gd"))
	add_child(_war_bonus)
	_tech_manager.setup_war_bonus(_war_bonus)
	# Connect tech completion to spillover system
	_tech_manager.tech_researched.connect(_on_tech_researched_spillover)


func _setup_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	hud.set_script(load("res://scripts/prototype/prototype_hud.gd"))
	add_child(hud)
	# Connect camera and input handler
	if hud.has_method("setup"):
		hud.setup(_camera, _input_handler)
	# Info panel for selected unit/building details
	var info_panel_layer := CanvasLayer.new()
	info_panel_layer.name = "InfoPanel"
	info_panel_layer.layer = 10
	add_child(info_panel_layer)
	_info_panel = PanelContainer.new()
	_info_panel.name = "InfoPanelWidget"
	_info_panel.set_script(load("res://scripts/ui/info_panel.gd"))
	info_panel_layer.add_child(_info_panel)
	_info_panel.setup(_input_handler, _target_detector)
	# Command panel
	var cmd_panel_layer := CanvasLayer.new()
	cmd_panel_layer.name = "CommandPanel"
	cmd_panel_layer.layer = 10
	add_child(cmd_panel_layer)
	var cmd_panel := PanelContainer.new()
	cmd_panel.name = "CommandPanelWidget"
	cmd_panel.set_script(load("res://scripts/ui/command_panel.gd"))
	cmd_panel_layer.add_child(cmd_panel)
	cmd_panel.setup(_input_handler, _building_placer)
	# Cursor overlay for command context labels
	_cursor_overlay = CanvasLayer.new()
	_cursor_overlay.name = "CursorOverlay"
	_cursor_overlay.set_script(load("res://scripts/prototype/cursor_overlay.gd"))
	add_child(_cursor_overlay)
	_input_handler._cursor_overlay = _cursor_overlay
	# Resource bar HUD
	_setup_resource_bar()


func _setup_resource_bar() -> void:
	ResourceManager.init_player(0)
	var resource_bar_layer := CanvasLayer.new()
	resource_bar_layer.name = "ResourceBar"
	resource_bar_layer.layer = 10
	add_child(resource_bar_layer)
	_resource_bar = PanelContainer.new()
	_resource_bar.name = "ResourceBarPanel"
	_resource_bar.set_script(load("res://scripts/ui/resource_bar.gd"))
	resource_bar_layer.add_child(_resource_bar)
	# Connect population manager to resource bar display
	if _population_manager != null:
		_population_manager.population_changed.connect(_on_population_changed)
		# Initial display update
		var current: int = _population_manager.get_population(0)
		var cap: int = _population_manager.get_population_cap(0)
		_resource_bar.update_population(current, cap)


func _on_tech_researched_spillover(player_id: int, tech_id: String, _effects: Dictionary) -> void:
	if _war_bonus != null:
		var tech_data: Dictionary = DataLoader.get_tech_data(tech_id)
		_war_bonus.apply_spillover(player_id, tech_id, tech_data)


func _on_population_changed(player_id: int, current: int, cap: int) -> void:
	if player_id == 0 and _resource_bar != null:
		_resource_bar.update_population(current, cap)


func _get_player_start_position() -> Vector2i:
	var positions: Array = _map_node.get_starting_positions()
	if positions.size() >= 1:
		return positions[0] as Vector2i
	return Vector2i(4, 4)


func _get_ai_start_position() -> Vector2i:
	var positions: Array = _map_node.get_starting_positions()
	if positions.size() >= 2:
		return positions[1] as Vector2i
	var map_size: int = _map_node.get_map_size()
	return Vector2i(map_size - 7, map_size - 7)


func _get_villager_offsets() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var map_gen_cfg: Dictionary = DataLoader.load_json("res://data/settings/map_generation.json")
	var start_cfg: Dictionary = map_gen_cfg.get("starting_locations", {})
	var raw_offsets: Array = start_cfg.get("villager_offsets", [[-1, 0], [0, -1], [-1, -1], [1, -1], [-1, 1]])
	for offset in raw_offsets:
		if offset is Array and offset.size() == 2:
			result.append(Vector2i(int(offset[0]), int(offset[1])))
	return result

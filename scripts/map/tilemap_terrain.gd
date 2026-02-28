extends TileMapLayer
## TileMapLayer-based terrain system with programmatic TileSet construction.
## Supports 7 terrain types with custom data layers for movement cost, buildability,
## and line-of-sight blocking. Replaces prototype_map.gd Sprite2D approach.

const TILE_SIZE := Vector2i(128, 64)
const TEXTURE_BASE_PATH := "res://assets/tiles/terrain/prototype/"

const ElevationGenerator := preload("res://scripts/map/elevation_generator.gd")
const RiverGenerator := preload("res://scripts/map/river_generator.gd")
const CoastlineGenerator := preload("res://scripts/map/coastline_generator.gd")
const ResourceGenerator := preload("res://scripts/map/resource_generator.gd")
const StartingLocationGenerator := preload("res://scripts/map/starting_location_generator.gd")
const FaunaGenerator := preload("res://scripts/map/fauna_generator.gd")
const TerrainMapperScript := preload("res://scripts/map/terrain_mapper.gd")

var _terrain_config: Dictionary = {}
var _map_gen_config: Dictionary = {}
var _tile_grid: Dictionary = {}  # Vector2i -> terrain name
var _terrain_properties: Dictionary = {}
var _terrain_costs: Dictionary = {}
var _map_width: int = 64
var _map_height: int = 64
var _seed_value: int = 42
var _terrain_weights: Dictionary = {}
var _source_ids: Dictionary = {}  # terrain_name -> source_id (primary)
var _variant_ids: Dictionary = {}  # terrain_name -> Array[int] (all variant source_ids)

# River/elevation data
var _elevation_grid: Dictionary = {}  # Vector2i -> float
var _river_tiles: Dictionary = {}  # Vector2i -> true
var _flow_directions: Dictionary = {}  # Vector2i -> Vector2i
var _river_ids: Dictionary = {}  # Vector2i -> int
var _river_widths: Dictionary = {}  # Vector2i -> int

# Resource positions
var _resource_positions: Dictionary = {}  # resource_name -> Array[Vector2i]

# Starting positions
var _starting_positions: Array = []  # Array[Vector2i]

# Fauna positions
var _fauna_positions: Dictionary = {}  # fauna_name -> Array[Dictionary]


func _ready() -> void:
	_load_config()
	_build_tileset()
	_generate_map()
	queue_redraw()
	notify_runtime_tile_data_update()


func _load_config() -> void:
	var terrain_cfg := _load_settings("terrain")
	var map_gen_cfg := _load_settings("map_generation")

	_terrain_costs = terrain_cfg.get("terrain_costs", {})
	_terrain_properties = terrain_cfg.get("terrain_properties", {})
	_map_gen_config = map_gen_cfg

	var sizes: Dictionary = map_gen_cfg.get("map_sizes", {})
	var default_size_key: String = map_gen_cfg.get("default_size", "dev")
	var size_data: Dictionary = sizes.get(default_size_key, {})
	_map_width = int(size_data.get("width", 64))
	_map_height = int(size_data.get("height", 64))
	_seed_value = int(map_gen_cfg.get("seed", 42))
	_terrain_weights = map_gen_cfg.get("terrain_weights", {})

	# Fallback defaults if no config loaded
	if _terrain_weights.is_empty():
		_terrain_weights = {
			"grass": 45,
			"dirt": 10,
			"sand": 5,
			"water": 10,
			"forest": 15,
			"stone": 10,
			"mountain": 5,
		}
	if _terrain_properties.is_empty():
		_terrain_properties = {
			"grass": {"buildable": true, "blocks_los": false},
			"dirt": {"buildable": true, "blocks_los": false},
			"sand": {"buildable": true, "blocks_los": false},
			"water": {"buildable": false, "blocks_los": false},
			"forest": {"buildable": true, "blocks_los": true},
			"stone": {"buildable": true, "blocks_los": false},
			"mountain": {"buildable": false, "blocks_los": true},
			"river": {"buildable": false, "blocks_los": false},
		}


func _load_settings(settings_name: String) -> Dictionary:
	if is_instance_valid(Engine.get_main_loop()):
		var dl: Node = Engine.get_main_loop().root.get_node_or_null("DataLoader")
		if dl and dl.has_method("get_settings"):
			return dl.get_settings(settings_name)
	# Direct file fallback for tests
	var dl_class: GDScript = load("res://scripts/autoloads/data_loader.gd")
	var subpath: String = dl_class.SETTINGS_PATHS.get(settings_name, settings_name)
	var path := "res://data/settings/%s.json" % subpath
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	if json.data is Dictionary:
		return json.data
	return {}


func _build_tileset() -> void:
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_size = TILE_SIZE

	# Custom data layers
	ts.add_custom_data_layer()
	ts.set_custom_data_layer_name(0, "terrain_type")
	ts.set_custom_data_layer_type(0, TYPE_STRING)

	ts.add_custom_data_layer()
	ts.set_custom_data_layer_name(1, "movement_cost")
	ts.set_custom_data_layer_type(1, TYPE_FLOAT)

	ts.add_custom_data_layer()
	ts.set_custom_data_layer_name(2, "buildable")
	ts.set_custom_data_layer_type(2, TYPE_BOOL)

	ts.add_custom_data_layer()
	ts.set_custom_data_layer_name(3, "blocks_los")
	ts.set_custom_data_layer_type(3, TYPE_BOOL)

	# One atlas source per terrain type (+ variant sources)
	var source_id := 0
	for terrain_name: String in _terrain_weights:
		var cost: float = float(_terrain_costs.get(terrain_name, 1.0))
		var props: Dictionary = _terrain_properties.get(terrain_name, {})

		# Check for variant files: {terrain}_flat_01.png, _02.png, etc.
		var variants: Array[int] = []
		var variant_idx := 1
		while true:
			var vpath := TEXTURE_BASE_PATH + terrain_name + "_flat_%02d.png" % variant_idx
			var vtex: Texture2D = load(vpath)
			if vtex == null:
				break
			var vsource := TileSetAtlasSource.new()
			vsource.texture = vtex
			vsource.texture_region_size = TILE_SIZE
			ts.add_source(vsource, source_id)
			vsource.create_tile(Vector2i.ZERO)
			var vtile: TileData = vsource.get_tile_data(Vector2i.ZERO, 0)
			vtile.set_custom_data("terrain_type", terrain_name)
			vtile.set_custom_data("movement_cost", cost)
			vtile.set_custom_data("buildable", props.get("buildable", true))
			vtile.set_custom_data("blocks_los", props.get("blocks_los", false))
			variants.append(source_id)
			source_id += 1
			variant_idx += 1

		if not variants.is_empty():
			_source_ids[terrain_name] = variants[0]
			_variant_ids[terrain_name] = variants
			continue

		# Fallback: single base texture
		var tex_path := TEXTURE_BASE_PATH + terrain_name + ".png"
		var tex: Texture2D = load(tex_path)
		if tex == null:
			push_warning("TilemapTerrain: Could not load texture: " + tex_path)
			continue

		var source := TileSetAtlasSource.new()
		source.texture = tex
		source.texture_region_size = TILE_SIZE
		ts.add_source(source, source_id)
		source.create_tile(Vector2i.ZERO)

		var tile_data: TileData = source.get_tile_data(Vector2i.ZERO, 0)
		tile_data.set_custom_data("terrain_type", terrain_name)
		tile_data.set_custom_data("movement_cost", cost)
		tile_data.set_custom_data("buildable", props.get("buildable", true))
		tile_data.set_custom_data("blocks_los", props.get("blocks_los", false))

		_source_ids[terrain_name] = source_id
		source_id += 1

	# Register procedurally-placed terrain tiles (not in terrain_weights)
	var extra_terrains := ["river", "shore", "shallows", "deep_water"]
	for extra_name: String in extra_terrains:
		if _source_ids.has(extra_name):
			continue
		var extra_tex_path := TEXTURE_BASE_PATH + extra_name + ".png"
		var extra_tex: Texture2D = load(extra_tex_path)
		if extra_tex == null:
			continue
		var extra_source := TileSetAtlasSource.new()
		extra_source.texture = extra_tex
		extra_source.texture_region_size = TILE_SIZE
		ts.add_source(extra_source, source_id)
		extra_source.create_tile(Vector2i.ZERO)

		var extra_tile_data: TileData = extra_source.get_tile_data(Vector2i.ZERO, 0)
		extra_tile_data.set_custom_data("terrain_type", extra_name)
		extra_tile_data.set_custom_data("movement_cost", float(_terrain_costs.get(extra_name, 1.0)))
		var extra_props: Dictionary = _terrain_properties.get(extra_name, {})
		extra_tile_data.set_custom_data("buildable", extra_props.get("buildable", false))
		extra_tile_data.set_custom_data("blocks_los", extra_props.get("blocks_los", false))

		_source_ids[extra_name] = source_id
		source_id += 1

	tile_set = ts


func _pick_variant_sid(terrain: String, pos: Vector2i) -> int:
	var variants: Array = _variant_ids.get(terrain, [])
	if variants.is_empty():
		return _source_ids.get(terrain, -1)
	# Deterministic selection from seed + position (reproducible across save/load)
	var hash_val: int = _seed_value + pos.x * 7919 + pos.y * 104729
	return variants[absi(hash_val) % variants.size()]


func _generate_map() -> void:
	# 1. Generate elevation grid
	var elev_gen := ElevationGenerator.new()
	elev_gen.configure(_map_gen_config.get("elevation_noise", {}))
	_elevation_grid = elev_gen.generate(_map_width, _map_height, _seed_value)

	# 2. Apply island mask (edges become water)
	var edge_width: int = int(_map_gen_config.get("island_edge_width", 3))
	var falloff_width: int = int(_map_gen_config.get("island_falloff_width", 8))
	TerrainMapperScript.apply_island_mask(_elevation_grid, _map_width, _map_height, edge_width, falloff_width)

	# 3. Generate moisture grid (reuse ElevationGenerator with different config)
	var moisture_gen := ElevationGenerator.new()
	moisture_gen.configure(_map_gen_config.get("moisture_noise", {}))
	var moisture_grid: Dictionary = moisture_gen.generate(_map_width, _map_height, _seed_value)

	# 4. Map elevation + moisture to terrain type (rendering deferred to step 4b)
	var mapper := TerrainMapperScript.new()
	mapper.configure(_map_gen_config)
	for row in _map_height:
		for col in _map_width:
			var pos := Vector2i(col, row)
			var elevation: float = _elevation_grid.get(pos, 0.0)
			var moisture: float = moisture_grid.get(pos, 0.0)
			var terrain: String = mapper.get_terrain(elevation, moisture)
			_tile_grid[pos] = terrain

	# 4a. Reclassify water/land adjacency into shore/shallows/deep_water
	var coast_gen := CoastlineGenerator.new()
	coast_gen.configure(_map_gen_config.get("coastline_generation", {}))
	var coast_result: Dictionary = coast_gen.generate(_tile_grid, _map_width, _map_height)
	var coast_changes: Dictionary = coast_result.get("changes", {})
	for pos: Vector2i in coast_changes:
		_tile_grid[pos] = coast_changes[pos]

	# 4b. Render all tiles (after coastline reclassification)
	for pos: Vector2i in _tile_grid:
		var sid: int = _pick_variant_sid(_tile_grid[pos], pos)
		if sid >= 0:
			set_cell(pos, sid, Vector2i.ZERO)

	# 5. Generate rivers (existing system, unchanged)
	var river_gen := RiverGenerator.new()
	river_gen.configure(_map_gen_config.get("river_generation", {}))
	var river_data: Dictionary = river_gen.generate(_elevation_grid, _tile_grid, _map_width, _map_height, _seed_value)
	_river_tiles = river_data.get("river_tiles", {})
	_flow_directions = river_data.get("flow_directions", {})
	_river_ids = river_data.get("river_ids", {})
	_river_widths = river_data.get("river_widths", {})

	# 6. Apply river tiles to the map
	for pos: Vector2i in _river_tiles:
		_tile_grid[pos] = "river"
		var river_sid: int = _pick_variant_sid("river", pos)
		if river_sid >= 0:
			set_cell(pos, river_sid, Vector2i.ZERO)

	# 7. Select starting locations
	var start_gen := StartingLocationGenerator.new()
	start_gen.configure(_map_gen_config.get("starting_locations", {}))
	var start_result: Dictionary = (
		start_gen
		. generate(
			_tile_grid,
			_elevation_grid,
			_terrain_properties,
			_map_width,
			_map_height,
			_seed_value,
			_river_tiles,
			_flow_directions,
		)
	)
	_starting_positions = []
	for pos in start_result.get("starting_positions", []):
		_starting_positions.append(pos as Vector2i)

	# 8. Generate resource positions (with starting positions for zone guarantees)
	var res_gen := ResourceGenerator.new()
	res_gen.configure(_map_gen_config.get("resource_generation", {}))
	_resource_positions = res_gen.generate(_tile_grid, _map_width, _map_height, _seed_value, _starting_positions)

	# 9. Generate fauna positions (with starting positions for distance constraints)
	var fauna_gen := FaunaGenerator.new()
	fauna_gen.configure(_map_gen_config.get("fauna_generation", {}))
	_fauna_positions = fauna_gen.generate(_tile_grid, _map_width, _map_height, _seed_value, _starting_positions)


# -- Public API (backward-compatible with prototype_map.gd) --


func get_terrain_at(grid_pos: Vector2i) -> String:
	return _tile_grid.get(grid_pos, "")


func get_map_size() -> int:
	# Backward-compatible: returns width (assumes square for old callers)
	return _map_width


func get_map_dimensions() -> Vector2i:
	return Vector2i(_map_width, _map_height)


func get_tile_grid() -> Dictionary:
	return _tile_grid


# -- Starting Position API --


func get_starting_positions() -> Array:
	return _starting_positions


# -- New API --


func is_buildable(grid_pos: Vector2i) -> bool:
	var terrain: String = _tile_grid.get(grid_pos, "")
	if terrain.is_empty():
		return false
	var props: Dictionary = _terrain_properties.get(terrain, {})
	return props.get("buildable", true)


func blocks_los(grid_pos: Vector2i) -> bool:
	var terrain: String = _tile_grid.get(grid_pos, "")
	if terrain.is_empty():
		return false
	var props: Dictionary = _terrain_properties.get(terrain, {})
	return props.get("blocks_los", false)


func get_movement_cost(grid_pos: Vector2i) -> float:
	var terrain: String = _tile_grid.get(grid_pos, "")
	if terrain.is_empty():
		return -1.0
	return float(_terrain_costs.get(terrain, 1.0))


# -- River / Elevation API --


func is_river(grid_pos: Vector2i) -> bool:
	return _river_tiles.has(grid_pos)


func get_flow_direction(grid_pos: Vector2i) -> Vector2i:
	return _flow_directions.get(grid_pos, Vector2i.ZERO)


func get_river_id(grid_pos: Vector2i) -> int:
	return _river_ids.get(grid_pos, -1)


func get_river_width(grid_pos: Vector2i) -> int:
	return _river_widths.get(grid_pos, 0)


func get_elevation_at(grid_pos: Vector2i) -> float:
	return _elevation_grid.get(grid_pos, 0.0)


# -- Resource API --

# -- Fauna API --


func get_fauna_positions() -> Dictionary:
	return _fauna_positions


func get_resource_positions() -> Dictionary:
	return _resource_positions


func get_resource_positions_for(resource_name: String) -> Array[Vector2i]:
	var positions: Array[Vector2i] = []
	var raw: Array = _resource_positions.get(resource_name, [])
	for pos in raw:
		positions.append(pos as Vector2i)
	return positions


# -- Save / Load --


func save_state() -> Dictionary:
	var grid_data: Dictionary = {}
	for pos: Vector2i in _tile_grid:
		var key := "%d,%d" % [pos.x, pos.y]
		grid_data[key] = _tile_grid[pos]
	# Serialize river data
	var river_data: Dictionary = {}
	var river_tiles_serialized: Dictionary = {}
	var flow_dirs_serialized: Dictionary = {}
	var river_ids_serialized: Dictionary = {}
	var river_widths_serialized: Dictionary = {}
	for pos: Vector2i in _river_tiles:
		var key := "%d,%d" % [pos.x, pos.y]
		river_tiles_serialized[key] = true
		if _flow_directions.has(pos):
			var dir: Vector2i = _flow_directions[pos]
			flow_dirs_serialized[key] = "%d,%d" % [dir.x, dir.y]
		if _river_ids.has(pos):
			river_ids_serialized[key] = _river_ids[pos]
		if _river_widths.has(pos):
			river_widths_serialized[key] = _river_widths[pos]
	river_data["river_tiles"] = river_tiles_serialized
	river_data["flow_directions"] = flow_dirs_serialized
	river_data["river_ids"] = river_ids_serialized
	river_data["river_widths"] = river_widths_serialized

	# Serialize resource positions
	var res_data: Dictionary = {}
	for res_name: String in _resource_positions:
		var positions: Array = []
		for pos: Vector2i in _resource_positions[res_name]:
			positions.append("%d,%d" % [pos.x, pos.y])
		res_data[res_name] = positions

	# Serialize starting positions
	var start_pos_data: Array = []
	for pos: Vector2i in _starting_positions:
		start_pos_data.append("%d,%d" % [pos.x, pos.y])

	# Serialize fauna positions
	var fauna_data: Dictionary = {}
	for fauna_name: String in _fauna_positions:
		var packs: Array = []
		for pack: Dictionary in _fauna_positions[fauna_name]:
			var pack_pos: Vector2i = pack.position
			(
				packs
				. append(
					{
						"position": "%d,%d" % [pack_pos.x, pack_pos.y],
						"pack_size": pack.pack_size,
						"contested": pack.contested,
					}
				)
			)
		fauna_data[fauna_name] = packs

	return {
		"map_width": _map_width,
		"map_height": _map_height,
		"seed": _seed_value,
		"tile_grid": grid_data,
		"river_data": river_data,
		"resource_positions": res_data,
		"starting_positions": start_pos_data,
		"fauna_positions": fauna_data,
	}


func load_state(state: Dictionary) -> void:
	_map_width = int(state.get("map_width", _map_width))
	_map_height = int(state.get("map_height", _map_height))
	_seed_value = int(state.get("seed", _seed_value))

	# Clear existing cells
	clear()
	_tile_grid.clear()
	_river_tiles.clear()
	_flow_directions.clear()
	_river_ids.clear()
	_river_widths.clear()
	_resource_positions.clear()
	_starting_positions.clear()
	_fauna_positions.clear()

	var grid_data: Dictionary = state.get("tile_grid", {})
	for key: String in grid_data:
		var parts := key.split(",")
		if parts.size() != 2:
			continue
		var pos := Vector2i(int(parts[0]), int(parts[1]))
		var terrain: String = grid_data[key]
		_tile_grid[pos] = terrain
		var sid: int = _pick_variant_sid(terrain, pos)
		if sid >= 0:
			set_cell(pos, sid, Vector2i.ZERO)

	# Deserialize river data (backward-compatible — missing key = no rivers)
	var river_data: Dictionary = state.get("river_data", {})
	if not river_data.is_empty():
		var rt: Dictionary = river_data.get("river_tiles", {})
		for key: String in rt:
			var parts := key.split(",")
			if parts.size() == 2:
				_river_tiles[Vector2i(int(parts[0]), int(parts[1]))] = true

		var fd: Dictionary = river_data.get("flow_directions", {})
		for key: String in fd:
			var parts := key.split(",")
			var dir_parts: PackedStringArray = str(fd[key]).split(",")
			if parts.size() == 2 and dir_parts.size() == 2:
				var pos := Vector2i(int(parts[0]), int(parts[1]))
				_flow_directions[pos] = Vector2i(int(dir_parts[0]), int(dir_parts[1]))

		var ri: Dictionary = river_data.get("river_ids", {})
		for key: String in ri:
			var parts := key.split(",")
			if parts.size() == 2:
				_river_ids[Vector2i(int(parts[0]), int(parts[1]))] = int(ri[key])

		var rw: Dictionary = river_data.get("river_widths", {})
		for key: String in rw:
			var parts := key.split(",")
			if parts.size() == 2:
				_river_widths[Vector2i(int(parts[0]), int(parts[1]))] = int(rw[key])

	# Deserialize resource positions (backward-compatible)
	var res_data: Dictionary = state.get("resource_positions", {})
	for res_name: String in res_data:
		var positions: Array[Vector2i] = []
		for pos_str in res_data[res_name]:
			var parts := str(pos_str).split(",")
			if parts.size() == 2:
				positions.append(Vector2i(int(parts[0]), int(parts[1])))
		_resource_positions[res_name] = positions

	# Deserialize starting positions (backward-compatible)
	var start_data: Array = state.get("starting_positions", [])
	for pos_str in start_data:
		var parts := str(pos_str).split(",")
		if parts.size() == 2:
			_starting_positions.append(Vector2i(int(parts[0]), int(parts[1])))

	# Deserialize fauna positions (backward-compatible)
	var fauna_data: Dictionary = state.get("fauna_positions", {})
	for fauna_name: String in fauna_data:
		var packs: Array[Dictionary] = []
		for pack in fauna_data[fauna_name]:
			var pack_dict: Dictionary = pack as Dictionary
			var pos_parts := str(pack_dict.get("position", "")).split(",")
			if pos_parts.size() == 2:
				(
					packs
					. append(
						{
							"position": Vector2i(int(pos_parts[0]), int(pos_parts[1])),
							"pack_size": int(pack_dict.get("pack_size", 2)),
							"contested": bool(pack_dict.get("contested", false)),
						}
					)
				)
		_fauna_positions[fauna_name] = packs

	queue_redraw()
	notify_runtime_tile_data_update()

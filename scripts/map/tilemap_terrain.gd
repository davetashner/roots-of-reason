extends TileMapLayer
## TileMapLayer-based terrain system with programmatic TileSet construction.
## Supports 7 terrain types with custom data layers for movement cost, buildability,
## and line-of-sight blocking. Replaces prototype_map.gd Sprite2D approach.

const TILE_SIZE := Vector2i(128, 64)
const TEXTURE_BASE_PATH := "res://assets/tiles/terrain/prototype/"

var _terrain_config: Dictionary = {}
var _map_gen_config: Dictionary = {}
var _tile_grid: Dictionary = {}  # Vector2i -> terrain name
var _terrain_properties: Dictionary = {}
var _terrain_costs: Dictionary = {}
var _map_width: int = 64
var _map_height: int = 64
var _seed_value: int = 42
var _terrain_weights: Dictionary = {}
var _source_ids: Dictionary = {}  # terrain_name -> source_id


func _ready() -> void:
	_load_config()
	_build_tileset()
	_generate_map()


func _load_config() -> void:
	var terrain_cfg := _load_settings("terrain")
	var map_gen_cfg := _load_settings("map_generation")

	_terrain_costs = terrain_cfg.get("terrain_costs", {})
	_terrain_properties = terrain_cfg.get("terrain_properties", {})

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
		}


func _load_settings(settings_name: String) -> Dictionary:
	if is_instance_valid(Engine.get_main_loop()):
		var dl: Node = Engine.get_main_loop().root.get_node_or_null("DataLoader")
		if dl and dl.has_method("get_settings"):
			return dl.get_settings(settings_name)
	# Direct file fallback for tests
	var path := "res://data/settings/%s.json" % settings_name
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

	# One atlas source per terrain type
	var source_id := 0
	for terrain_name: String in _terrain_weights:
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

		# Set custom data on the tile
		var tile_data: TileData = source.get_tile_data(Vector2i.ZERO, 0)
		tile_data.set_custom_data("terrain_type", terrain_name)

		var cost: float = float(_terrain_costs.get(terrain_name, 1.0))
		tile_data.set_custom_data("movement_cost", cost)

		var props: Dictionary = _terrain_properties.get(terrain_name, {})
		tile_data.set_custom_data("buildable", props.get("buildable", true))
		tile_data.set_custom_data("blocks_los", props.get("blocks_los", false))

		_source_ids[terrain_name] = source_id
		source_id += 1

	tile_set = ts


func _generate_map() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_value

	# Build weighted lookup
	var weighted_terrains: Array[String] = []
	for terrain_name: String in _terrain_weights:
		var weight: int = int(_terrain_weights[terrain_name])
		for i in weight:
			weighted_terrains.append(terrain_name)

	if weighted_terrains.is_empty():
		push_warning("TilemapTerrain: No terrain weights configured")
		return

	for row in _map_height:
		for col in _map_width:
			var terrain: String = weighted_terrains[rng.randi_range(0, weighted_terrains.size() - 1)]
			_tile_grid[Vector2i(col, row)] = terrain
			var sid: int = _source_ids.get(terrain, -1)
			if sid >= 0:
				set_cell(Vector2i(col, row), sid, Vector2i.ZERO)


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


# -- Save / Load --


func save_state() -> Dictionary:
	var grid_data: Dictionary = {}
	for pos: Vector2i in _tile_grid:
		var key := "%d,%d" % [pos.x, pos.y]
		grid_data[key] = _tile_grid[pos]
	return {
		"map_width": _map_width,
		"map_height": _map_height,
		"seed": _seed_value,
		"tile_grid": grid_data,
	}


func load_state(state: Dictionary) -> void:
	_map_width = int(state.get("map_width", _map_width))
	_map_height = int(state.get("map_height", _map_height))
	_seed_value = int(state.get("seed", _seed_value))

	# Clear existing cells
	clear()
	_tile_grid.clear()

	var grid_data: Dictionary = state.get("tile_grid", {})
	for key: String in grid_data:
		var parts := key.split(",")
		if parts.size() != 2:
			continue
		var pos := Vector2i(int(parts[0]), int(parts[1]))
		var terrain: String = grid_data[key]
		_tile_grid[pos] = terrain
		var sid: int = _source_ids.get(terrain, -1)
		if sid >= 0:
			set_cell(pos, sid, Vector2i.ZERO)

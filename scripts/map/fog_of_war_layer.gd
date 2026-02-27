extends TileMapLayer
## Fog of war overlay that renders black (unexplored), dim (explored), or
## clear (visible) tiles on top of the terrain layer. Updates only changed
## tiles via diff against previous state.

const TILE_SIZE := Vector2i(128, 64)
const TEXTURE_BASE_PATH := "res://assets/tiles/terrain/prototype/"

var _source_id_black: int = -1
var _source_id_dim: int = -1
var _map_width: int = 64
var _map_height: int = 64
var _player_id: int = 0


func setup(map_width: int, map_height: int, player_id: int = 0) -> void:
	_map_width = map_width
	_map_height = map_height
	_player_id = player_id
	_build_tileset()
	_initialize_fog()
	queue_redraw()
	notify_runtime_tile_data_update()


func _build_tileset() -> void:
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_size = TILE_SIZE

	var source_id := 0

	# Black fog tile (fully opaque)
	var black_tex_path := TEXTURE_BASE_PATH + "fog_black.png"
	var black_tex: Texture2D = load(black_tex_path)
	if black_tex != null:
		var black_source := TileSetAtlasSource.new()
		black_source.texture = black_tex
		black_source.texture_region_size = TILE_SIZE
		ts.add_source(black_source, source_id)
		black_source.create_tile(Vector2i.ZERO)
		_source_id_black = source_id
		source_id += 1

	# Dim fog tile (semi-transparent)
	var dim_tex_path := TEXTURE_BASE_PATH + "fog_dim.png"
	var dim_tex: Texture2D = load(dim_tex_path)
	if dim_tex != null:
		var dim_source := TileSetAtlasSource.new()
		dim_source.texture = dim_tex
		dim_source.texture_region_size = TILE_SIZE
		ts.add_source(dim_source, source_id)
		dim_source.create_tile(Vector2i.ZERO)
		_source_id_dim = source_id
		source_id += 1

	tile_set = ts


func _initialize_fog() -> void:
	# Start with all tiles fogged (black)
	if _source_id_black < 0:
		return
	for y in _map_height:
		for x in _map_width:
			set_cell(Vector2i(x, y), _source_id_black, Vector2i.ZERO)


func update_fog(
	visible_tiles: Dictionary,
	explored_tiles: Dictionary,
	prev_visible_tiles: Dictionary = {},
) -> void:
	# Collect all changes into batches before applying.
	# Each batch is an array of tiles that need the same operation.
	var cells_to_dim: Array[Vector2i] = []
	var cells_to_black: Array[Vector2i] = []
	var cells_to_clear: Array[Vector2i] = []

	# Tiles that were visible but no longer are → dim (if explored) or black
	for tile: Vector2i in prev_visible_tiles:
		if not visible_tiles.has(tile):
			if explored_tiles.has(tile):
				if _source_id_dim >= 0:
					cells_to_dim.append(tile)
			else:
				if _source_id_black >= 0:
					cells_to_black.append(tile)

	# Tiles that are now visible → clear (erase cell)
	for tile: Vector2i in visible_tiles:
		if not prev_visible_tiles.has(tile):
			cells_to_clear.append(tile)

	# Newly explored tiles that aren't visible → dim
	# (handles first-time exploration when prev_visible was empty)
	if prev_visible_tiles.is_empty():
		for tile: Vector2i in explored_tiles:
			if not visible_tiles.has(tile):
				if _source_id_dim >= 0:
					cells_to_dim.append(tile)

	# Apply batched changes — skip tiles already in the correct state
	_apply_batch_set(cells_to_dim, _source_id_dim)
	_apply_batch_set(cells_to_black, _source_id_black)
	_apply_batch_erase(cells_to_clear)


func _apply_batch_set(tiles: Array[Vector2i], source_id: int) -> void:
	if tiles.is_empty() or source_id < 0:
		return
	for tile: Vector2i in tiles:
		if get_cell_source_id(tile) != source_id:
			set_cell(tile, source_id, Vector2i.ZERO)


func _apply_batch_erase(tiles: Array[Vector2i]) -> void:
	if tiles.is_empty():
		return
	for tile: Vector2i in tiles:
		if get_cell_source_id(tile) != -1:
			erase_cell(tile)

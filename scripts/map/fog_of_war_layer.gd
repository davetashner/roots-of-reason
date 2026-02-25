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


func _build_tileset() -> void:
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
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
	# Tiles that were visible but no longer are → dim (if explored) or black
	for tile: Vector2i in prev_visible_tiles:
		if not visible_tiles.has(tile):
			if explored_tiles.has(tile):
				if _source_id_dim >= 0:
					set_cell(tile, _source_id_dim, Vector2i.ZERO)
			else:
				if _source_id_black >= 0:
					set_cell(tile, _source_id_black, Vector2i.ZERO)

	# Tiles that are now visible → clear (erase cell)
	for tile: Vector2i in visible_tiles:
		if not prev_visible_tiles.has(tile):
			erase_cell(tile)

	# Newly explored tiles that aren't visible → dim
	# (handles first-time exploration when prev_visible was empty)
	if prev_visible_tiles.is_empty():
		for tile: Vector2i in explored_tiles:
			if not visible_tiles.has(tile):
				if _source_id_dim >= 0:
					set_cell(tile, _source_id_dim, Vector2i.ZERO)

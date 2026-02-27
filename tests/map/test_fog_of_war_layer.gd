extends GdUnitTestSuite
## Tests for fog_of_war_layer.gd — rendering overlay logic.
## Note: These tests verify the fog state tracking, not visual rendering.

const FogOfWarLayerScript := preload("res://scripts/map/fog_of_war_layer.gd")

const MAP_W := 8
const MAP_H := 8


func _make_fog_layer() -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.set_script(FogOfWarLayerScript)
	add_child(layer)
	# Note: setup() requires fog tile textures to exist.
	# We test the logic by calling update_fog() directly.
	return layer


# -- State tracking tests --
# These tests exercise update_fog() behavior with mock tile IDs.


func test_visible_tiles_cleared() -> void:
	var layer := _make_fog_layer()
	# Manually set up source IDs for testing
	layer._source_id_black = 0
	layer._source_id_dim = 1
	layer._map_width = MAP_W
	layer._map_height = MAP_H

	var visible: Dictionary = {Vector2i(3, 3): true, Vector2i(4, 4): true}
	var explored: Dictionary = {Vector2i(3, 3): true, Vector2i(4, 4): true}

	# First update — prev_visible empty, so explored non-visible get dim
	layer.update_fog(visible, explored, {})

	# Visible tiles should have cells erased (no fog)
	var cell := layer.get_cell_source_id(Vector2i(3, 3))
	assert_int(cell).is_equal(-1)  # erased = no source


func test_explored_tiles_dimmed_when_not_visible() -> void:
	var layer := _make_fog_layer()
	layer._source_id_black = 0
	layer._source_id_dim = 1
	layer._map_width = MAP_W
	layer._map_height = MAP_H

	var visible: Dictionary = {Vector2i(3, 3): true}
	var explored: Dictionary = {Vector2i(3, 3): true, Vector2i(5, 5): true}

	# First pass
	layer.update_fog(visible, explored, {})

	# (5,5) is explored but not visible — should be dim
	var cell := layer.get_cell_source_id(Vector2i(5, 5))
	assert_int(cell).is_equal(1)  # dim source


func test_previously_visible_becomes_dim() -> void:
	var layer := _make_fog_layer()
	layer._source_id_black = 0
	layer._source_id_dim = 1
	layer._map_width = MAP_W
	layer._map_height = MAP_H

	var prev_visible: Dictionary = {Vector2i(3, 3): true}
	var visible: Dictionary = {}  # No longer visible
	var explored: Dictionary = {Vector2i(3, 3): true}

	layer.update_fog(visible, explored, prev_visible)

	# (3,3) was visible, now explored-only → dim
	var cell := layer.get_cell_source_id(Vector2i(3, 3))
	assert_int(cell).is_equal(1)  # dim source


func test_unexplored_stays_fogged() -> void:
	var layer := _make_fog_layer()
	layer._source_id_black = 0
	layer._source_id_dim = 1
	layer._map_width = MAP_W
	layer._map_height = MAP_H

	# Initialize fog
	layer._initialize_fog()

	var visible: Dictionary = {Vector2i(3, 3): true}
	var explored: Dictionary = {Vector2i(3, 3): true}

	layer.update_fog(visible, explored, {})

	# (7,7) was never explored — should still be black
	var cell := layer.get_cell_source_id(Vector2i(7, 7))
	assert_int(cell).is_equal(0)  # black source


# -- Batch helper tests --


func test_batch_skips_redundant_set() -> void:
	var layer := _make_fog_layer()
	layer._source_id_black = 0
	layer._source_id_dim = 1
	layer._map_width = MAP_W
	layer._map_height = MAP_H

	# Manually set a cell to dim
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_size = Vector2i(128, 64)
	var src0 := TileSetAtlasSource.new()
	src0.texture = PlaceholderTexture2D.new()
	src0.texture_region_size = Vector2i(128, 64)
	ts.add_source(src0, 0)
	src0.create_tile(Vector2i.ZERO)
	var src1 := TileSetAtlasSource.new()
	src1.texture = PlaceholderTexture2D.new()
	src1.texture_region_size = Vector2i(128, 64)
	ts.add_source(src1, 1)
	src1.create_tile(Vector2i.ZERO)
	layer.tile_set = ts

	# Set cell to dim, then batch-set to dim again — should be a no-op
	layer.set_cell(Vector2i(2, 2), 1, Vector2i.ZERO)
	var tiles: Array[Vector2i] = [Vector2i(2, 2)]
	layer._apply_batch_set(tiles, 1)
	# Cell should still be dim (source 1)
	assert_int(layer.get_cell_source_id(Vector2i(2, 2))).is_equal(1)


func test_batch_erase_skips_already_erased() -> void:
	var layer := _make_fog_layer()
	layer._source_id_black = 0
	layer._source_id_dim = 1
	layer._map_width = MAP_W
	layer._map_height = MAP_H

	# Cell starts erased (-1) — batch erase should not crash
	var tiles: Array[Vector2i] = [Vector2i(5, 5)]
	layer._apply_batch_erase(tiles)
	assert_int(layer.get_cell_source_id(Vector2i(5, 5))).is_equal(-1)


func test_batch_empty_arrays_noop() -> void:
	var layer := _make_fog_layer()
	layer._source_id_black = 0
	layer._source_id_dim = 1

	# Empty batches should not crash
	var empty: Array[Vector2i] = []
	layer._apply_batch_set(empty, 0)
	layer._apply_batch_erase(empty)

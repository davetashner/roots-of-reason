extends Control
## Minimap HUD element — shows terrain, fog of war, entity positions, and camera
## viewport with click-to-pan and right-click-to-move support.

signal minimap_move_command(world_pos: Vector2)

const MINIMAP_SIZE := 200
const BORDER_COLOR := Color(0.3, 0.3, 0.3, 1.0)
const VIEWPORT_COLOR := Color(1.0, 1.0, 1.0, 0.8)

const TERRAIN_COLORS: Dictionary = {
	"grass": Color("59A633"),
	"dirt": Color("A67341"),
	"sand": Color("D9CC73"),
	"water": Color("2666BF"),
	"forest": Color("1A661A"),
	"stone": Color("8C8C8C"),
	"mountain": Color("736666"),
	"river": Color("4A90C4"),
	"shore": Color("C2B280"),
	"shallows": Color("7EC8E3"),
	"deep_water": Color("2B5F8A"),
}
const DEFAULT_TERRAIN_COLOR := Color(0.2, 0.2, 0.2)

var _map_node: Node = null
var _camera: Camera2D = null
var _visibility_manager: Node = null
var _scene_root: Node = null

var _scale: float = 1.0
var _map_width: int = 0
var _map_height: int = 0

var _terrain_image: Image = null
var _terrain_texture: ImageTexture = null
var _fog_image: Image = null
var _fog_texture: ImageTexture = null
var _fog_dirty: bool = true


func setup(map_node: Node, camera: Camera2D, visibility_mgr: Node, scene_root: Node) -> void:
	_map_node = map_node
	_camera = camera
	_visibility_manager = visibility_mgr
	_scene_root = scene_root

	var dims: Vector2i = _map_node.get_map_dimensions()
	_map_width = dims.x
	_map_height = dims.y
	_scale = float(MINIMAP_SIZE) / float(maxi(_map_width, _map_height))

	_bake_terrain_texture()
	_rebuild_fog_image()

	if _visibility_manager != null and _visibility_manager.has_signal("visibility_changed"):
		_visibility_manager.visibility_changed.connect(_on_visibility_changed)


func _ready() -> void:
	custom_minimum_size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
	size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(_delta: float) -> void:
	queue_redraw()


func _bake_terrain_texture() -> void:
	_terrain_image = Image.create(MINIMAP_SIZE, MINIMAP_SIZE, false, Image.FORMAT_RGBA8)
	_terrain_image.fill(DEFAULT_TERRAIN_COLOR)

	if _map_node == null:
		_terrain_texture = ImageTexture.create_from_image(_terrain_image)
		return

	var tile_grid: Dictionary = _map_node.get_tile_grid()

	for py in MINIMAP_SIZE:
		for px in MINIMAP_SIZE:
			var grid_pos := _minimap_to_grid(Vector2(px, py))
			var grid_cell := Vector2i(roundi(grid_pos.x), roundi(grid_pos.y))
			var terrain: String = tile_grid.get(grid_cell, "")
			if terrain.is_empty():
				continue
			# River overlay check
			if _map_node.has_method("is_river") and _map_node.is_river(grid_cell):
				_terrain_image.set_pixel(px, py, TERRAIN_COLORS.get("river", DEFAULT_TERRAIN_COLOR))
			else:
				_terrain_image.set_pixel(px, py, TERRAIN_COLORS.get(terrain, DEFAULT_TERRAIN_COLOR))

	_terrain_texture = ImageTexture.create_from_image(_terrain_image)


func _rebuild_fog_image() -> void:
	_fog_image = Image.create(MINIMAP_SIZE, MINIMAP_SIZE, false, Image.FORMAT_RGBA8)
	_fog_image.fill(Color(0.0, 0.0, 0.0, 1.0))  # Start fully black (unexplored)

	if _visibility_manager == null:
		_fog_texture = ImageTexture.create_from_image(_fog_image)
		_fog_dirty = false
		return

	var visible_tiles: Dictionary = _visibility_manager.get_visible_tiles(0)
	var explored_tiles: Dictionary = _visibility_manager.get_explored_tiles(0)

	for py in MINIMAP_SIZE:
		for px in MINIMAP_SIZE:
			var grid_pos := _minimap_to_grid(Vector2(px, py))
			var grid_cell := Vector2i(roundi(grid_pos.x), roundi(grid_pos.y))
			if visible_tiles.has(grid_cell):
				_fog_image.set_pixel(px, py, Color(0.0, 0.0, 0.0, 0.0))  # Fully transparent
			elif explored_tiles.has(grid_cell):
				_fog_image.set_pixel(px, py, Color(0.0, 0.0, 0.0, 0.5))  # Semi-transparent
			# else: stays black (unexplored)

	_fog_texture = ImageTexture.create_from_image(_fog_image)
	_fog_dirty = false


func _draw() -> void:
	# Background
	draw_rect(Rect2(Vector2.ZERO, Vector2(MINIMAP_SIZE, MINIMAP_SIZE)), Color(0.1, 0.1, 0.1, 0.8))

	# Terrain
	if _terrain_texture != null:
		draw_texture(_terrain_texture, Vector2.ZERO)

	# Fog of war
	if _fog_dirty:
		_rebuild_fog_image()
	if _fog_texture != null:
		draw_texture(_fog_texture, Vector2.ZERO)

	# Entity dots
	_draw_entities()

	# Camera viewport rect
	_draw_camera_rect()

	# Border
	draw_rect(Rect2(Vector2.ZERO, Vector2(MINIMAP_SIZE, MINIMAP_SIZE)), BORDER_COLOR, false, 2.0)


func _draw_entities() -> void:
	if _scene_root == null:
		return

	var visible_tiles: Dictionary = {}
	if _visibility_manager != null:
		visible_tiles = _visibility_manager.get_visible_tiles(0)

	for child in _scene_root.get_children():
		if not (child is Node2D):
			continue
		if "owner_id" not in child:
			continue
		# Skip dead entities
		if "hp" in child and child.hp <= 0:
			continue

		var owner_id: int = child.owner_id
		# AI entities only shown if visible
		if owner_id > 0 and not visible_tiles.is_empty():
			var grid_cell := Vector2i(IsoUtils.screen_to_grid(child.position))
			if not visible_tiles.has(grid_cell):
				continue

		# Determine color
		var dot_color: Color
		if owner_id == 0:
			dot_color = Color(0.2, 0.5, 1.0)  # Blue — player
		elif owner_id < 0:
			dot_color = Color(0.5, 0.5, 0.5)  # Gray — gaia
		else:
			dot_color = Color(1.0, 0.2, 0.2)  # Red — AI

		# Determine dot size — buildings larger than units
		var dot_size: float = 2.0
		if "building_name" in child:
			dot_size = 4.0

		var minimap_pos := _grid_to_minimap(IsoUtils.screen_to_grid(child.position))
		# Clamp to minimap bounds
		minimap_pos.x = clampf(minimap_pos.x, 0.0, float(MINIMAP_SIZE))
		minimap_pos.y = clampf(minimap_pos.y, 0.0, float(MINIMAP_SIZE))
		draw_rect(
			Rect2(minimap_pos - Vector2(dot_size, dot_size) * 0.5, Vector2(dot_size, dot_size)),
			dot_color,
		)


func _draw_camera_rect() -> void:
	if _camera == null or not _camera.is_inside_tree():
		return

	var vp_size := _camera.get_viewport_rect().size
	var cam_zoom: float = _camera.zoom.x
	var half_view := vp_size / (2.0 * cam_zoom)
	var cam_pos: Vector2 = _camera.position

	# Four corners of the camera viewport in world space
	var corners: Array[Vector2] = [
		cam_pos + Vector2(-half_view.x, -half_view.y),
		cam_pos + Vector2(half_view.x, -half_view.y),
		cam_pos + Vector2(half_view.x, half_view.y),
		cam_pos + Vector2(-half_view.x, half_view.y),
	]

	# Convert to minimap space
	var minimap_corners: PackedVector2Array = PackedVector2Array()
	for corner in corners:
		var grid := IsoUtils.screen_to_grid(corner)
		minimap_corners.append(_grid_to_minimap(grid))
	# Close the loop
	minimap_corners.append(minimap_corners[0])

	draw_polyline(minimap_corners, VIEWPORT_COLOR, 1.5)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_handle_left_click(mb.position)
				accept_event()
			elif mb.button_index == MOUSE_BUTTON_RIGHT:
				_handle_right_click(mb.position)
				accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_handle_left_click(mm.position)
			accept_event()


func _handle_left_click(local_pos: Vector2) -> void:
	if _camera == null:
		return
	var world_pos := _minimap_to_world(local_pos)
	_camera.position = world_pos


func _handle_right_click(local_pos: Vector2) -> void:
	var world_pos := _minimap_to_world(local_pos)
	minimap_move_command.emit(world_pos)


func _grid_to_minimap(grid_pos: Vector2) -> Vector2:
	return Vector2(grid_pos.x * _scale, grid_pos.y * _scale)


func _minimap_to_grid(minimap_px: Vector2) -> Vector2:
	if _scale <= 0.0:
		return Vector2.ZERO
	return Vector2(minimap_px.x / _scale, minimap_px.y / _scale)


func _minimap_to_world(minimap_px: Vector2) -> Vector2:
	var grid := _minimap_to_grid(minimap_px)
	return IsoUtils.grid_to_screen(grid)


func _on_visibility_changed(player_id: int) -> void:
	if player_id == 0:
		_fog_dirty = true


func get_terrain_texture() -> ImageTexture:
	return _terrain_texture


func get_fog_texture() -> ImageTexture:
	return _fog_texture


func get_minimap_scale() -> float:
	return _scale

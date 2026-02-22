class_name IsoUtils
## Isometric coordinate conversion utilities.
## Tile size: 128x64 (2:1 ratio)

const TILE_WIDTH: int = 128
const TILE_HEIGHT: int = 64
const HALF_W: float = TILE_WIDTH / 2.0
const HALF_H: float = TILE_HEIGHT / 2.0


## Convert grid coordinates (col, row) to screen position (pixels).
static func grid_to_screen(grid_pos: Vector2) -> Vector2:
	var screen_x: float = (grid_pos.x - grid_pos.y) * HALF_W
	var screen_y: float = (grid_pos.x + grid_pos.y) * HALF_H
	return Vector2(screen_x, screen_y)


## Convert screen position (pixels) to grid coordinates.
static func screen_to_grid(screen_pos: Vector2) -> Vector2:
	var grid_x: float = (screen_pos.x / HALF_W + screen_pos.y / HALF_H) / 2.0
	var grid_y: float = (screen_pos.y / HALF_H - screen_pos.x / HALF_W) / 2.0
	return Vector2(grid_x, grid_y)


## Snap to nearest grid cell.
static func snap_to_grid(screen_pos: Vector2) -> Vector2i:
	var grid: Vector2 = screen_to_grid(screen_pos)
	return Vector2i(roundi(grid.x), roundi(grid.y))

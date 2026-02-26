extends RefCounted
## Reclassifies water and adjacent land tiles into shore, shallows, and deep_water
## based on 8-directional adjacency. Creates natural 3-band coastlines:
## land -> shore -> shallows -> deep_water.

const DIRECTIONS_8 := [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
	Vector2i(1, 1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(-1, -1),
]

## Land types that never become shore (they have special terrain behavior).
const NEVER_SHORE := ["mountain", "river"]

var _shore_enabled: bool = true


func configure(config: Dictionary) -> void:
	_shore_enabled = bool(config.get("shore_enabled", _shore_enabled))


func generate(tile_grid: Dictionary, map_width: int, map_height: int) -> Dictionary:
	var changes: Dictionary = {}  # Vector2i -> String

	if not _shore_enabled:
		return {"changes": changes}

	# Two-phase collect-then-apply: scan all tiles, then apply changes.
	# This prevents cascading (e.g. a newly-assigned shore triggering more shore).
	for y in map_height:
		for x in map_width:
			var pos := Vector2i(x, y)
			var terrain: String = tile_grid.get(pos, "")
			if terrain.is_empty():
				continue

			if terrain == "water":
				# Water adjacent to any land -> shallows; otherwise -> deep_water
				if _has_land_neighbor(pos, tile_grid):
					changes[pos] = "shallows"
				else:
					changes[pos] = "deep_water"
			elif terrain not in NEVER_SHORE:
				# Walkable land adjacent to water -> shore
				if _has_water_neighbor(pos, tile_grid):
					changes[pos] = "shore"

	return {"changes": changes}


func _has_land_neighbor(pos: Vector2i, tile_grid: Dictionary) -> bool:
	for dir: Vector2i in DIRECTIONS_8:
		var neighbor := pos + dir
		var t: String = tile_grid.get(neighbor, "")
		if not t.is_empty() and t != "water":
			return true
	return false


func _has_water_neighbor(pos: Vector2i, tile_grid: Dictionary) -> bool:
	for dir: Vector2i in DIRECTIONS_8:
		var neighbor := pos + dir
		var t: String = tile_grid.get(neighbor, "")
		if t == "water":
			return true
	return false

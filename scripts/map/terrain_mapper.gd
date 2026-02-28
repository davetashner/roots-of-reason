class_name TerrainMapper
extends RefCounted
## Maps elevation and moisture noise values to terrain types.
## Thresholds are configurable via map_generation.json.
## Used by tilemap_terrain.gd to replace random weighted terrain generation
## with procedural noise-based terrain.

var _thresholds: Dictionary = {
	"water": 0.30,
	"sand": 0.40,
	"grass": 0.70,
	"stone": 0.85,
	"mountain": 1.0,
}
var _forest_moisture_threshold: float = 0.55
var _dirt_moisture_threshold: float = 0.30
var _canyon_moisture_threshold: float = 0.30


func configure(config: Dictionary) -> void:
	var thresholds: Dictionary = config.get("terrain_thresholds", {})
	if not thresholds.is_empty():
		_thresholds = thresholds
	_forest_moisture_threshold = float(config.get("forest_moisture_threshold", _forest_moisture_threshold))
	_dirt_moisture_threshold = float(config.get("dirt_moisture_threshold", _dirt_moisture_threshold))
	_canyon_moisture_threshold = float(config.get("canyon_moisture_threshold", _canyon_moisture_threshold))


func get_terrain(elevation: float, moisture: float) -> String:
	if elevation < _thresholds.get("water", 0.30):
		return "water"
	if elevation < _thresholds.get("sand", 0.40):
		return "sand"
	if elevation < _thresholds.get("grass", 0.70):
		return _grass_biome(moisture)
	if elevation < _thresholds.get("stone", 0.85):
		if moisture < _canyon_moisture_threshold:
			return "canyon"
		return "stone"
	return "mountain"


func _grass_biome(moisture: float) -> String:
	if moisture >= _forest_moisture_threshold:
		return "forest"
	if moisture < _dirt_moisture_threshold:
		return "dirt"
	return "grass"


static func apply_island_mask(
	elevation_grid: Dictionary,
	map_width: int,
	map_height: int,
	edge_width: int = 3,
	falloff_width: int = 8,
) -> void:
	## Modifies elevation_grid in-place: cells near edges get reduced elevation,
	## forcing them to become water.
	for pos: Vector2i in elevation_grid:
		var dist_to_edge: int = _min_edge_distance(pos, map_width, map_height)
		if dist_to_edge < edge_width:
			elevation_grid[pos] = 0.0
		elif dist_to_edge < edge_width + falloff_width:
			var t: float = float(dist_to_edge - edge_width) / float(falloff_width)
			elevation_grid[pos] = elevation_grid[pos] * t


static func _min_edge_distance(pos: Vector2i, w: int, h: int) -> int:
	return mini(mini(pos.x, w - 1 - pos.x), mini(pos.y, h - 1 - pos.y))

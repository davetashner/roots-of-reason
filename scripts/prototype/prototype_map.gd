extends Node2D
## Procedurally generates a 20x20 isometric tile map using Sprite2D nodes
## positioned on an isometric grid. Uses the generated prototype tile PNGs.

const MAP_SIZE: int = 20
const SEED_VALUE: int = 42

# Terrain types with weights (must sum to 100)
const TERRAIN_WEIGHTS: Dictionary = {
	"grass": 60,
	"forest": 15,
	"desert": 10,
	"water": 15,
}

var _tile_textures: Dictionary = {}


func _ready() -> void:
	_load_textures()
	_generate_map()


func _load_textures() -> void:
	var base_path := "res://assets/tiles/terrain/prototype/"
	for terrain_name in TERRAIN_WEIGHTS.keys():
		var path: String = base_path + terrain_name + ".png"
		var tex := load(path)
		if tex != null:
			_tile_textures[terrain_name] = tex
		else:
			push_warning("Could not load tile texture: " + path)


func _generate_map() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_VALUE

	# Build weighted lookup
	var weighted_terrains: Array[String] = []
	for terrain_name: String in TERRAIN_WEIGHTS:
		var weight: int = TERRAIN_WEIGHTS[terrain_name]
		for i in weight:
			weighted_terrains.append(terrain_name)

	for row in MAP_SIZE:
		for col in MAP_SIZE:
			var terrain: String = weighted_terrains[rng.randi_range(0, weighted_terrains.size() - 1)]
			_place_tile(col, row, terrain)


func _place_tile(col: int, row: int, terrain: String) -> void:
	if terrain not in _tile_textures:
		return
	var sprite := Sprite2D.new()
	sprite.texture = _tile_textures[terrain]
	sprite.position = IsoUtils.grid_to_screen(Vector2(col, row))
	sprite.z_index = col + row  # Proper depth sorting
	add_child(sprite)

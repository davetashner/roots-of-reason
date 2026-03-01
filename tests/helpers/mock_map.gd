## Shared mock map for tests — supports the buildable + terrain API used by
## AI economy, build planner, and nomadic save/load tests.
##
## Usage:
##   const MockMap = preload("res://tests/helpers/mock_map.gd")
##   var m := MockMap.new()
##   _root.add_child(m)
extends Node

var _map_size: int = 64
var _terrain: Dictionary = {}


func get_map_size() -> int:
	return _map_size


func get_map_dimensions() -> Vector2i:
	return Vector2i(_map_size, _map_size)


func is_buildable(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < _map_size and cell.y >= 0 and cell.y < _map_size


func get_terrain_at(_cell: Vector2i) -> String:
	return _terrain.get(_cell, "grass")

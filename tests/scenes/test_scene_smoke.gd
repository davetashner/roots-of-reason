extends GdUnitTestSuite
## Smoke tests — verify every .tscn in the project loads without error.


func test_all_scenes_load() -> void:
	var scene_paths := _discover_scenes("res://scenes")
	assert_array(scene_paths).is_not_empty()
	for path: String in scene_paths:
		var scene: PackedScene = load(path)
		assert_object(scene).override_failure_message("Failed to load scene: %s" % path).is_not_null()


func _discover_scenes(root: String) -> Array[String]:
	var results: Array[String] = []
	_scan_dir(root, results)
	return results


func _scan_dir(path: String, results: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		var full_path := path.path_join(file_name)
		if dir.current_is_dir():
			_scan_dir(full_path, results)
		elif file_name.ends_with(".tscn"):
			results.append(full_path)
		file_name = dir.get_next()
	dir.list_dir_end()

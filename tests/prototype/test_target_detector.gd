extends GdUnitTestSuite
## Tests for TargetDetector — spatial entity lookup.

const DetectorScript := preload("res://scripts/prototype/target_detector.gd")
const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")


func _create_detector() -> Node:
	var detector := Node.new()
	detector.set_script(DetectorScript)
	return auto_free(detector)


func _create_entity(pos: Vector2) -> Node2D:
	var entity := Node2D.new()
	entity.set_script(UnitScript)
	entity.position = pos
	entity.global_position = pos
	return auto_free(entity)


# -- detect() --


func test_detect_entity_at_position() -> void:
	var detector := _create_detector()
	var entity := _create_entity(Vector2(100, 100))
	detector.register_entity(entity)
	var result: Variant = detector.detect(Vector2(105, 100))
	assert_object(result).is_same(entity)


func test_detect_returns_null_empty_space() -> void:
	var detector := _create_detector()
	var entity := _create_entity(Vector2(100, 100))
	detector.register_entity(entity)
	var result: Variant = detector.detect(Vector2(500, 500))
	assert_object(result).is_null()


func test_detect_returns_closest() -> void:
	var detector := _create_detector()
	var far := _create_entity(Vector2(100, 100))
	var near := _create_entity(Vector2(110, 100))
	detector.register_entity(far)
	detector.register_entity(near)
	# Point closer to 'near'
	var result: Variant = detector.detect(Vector2(112, 100))
	assert_object(result).is_same(near)


func test_register_unregister() -> void:
	var detector := _create_detector()
	var entity := _create_entity(Vector2(100, 100))
	detector.register_entity(entity)
	detector.unregister_entity(entity)
	var result: Variant = detector.detect(Vector2(105, 100))
	assert_object(result).is_null()


func test_detect_skips_freed_entities() -> void:
	var detector := _create_detector()
	var e1 := _create_entity(Vector2(100, 100))
	var e2 := _create_entity(Vector2(200, 200))
	detector.register_entity(e1)
	detector.register_entity(e2)
	e1.free()
	var result: Variant = detector.detect(Vector2(205, 200))
	assert_object(result).is_same(e2)

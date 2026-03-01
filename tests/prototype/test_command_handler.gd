extends GdUnitTestSuite
## Tests for CommandHandler and all concrete command handler subclasses.

const FeedScript := preload("res://scripts/prototype/feed_command_handler.gd")
const BuildScript := preload("res://scripts/prototype/build_command_handler.gd")
const GatherScript := preload("res://scripts/prototype/gather_command_handler.gd")
const GarrisonScript := preload("res://scripts/prototype/garrison_command_handler.gd")
const EmbarkScript := preload("res://scripts/prototype/embark_command_handler.gd")
const DisembarkScript := preload("res://scripts/prototype/disembark_command_handler.gd")
const AttackScript := preload("res://scripts/prototype/attack_command_handler.gd")

var _pos := Vector2(100, 100)


## Helper: create a plain Node as a mock target with optional tracked methods.
func _mock_target(methods: Array[String] = []) -> Node:
	var target := Node.new()
	if not methods.is_empty():
		var src := "extends Node\n"
		for m in methods:
			src += "var %s_called := false\n" % m
			src += "var %s_arg = null\n" % m
			src += "func %s(a = null, b = null) -> void:\n\t%s_called = true\n\t%s_arg = a\n" % [m, m, m]
		var script := GDScript.new()
		script.source_code = src
		script.reload()
		target.set_script(script)
	return auto_free(target)


## Helper: create a Node2D unit with configurable methods via script.
func _mock_unit(methods: Array[String] = [], extra_vars: String = "") -> Node2D:
	var unit := Node2D.new()
	var src := "extends Node2D\n"
	if extra_vars != "":
		src += extra_vars + "\n"
	for m in methods:
		src += "var %s_called := false\n" % m
		src += "var %s_arg = null\n" % m
		src += "func %s(a = null, b = null) -> void:\n\t%s_called = true\n\t%s_arg = a\n" % [m, m, m]
	var script := GDScript.new()
	script.source_code = src
	script.reload()
	unit.set_script(script)
	return auto_free(unit)


## Helper: create a transport mock that tracks embarked count and disembark calls.
func _mock_transport(embarked: int) -> Node2D:
	var unit := Node2D.new()
	var src := (
		"extends Node2D\n"
		+ "var _embarked := %d\n" % embarked
		+ "var disembark_all_called := false\n"
		+ "var disembark_pos := Vector2.ZERO\n"
		+ "var move_to_called := false\n"
		+ "var move_to_arg := Vector2.ZERO\n"
		+ "func get_embarked_count() -> int:\n\treturn _embarked\n"
		+ "func disembark_all(pos: Vector2) -> void:\n"
		+ "\tdisembark_all_called = true\n\tdisembark_pos = pos\n"
		+ "func move_to(pos: Vector2) -> void:\n"
		+ "\tmove_to_called = true\n\tmove_to_arg = pos\n"
	)
	var script := GDScript.new()
	script.source_code = src
	script.reload()
	unit.set_script(script)
	return auto_free(unit)


# -- Base CommandHandler --


func test_base_can_handle_returns_false() -> void:
	var handler := CommandHandler.new()
	var target := _mock_target()
	var units: Array[Node] = [target]
	assert_bool(handler.can_handle("move", target, units, _pos)).is_false()


func test_base_execute_returns_false() -> void:
	var handler := CommandHandler.new()
	var target := _mock_target()
	var units: Array[Node] = [target]
	assert_bool(handler.execute("move", target, units, _pos)).is_false()


# -- FeedCommandHandler --


func test_feed_can_handle_with_feed_cmd_and_target() -> void:
	var handler: CommandHandler = FeedScript.new()
	var target := _mock_target()
	var units: Array[Node] = []
	assert_bool(handler.can_handle("feed", target, units, _pos)).is_true()


func test_feed_can_handle_rejects_wrong_cmd() -> void:
	var handler: CommandHandler = FeedScript.new()
	var target := _mock_target()
	var units: Array[Node] = []
	assert_bool(handler.can_handle("gather", target, units, _pos)).is_false()


func test_feed_can_handle_rejects_null_target() -> void:
	var handler: CommandHandler = FeedScript.new()
	var units: Array[Node] = []
	assert_bool(handler.can_handle("feed", null, units, _pos)).is_false()


func test_feed_execute_calls_assign_feed_target() -> void:
	var handler: CommandHandler = FeedScript.new()
	var target := _mock_target()
	var unit := _mock_unit(["assign_feed_target"])
	var units: Array[Node] = [unit]
	var result := handler.execute("feed", target, units, _pos)
	assert_bool(result).is_true()
	assert_bool(unit.assign_feed_target_called).is_true()
	assert_object(unit.assign_feed_target_arg).is_same(target)


func test_feed_execute_skips_units_without_method() -> void:
	var handler: CommandHandler = FeedScript.new()
	var target := _mock_target()
	var unit := _mock_unit([])  # no assign_feed_target
	var units: Array[Node] = [unit]
	var result := handler.execute("feed", target, units, _pos)
	assert_bool(result).is_true()


func test_feed_execute_returns_false_for_wrong_cmd() -> void:
	var handler: CommandHandler = FeedScript.new()
	var target := _mock_target()
	var units: Array[Node] = []
	assert_bool(handler.execute("attack", target, units, _pos)).is_false()


# -- BuildCommandHandler --


func test_build_can_handle_with_build_cmd_and_buildable_target() -> void:
	var handler: CommandHandler = BuildScript.new()
	var target := _mock_target(["apply_build_work"])
	var units: Array[Node] = []
	assert_bool(handler.can_handle("build", target, units, _pos)).is_true()


func test_build_can_handle_rejects_target_without_apply_build_work() -> void:
	var handler: CommandHandler = BuildScript.new()
	var target := _mock_target()
	var units: Array[Node] = []
	assert_bool(handler.can_handle("build", target, units, _pos)).is_false()


func test_build_can_handle_rejects_null_target() -> void:
	var handler: CommandHandler = BuildScript.new()
	var units: Array[Node] = []
	assert_bool(handler.can_handle("build", null, units, _pos)).is_false()


func test_build_execute_calls_assign_build_target() -> void:
	var handler: CommandHandler = BuildScript.new()
	var target := _mock_target(["apply_build_work"])
	var unit := _mock_unit(["assign_build_target"])
	var units: Array[Node] = [unit]
	var result := handler.execute("build", target, units, _pos)
	assert_bool(result).is_true()
	assert_bool(unit.assign_build_target_called).is_true()
	assert_object(unit.assign_build_target_arg).is_same(target)


func test_build_execute_returns_false_for_wrong_cmd() -> void:
	var handler: CommandHandler = BuildScript.new()
	var target := _mock_target(["apply_build_work"])
	var units: Array[Node] = []
	assert_bool(handler.execute("gather", target, units, _pos)).is_false()


# -- GatherCommandHandler --


func test_gather_can_handle_with_gather_cmd_and_target() -> void:
	var handler: CommandHandler = GatherScript.new()
	var target := _mock_target()
	var units: Array[Node] = []
	assert_bool(handler.can_handle("gather", target, units, _pos)).is_true()


func test_gather_can_handle_rejects_null_target() -> void:
	var handler: CommandHandler = GatherScript.new()
	var units: Array[Node] = []
	assert_bool(handler.can_handle("gather", null, units, _pos)).is_false()


func test_gather_execute_calls_assign_gather_target() -> void:
	var handler: CommandHandler = GatherScript.new()
	var target := _mock_target()
	var unit := _mock_unit(["assign_gather_target"])
	var units: Array[Node] = [unit]
	var result := handler.execute("gather", target, units, _pos)
	assert_bool(result).is_true()
	assert_bool(unit.assign_gather_target_called).is_true()
	assert_object(unit.assign_gather_target_arg).is_same(target)


func test_gather_execute_passes_offset_to_multiple_units() -> void:
	var handler: CommandHandler = GatherScript.new()
	var target := _mock_target()
	var unit_a := _mock_unit(["assign_gather_target"])
	var unit_b := _mock_unit(["assign_gather_target"])
	var units: Array[Node] = [unit_a, unit_b]
	var result := handler.execute("gather", target, units, _pos)
	assert_bool(result).is_true()
	assert_bool(unit_a.assign_gather_target_called).is_true()
	assert_bool(unit_b.assign_gather_target_called).is_true()


func test_gather_execute_returns_false_for_wrong_cmd() -> void:
	var handler: CommandHandler = GatherScript.new()
	var target := _mock_target()
	var units: Array[Node] = []
	assert_bool(handler.execute("build", target, units, _pos)).is_false()


# -- GarrisonCommandHandler --


func test_garrison_can_handle_with_garrisonable_target() -> void:
	var handler: CommandHandler = GarrisonScript.new()
	var target := _mock_target(["garrison_unit"])
	var units: Array[Node] = []
	assert_bool(handler.can_handle("garrison", target, units, _pos)).is_true()


func test_garrison_can_handle_rejects_target_without_garrison_unit() -> void:
	var handler: CommandHandler = GarrisonScript.new()
	var target := _mock_target()
	var units: Array[Node] = []
	assert_bool(handler.can_handle("garrison", target, units, _pos)).is_false()


func test_garrison_can_handle_rejects_null_target() -> void:
	var handler: CommandHandler = GarrisonScript.new()
	var units: Array[Node] = []
	assert_bool(handler.can_handle("garrison", null, units, _pos)).is_false()


func test_garrison_execute_calls_garrison_unit_on_target() -> void:
	var handler: CommandHandler = GarrisonScript.new()
	var target := _mock_target(["garrison_unit"])
	var unit := Node2D.new()
	auto_free(unit)
	var units: Array[Node] = [unit]
	var result := handler.execute("garrison", target, units, _pos)
	assert_bool(result).is_true()
	assert_bool(target.garrison_unit_called).is_true()


func test_garrison_execute_skips_non_node2d_units() -> void:
	var handler: CommandHandler = GarrisonScript.new()
	var target := _mock_target(["garrison_unit"])
	var unit := Node.new()  # Not Node2D
	auto_free(unit)
	var units: Array[Node] = [unit]
	var result := handler.execute("garrison", target, units, _pos)
	assert_bool(result).is_true()
	# garrison_unit should NOT have been called since unit is not Node2D
	assert_bool(target.garrison_unit_called).is_false()


func test_garrison_execute_returns_false_for_wrong_cmd() -> void:
	var handler: CommandHandler = GarrisonScript.new()
	var target := _mock_target(["garrison_unit"])
	var units: Array[Node] = []
	assert_bool(handler.execute("attack", target, units, _pos)).is_false()


# -- EmbarkCommandHandler --


func test_embark_can_handle_with_embarkable_target() -> void:
	var handler: CommandHandler = EmbarkScript.new()
	var target := _mock_target(["embark_unit"])
	var units: Array[Node] = []
	assert_bool(handler.can_handle("embark", target, units, _pos)).is_true()


func test_embark_can_handle_rejects_target_without_embark_unit() -> void:
	var handler: CommandHandler = EmbarkScript.new()
	var target := _mock_target()
	var units: Array[Node] = []
	assert_bool(handler.can_handle("embark", target, units, _pos)).is_false()


func test_embark_can_handle_rejects_null_target() -> void:
	var handler: CommandHandler = EmbarkScript.new()
	var units: Array[Node] = []
	assert_bool(handler.can_handle("embark", null, units, _pos)).is_false()


func test_embark_execute_moves_and_embarks_node2d_units() -> void:
	var handler: CommandHandler = EmbarkScript.new()
	# Target must be Node2D so global_position is accessible
	var target := Node2D.new()
	var tsrc := "extends Node2D\nvar embark_unit_called := false\n"
	tsrc += "func embark_unit(a = null) -> void:\n\tembark_unit_called = true\n"
	var tscript := GDScript.new()
	tscript.source_code = tsrc
	tscript.reload()
	target.set_script(tscript)
	auto_free(target)
	target.global_position = Vector2(50, 50)
	var unit := _mock_unit(["move_to"])
	var units: Array[Node] = [unit]
	var result := handler.execute("embark", target, units, _pos)
	assert_bool(result).is_true()
	assert_bool(unit.move_to_called).is_true()


func test_embark_execute_returns_false_for_wrong_cmd() -> void:
	var handler: CommandHandler = EmbarkScript.new()
	var target := _mock_target(["embark_unit"])
	var units: Array[Node] = []
	assert_bool(handler.execute("garrison", target, units, _pos)).is_false()


# -- DisembarkCommandHandler --


func test_disembark_can_handle_with_transport_no_target() -> void:
	var handler: CommandHandler = DisembarkScript.new()
	var transport := _mock_transport(3)
	var units: Array[Node] = [transport]
	assert_bool(handler.can_handle("move", null, units, _pos)).is_true()


func test_disembark_can_handle_rejects_when_target_present() -> void:
	var handler: CommandHandler = DisembarkScript.new()
	var target := _mock_target()
	var transport := _mock_transport(3)
	var units: Array[Node] = [transport]
	assert_bool(handler.can_handle("move", target, units, _pos)).is_false()


func test_disembark_can_handle_rejects_no_passengers() -> void:
	var handler: CommandHandler = DisembarkScript.new()
	var transport := _mock_transport(0)
	var units: Array[Node] = [transport]
	assert_bool(handler.can_handle("move", null, units, _pos)).is_false()


func test_disembark_execute_calls_disembark_all() -> void:
	var handler: CommandHandler = DisembarkScript.new()
	var transport := _mock_transport(2)
	var units: Array[Node] = [transport]
	var dest := Vector2(200, 200)
	var result := handler.execute("move", null, units, dest)
	assert_bool(result).is_true()
	assert_bool(transport.disembark_all_called).is_true()
	assert_vector(transport.disembark_pos).is_equal(dest)


func test_disembark_execute_moves_non_transport_units() -> void:
	var handler: CommandHandler = DisembarkScript.new()
	var transport := _mock_transport(2)
	var mover := _mock_unit(["move_to"], "func get_embarked_count() -> int:\n\treturn 0")
	var units: Array[Node] = [transport, mover]
	var dest := Vector2(300, 300)
	var result := handler.execute("move", null, units, dest)
	assert_bool(result).is_true()
	assert_bool(mover.move_to_called).is_true()


func test_disembark_execute_returns_false_with_target() -> void:
	var handler: CommandHandler = DisembarkScript.new()
	var target := _mock_target()
	var transport := _mock_transport(2)
	var units: Array[Node] = [transport]
	assert_bool(handler.execute("move", target, units, _pos)).is_false()


func test_disembark_has_transport_with_passengers_static() -> void:
	var transport := _mock_transport(1)
	var empty := _mock_transport(0)
	var with_passengers: Array[Node] = [transport]
	var without: Array[Node] = [empty]
	var empty_arr: Array[Node] = []
	assert_bool(DisembarkScript.has_transport_with_passengers(with_passengers)).is_true()
	assert_bool(DisembarkScript.has_transport_with_passengers(without)).is_false()
	assert_bool(DisembarkScript.has_transport_with_passengers(empty_arr)).is_false()


# -- Handler with empty unit list --


func test_feed_execute_with_empty_units_returns_true() -> void:
	var handler: CommandHandler = FeedScript.new()
	var target := _mock_target()
	var units: Array[Node] = []
	assert_bool(handler.execute("feed", target, units, _pos)).is_true()


func test_gather_execute_with_empty_units_returns_true() -> void:
	var handler: CommandHandler = GatherScript.new()
	var target := _mock_target()
	var units: Array[Node] = []
	assert_bool(handler.execute("gather", target, units, _pos)).is_true()


func test_build_execute_with_empty_units_returns_true() -> void:
	var handler: CommandHandler = BuildScript.new()
	var target := _mock_target(["apply_build_work"])
	var units: Array[Node] = []
	assert_bool(handler.execute("build", target, units, _pos)).is_true()


# -- AttackCommandHandler --


func test_attack_can_handle_with_attack_cmd_and_target() -> void:
	var handler: CommandHandler = AttackScript.new()
	var target := _mock_target()
	var units: Array[Node] = []
	assert_bool(handler.can_handle("attack", target, units, _pos)).is_true()


func test_attack_can_handle_rejects_wrong_cmd() -> void:
	var handler: CommandHandler = AttackScript.new()
	var target := _mock_target()
	var units: Array[Node] = []
	assert_bool(handler.can_handle("gather", target, units, _pos)).is_false()


func test_attack_can_handle_rejects_null_target() -> void:
	var handler: CommandHandler = AttackScript.new()
	var units: Array[Node] = []
	assert_bool(handler.can_handle("attack", null, units, _pos)).is_false()


func test_attack_execute_calls_assign_attack_target() -> void:
	var handler: CommandHandler = AttackScript.new()
	var target := _mock_target()
	var unit := _mock_unit(["assign_attack_target"])
	var units: Array[Node] = [unit]
	var result := handler.execute("attack", target, units, _pos)
	assert_bool(result).is_true()
	assert_bool(unit.assign_attack_target_called).is_true()
	assert_object(unit.assign_attack_target_arg).is_same(target)


func test_attack_execute_skips_units_without_method() -> void:
	var handler: CommandHandler = AttackScript.new()
	var target := _mock_target()
	var unit := _mock_unit([])
	var units: Array[Node] = [unit]
	var result := handler.execute("attack", target, units, _pos)
	assert_bool(result).is_true()


func test_attack_execute_returns_false_for_null_target() -> void:
	var handler: CommandHandler = AttackScript.new()
	var units: Array[Node] = []
	assert_bool(handler.execute("attack", null, units, _pos)).is_false()


func test_attack_execute_returns_false_for_wrong_cmd() -> void:
	var handler: CommandHandler = AttackScript.new()
	var target := _mock_target()
	var units: Array[Node] = []
	assert_bool(handler.execute("move", target, units, _pos)).is_false()

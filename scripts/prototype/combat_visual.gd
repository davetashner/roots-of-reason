class_name CombatVisual
extends RefCounted
## Static helper methods for combat visual effects — damage numbers, projectiles,
## attack flashes, and death animations. All methods are static; no instance state.


static func spawn_damage_number(parent: Node, world_pos: Vector2, amount: int, config: Dictionary) -> Label:
	var label := Label.new()
	label.text = str(amount)
	label.position = world_pos
	label.z_index = 100
	label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
	parent.add_child(label)

	var rise: float = float(config.get("damage_number_rise_distance", 30.0))
	var duration: float = float(config.get("damage_number_duration", 0.8))

	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", world_pos.y - rise, duration)
	tween.tween_property(label, "modulate:a", 0.0, duration)
	tween.set_parallel(false)
	tween.tween_callback(label.queue_free)
	return label


static func spawn_projectile(parent: Node, origin: Vector2, target_pos: Vector2, config: Dictionary) -> Node2D:
	var proj := _ProjectileDot.new()
	proj.radius = float(config.get("projectile_radius", 3.0))
	proj.position = origin
	proj.z_index = 90
	parent.add_child(proj)

	var speed: float = float(config.get("projectile_speed", 400.0))
	var dist: float = origin.distance_to(target_pos)
	var duration: float = dist / maxf(speed, 1.0)

	var tween := proj.create_tween()
	tween.tween_property(proj, "position", target_pos, duration)
	tween.tween_callback(proj.queue_free)
	return proj


static func play_attack_flash(node: Node2D, config: Dictionary) -> void:
	var duration: float = float(config.get("attack_flash_duration", 0.15))
	var tween := node.create_tween()
	tween.tween_property(node, "scale", Vector2(1.3, 1.3), duration * 0.5)
	tween.tween_property(node, "scale", Vector2(1.0, 1.0), duration * 0.5)


static func play_death_animation(node: Node2D, config: Dictionary) -> Tween:
	var duration: float = float(config.get("death_fade_duration", 0.5))
	if duration <= 0.0:
		return null
	var tween := node.create_tween()
	tween.set_parallel(true)
	tween.tween_property(node, "modulate", Color(0.5, 0.5, 0.5, 0.0), duration)
	return tween


static func spawn_splash_effect(parent: Node, world_pos: Vector2, config: Dictionary) -> Node2D:
	var splash := _SplashRing.new()
	splash.position = world_pos
	splash.z_index = 95
	splash.max_radius = float(config.get("destruction_splash_radius", 20.0))
	var color_arr: Array = config.get("destruction_splash_color", [0.3, 0.6, 1.0, 0.7])
	if color_arr.size() == 4:
		splash.ring_color = Color(color_arr[0], color_arr[1], color_arr[2], color_arr[3])
	var duration: float = float(config.get("destruction_splash_duration", 0.6))
	parent.add_child(splash)
	var tween := splash.create_tween()
	tween.set_parallel(true)
	tween.tween_property(splash, "current_radius", splash.max_radius, duration)
	tween.tween_property(splash, "modulate:a", 0.0, duration)
	tween.set_parallel(false)
	tween.tween_callback(splash.queue_free)
	return splash


static func spawn_resource_scatter(parent: Node, world_pos: Vector2, config: Dictionary) -> void:
	var scatter_radius: float = float(config.get("resource_scatter_radius", 30.0))
	var dot_count: int = int(config.get("resource_scatter_dot_count", 6))
	var duration: float = float(config.get("resource_scatter_duration", 0.8))
	for i in dot_count:
		var dot := _ScatterDot.new()
		dot.position = world_pos
		dot.z_index = 94
		parent.add_child(dot)
		var angle: float = TAU * float(i) / float(dot_count)
		var target := world_pos + Vector2(cos(angle), sin(angle)) * scatter_radius
		var tween := dot.create_tween()
		tween.set_parallel(true)
		tween.tween_property(dot, "position", target, duration)
		tween.tween_property(dot, "modulate:a", 0.0, duration)
		tween.set_parallel(false)
		tween.tween_callback(dot.queue_free)


## Internal node used for projectile drawing.
class _ProjectileDot:
	extends Node2D

	var radius: float = 3.0

	func _draw() -> void:
		draw_circle(Vector2.ZERO, radius, Color(0.9, 0.8, 0.2))


## Expanding ring effect for barge destruction.
class _SplashRing:
	extends Node2D

	var max_radius: float = 20.0
	var current_radius: float = 0.0
	var ring_color: Color = Color(0.3, 0.6, 1.0, 0.7)

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if current_radius > 0.0:
			draw_arc(Vector2.ZERO, current_radius, 0, TAU, 24, ring_color, 2.0)


## Small dot for resource scatter effect.
class _ScatterDot:
	extends Node2D

	func _draw() -> void:
		draw_circle(Vector2.ZERO, 3.0, Color(0.9, 0.8, 0.2, 0.8))

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


## Internal node used for projectile drawing.
class _ProjectileDot:
	extends Node2D

	var radius: float = 3.0

	func _draw() -> void:
		draw_circle(Vector2.ZERO, radius, Color(0.9, 0.8, 0.2))

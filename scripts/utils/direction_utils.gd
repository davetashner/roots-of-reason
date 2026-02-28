class_name DirectionUtils
## Static utility for quantizing a continuous facing vector to one of 8 direction
## strings used by the sprite manifest system.


## Quantizes a facing vector to one of 8 compass direction strings.
## Returns one of: "s", "se", "e", "ne", "n", "nw", "w", "sw".
static func facing_to_direction(facing: Vector2) -> String:
	if facing.is_zero_approx():
		return "s"
	# atan2 gives angle in radians; Godot's y-axis points down.
	# 0 = right (+x), PI/2 = down (+y)
	var angle := fmod(facing.angle() + TAU, TAU)  # Normalize to [0, TAU)
	# Each sector is TAU/8 = 0.7854 rad wide; offset by half a sector so
	# "east" (angle 0) maps to sector center rather than boundary.
	var sector := int(round(angle / (TAU / 8.0))) % 8
	var directions: Array[String] = ["e", "se", "s", "sw", "w", "nw", "n", "ne"]
	return directions[sector]

extends GdUnitTestSuite
## Tests for DirectionUtils.facing_to_direction — vector quantization to 8 compass strings.
##
## Coordinate system: Godot 2D with y-axis pointing DOWN.
##   Vector2(1,  0) → East   (angle = 0°)
##   Vector2(0,  1) → South  (angle = 90°, y-down)
##   Vector2(-1, 0) → West   (angle = 180°)
##   Vector2(0, -1) → North  (angle = 270°)

# --- Zero vector ---


func test_zero_vector_returns_south_default() -> void:
	# Zero vector has no facing; the function must return a safe fallback.
	assert_str(DirectionUtils.facing_to_direction(Vector2.ZERO)).is_equal("s")


# --- Cardinal directions (canonical center angles) ---


func test_east_vector() -> void:
	assert_str(DirectionUtils.facing_to_direction(Vector2(1.0, 0.0))).is_equal("e")


func test_south_vector() -> void:
	# y-axis points down in Godot, so (0,1) is "south" in screen space.
	assert_str(DirectionUtils.facing_to_direction(Vector2(0.0, 1.0))).is_equal("s")


func test_west_vector() -> void:
	assert_str(DirectionUtils.facing_to_direction(Vector2(-1.0, 0.0))).is_equal("w")


func test_north_vector() -> void:
	# Negative y is "up" / north on screen.
	assert_str(DirectionUtils.facing_to_direction(Vector2(0.0, -1.0))).is_equal("n")


# --- Diagonal directions (canonical center angles) ---


func test_southeast_vector() -> void:
	assert_str(DirectionUtils.facing_to_direction(Vector2(1.0, 1.0))).is_equal("se")


func test_southwest_vector() -> void:
	assert_str(DirectionUtils.facing_to_direction(Vector2(-1.0, 1.0))).is_equal("sw")


func test_northwest_vector() -> void:
	assert_str(DirectionUtils.facing_to_direction(Vector2(-1.0, -1.0))).is_equal("nw")


func test_northeast_vector() -> void:
	assert_str(DirectionUtils.facing_to_direction(Vector2(1.0, -1.0))).is_equal("ne")


# --- Magnitude independence (direction should not depend on vector length) ---


func test_long_east_vector() -> void:
	assert_str(DirectionUtils.facing_to_direction(Vector2(100.0, 0.0))).is_equal("e")


func test_short_south_vector() -> void:
	assert_str(DirectionUtils.facing_to_direction(Vector2(0.0, 0.001))).is_equal("s")


# --- Boundary angles (just inside each sector boundary) ---
# Each sector is 45° wide.  The E/SE boundary is at ±22.5° from E (0°).
# GDScript round(0.5) == 0 (banker's rounding), so exactly 22.5° → "e".


func test_boundary_east_side_stays_east() -> void:
	# 22.4° from +x axis, still inside the "east" sector.
	var angle_rad := deg_to_rad(22.4)
	var v := Vector2(cos(angle_rad), sin(angle_rad))
	assert_str(DirectionUtils.facing_to_direction(v)).is_equal("e")


func test_boundary_just_past_east_into_southeast() -> void:
	# 22.6° crosses into the "southeast" sector.
	var angle_rad := deg_to_rad(22.6)
	var v := Vector2(cos(angle_rad), sin(angle_rad))
	assert_str(DirectionUtils.facing_to_direction(v)).is_equal("se")


func test_boundary_southeast_side_stays_southeast() -> void:
	# 67.4° is still inside "southeast" (center at 45°, boundary at 67.5°).
	var angle_rad := deg_to_rad(67.4)
	var v := Vector2(cos(angle_rad), sin(angle_rad))
	assert_str(DirectionUtils.facing_to_direction(v)).is_equal("se")


func test_boundary_just_past_southeast_into_south() -> void:
	# 67.6° crosses into the "south" sector.
	var angle_rad := deg_to_rad(67.6)
	var v := Vector2(cos(angle_rad), sin(angle_rad))
	assert_str(DirectionUtils.facing_to_direction(v)).is_equal("s")


func test_boundary_north_sector_negative_y() -> void:
	# 270° = straight up (negative y). Verify negative-y input maps to "n".
	var angle_rad := deg_to_rad(270.0)
	var v := Vector2(cos(angle_rad), sin(angle_rad))
	assert_str(DirectionUtils.facing_to_direction(v)).is_equal("n")


func test_boundary_just_before_north_into_northwest() -> void:
	# 247.6° is just past the NW/N boundary (at 247.5°) → "n".
	var angle_rad := deg_to_rad(247.6)
	var v := Vector2(cos(angle_rad), sin(angle_rad))
	assert_str(DirectionUtils.facing_to_direction(v)).is_equal("n")


func test_boundary_just_before_north_stays_northwest() -> void:
	# 247.4° is still inside "northwest".
	var angle_rad := deg_to_rad(247.4)
	var v := Vector2(cos(angle_rad), sin(angle_rad))
	assert_str(DirectionUtils.facing_to_direction(v)).is_equal("nw")


# --- Wrap-around: angles near 360° should map back to "east" ---


func test_near_360_wraps_to_east() -> void:
	# 359° is just before a full rotation — should still be "east".
	var angle_rad := deg_to_rad(359.0)
	var v := Vector2(cos(angle_rad), sin(angle_rad))
	assert_str(DirectionUtils.facing_to_direction(v)).is_equal("e")

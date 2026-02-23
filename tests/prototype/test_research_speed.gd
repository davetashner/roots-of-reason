extends GdUnitTestSuite
## Tests for research_speed.gd — pure research speed formula calculations.

const RESEARCH_CONFIG: Dictionary = {
	"age_research_multipliers":
	{
		"0": 1.0,
		"1": 1.0,
		"2": 1.1,
		"3": 1.2,
		"4": 1.5,
		"5": 2.5,
		"6": 5.0,
	},
}


func test_base_speed_no_modifiers() -> void:
	var speed: float = ResearchSpeed.get_effective_speed(1.0, 0, RESEARCH_CONFIG)
	assert_float(speed).is_equal_approx(1.0, 0.001)


func test_age_multiplier_applied() -> void:
	# Age 4 = 1.5x
	var speed: float = ResearchSpeed.get_effective_speed(1.0, 4, RESEARCH_CONFIG)
	assert_float(speed).is_equal_approx(1.5, 0.001)


func test_war_bonus_applied() -> void:
	# 0.10 war bonus = 1.1x
	var speed: float = ResearchSpeed.get_effective_speed(1.0, 0, RESEARCH_CONFIG, 0.10)
	assert_float(speed).is_equal_approx(1.1, 0.001)


func test_tech_bonuses_applied() -> void:
	# 0.25 tech bonus = 1.25x
	var speed: float = ResearchSpeed.get_effective_speed(1.0, 0, RESEARCH_CONFIG, 0.0, 0.25)
	assert_float(speed).is_equal_approx(1.25, 0.001)


func test_all_modifiers_combined() -> void:
	# base=1.0, age 4=1.5x, war=0.10 -> 1.1x, tech=0.25 -> 1.25x
	# expected: 1.0 * 1.5 * 1.25 * 1.1 = 2.0625
	var speed: float = ResearchSpeed.get_effective_speed(1.0, 4, RESEARCH_CONFIG, 0.10, 0.25)
	assert_float(speed).is_equal_approx(2.0625, 0.001)


func test_effective_time_calculation() -> void:
	# base_time = 100, speed = 2.0 -> effective_time = 50
	var time: float = ResearchSpeed.get_effective_time(100.0, 2.0)
	assert_float(time).is_equal_approx(50.0, 0.001)


func test_effective_time_zero_speed() -> void:
	var time: float = ResearchSpeed.get_effective_time(100.0, 0.0)
	assert_float(time).is_equal(INF)


func test_empty_config_defaults_to_one() -> void:
	var speed: float = ResearchSpeed.get_effective_speed(1.0, 0, {})
	assert_float(speed).is_equal_approx(1.0, 0.001)

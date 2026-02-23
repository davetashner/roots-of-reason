class_name ResearchSpeed
extends RefCounted
## Pure calculation helper for research speed formulas.
## No state — just static methods implementing the documented formula:
## effective_speed = base_speed * age_multiplier * (1 + sum(tech_bonuses)) * (1 + war_bonus)


static func get_effective_speed(
	base_speed: float,
	age: int,
	research_config: Dictionary,
	war_bonus: float = 0.0,
	tech_bonuses: float = 0.0,
) -> float:
	## Computes the effective research speed from all multiplier sources.
	var age_str: String = str(age)
	var age_multipliers: Dictionary = research_config.get("age_research_multipliers", {})
	var age_multiplier: float = float(age_multipliers.get(age_str, 1.0))
	return base_speed * age_multiplier * (1.0 + tech_bonuses) * (1.0 + war_bonus)


static func get_effective_time(base_time: float, effective_speed: float) -> float:
	## Computes the effective research time given base time and speed.
	if effective_speed <= 0.0:
		return INF
	return base_time / effective_speed

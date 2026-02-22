extends Node
## Global game state manager.
## Manages game clock, pause state, and game-wide events.

signal game_paused
signal game_resumed
signal game_speed_changed(speed: float)

var is_paused: bool = false
var game_speed: float = 1.0
var current_age: int = 0  # 0=Stone, 1=Bronze, ..., 6=Singularity

const AGE_NAMES: Array[String] = [
	"Stone Age", "Bronze Age", "Iron Age", "Medieval Age",
	"Industrial Age", "Information Age", "Singularity Age"
]

func get_age_name() -> String:
	return AGE_NAMES[current_age]

# Autoload Signal Flow

All autoloads are registered in `project.godot` and live in `scripts/autoloads/`.

## Signal Map

```
┌──────────────────────────────────────────────────────────────────────┐
│                        AUTOLOAD SIGNALS                              │
├──────────────────┬───────────────────────────────────────────────────┤
│ GameManager      │ game_paused()                                    │
│                  │ game_resumed()                                    │
│                  │ game_speed_changed(speed: float)                  │
│                  │ age_advanced(new_age: int)                        │
├──────────────────┼───────────────────────────────────────────────────┤
│ ResourceManager  │ resources_changed(player_id, resource_type,      │
│                  │                   old_amount, new_amount)         │
├──────────────────┼───────────────────────────────────────────────────┤
│ CivBonusManager  │ bonuses_applied(player_id, civ_id)               │
│                  │ bonuses_removed(player_id, civ_id)               │
├──────────────────┼───────────────────────────────────────────────────┤
│ SaveManager      │ (no signals — orchestrates via direct calls)     │
├──────────────────┼───────────────────────────────────────────────────┤
│ DataLoader       │ (no signals — passive cache/lookup)              │
└──────────────────┴───────────────────────────────────────────────────┘
```

## Autoload Responsibilities

### GameManager
**State:** `is_paused`, `game_speed`, `game_time`, `current_age` (0-6), `player_civilizations`

- Controls game clock (pause/resume/speed)
- Tracks age progression (Stone → Singularity)
- Maps player IDs to civilization IDs
- `get_game_delta(delta)` — returns delta adjusted for pause/speed

### ResourceManager
**State:** per-player stockpiles for FOOD, WOOD, STONE, GOLD, KNOWLEDGE

- `add_resource()` — applies gather multiplier and corruption rate
- `can_afford() / spend()` — cost validation and deduction
- `init_player()` — sets starting resources per difficulty
- Corruption reduces non-knowledge resource gains

### DataLoader
**State:** JSON cache (path → parsed data)

- `load_json(path)` — cached file loading
- `get_unit_stats()`, `get_building_stats()`, `get_tech_data()`, `get_civ_data()`
- `get_settings(name)` — loads from `data/settings/`
- `get_ages_data()`, `get_all_civ_ids()`

### CivBonusManager
**State:** per-player active civ ID and applied bonuses

- `apply_civ_bonuses(player_id, civ_id)` — applies stat modifiers
- `get_bonus_value()`, `get_build_speed_multiplier()`
- `get_resolved_building_id()` / `get_resolved_unit_id()` — civ-unique replacements
- `apply_bonus_to_unit(unit_stats, unit_id, player_id)` — injects modifiers

### SaveManager
- `save_game(slot)` — writes to `user://saves/slot_N.json` (3 max)
- `load_game(slot)` / `apply_loaded_state(data)`
- Calls `save_state()`/`load_state()` on GameManager, ResourceManager, CivBonusManager

## Signal Flow: Resource Updates

```
Unit.gather()
    │
    ▼
ResourceManager.add_resource(player_id, type, amount)
    │  applies gather_multiplier, corruption_rate
    ▼
resources_changed(player_id, type, old, new)
    │
    ├──▶ ResourceBar (UI update)
    ├──▶ AIEconomy (rebalance villagers)
    └──▶ ProductionQueue (unpause if can afford)
```

## Signal Flow: Age Advancement

```
TechManager completes age-up research
    │
    ▼
GameManager.advance_age(new_age)
    │
    ▼
age_advanced(new_age)
    │
    ├──▶ TechManager (unlock age-gated techs)
    ├──▶ VictoryManager (check Singularity victory)
    ├──▶ HistoricalEventManager (trigger plague/renaissance)
    └──▶ AITech (adjust research priorities)
```

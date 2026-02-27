# State Machine Patterns

Units and buildings use enum-based state machines with transitions driven by commands and game events.

## Unit Gather State Machine

Located in `scripts/prototype/prototype_unit.gd`

**Enum:** `GatherState { NONE, MOVING_TO_RESOURCE, GATHERING, MOVING_TO_DROP_OFF, DEPOSITING }`

**Flow:**

    NONE --> (right-click resource) --> MOVING_TO_RESOURCE
    MOVING_TO_RESOURCE --> (reach resource) --> GATHERING
    GATHERING --> (carry full) --> MOVING_TO_DROP_OFF
    MOVING_TO_DROP_OFF --> (reach building) --> DEPOSITING
    DEPOSITING --> (deposit complete) --> NONE  (loops back)

**Key state:**
- `_gather_target` — resource node being gathered
- `_gather_type` — resource type (food, wood, etc.)
- `_carried_amount` / `_carry_capacity` — how much the unit is carrying
- `_gather_accumulator` — per-tick gather progress

**Transitions:**
- `gather_from(resource, type)` sets MOVING_TO_RESOURCE
- Reach resource sets GATHERING (accumulates per tick)
- Carry full sets MOVING_TO_DROP_OFF (finds nearest drop-off building)
- Reach building sets DEPOSITING, calls ResourceManager.add_resource(), then resets to NONE

## Unit Combat State Machine

Located in `scripts/prototype/prototype_unit.gd`

**Enum:** `CombatState { NONE, PURSUING, ATTACKING, ATTACK_MOVING, PATROLLING }`

**Flow:**

    NONE --> (attack command) --> PURSUING
    PURSUING --> (in range) --> ATTACKING
    ATTACKING --> (target dies + has destination) --> ATTACK_MOVING
    ATTACKING --> (target dies, no destination) --> NONE

    NONE --> (attack-move command) --> ATTACK_MOVING
    ATTACK_MOVING --> (enemy spotted) --> PURSUING

    NONE --> (patrol command) --> PATROLLING
    PATROLLING --> (ping-pong between waypoints A and B)

**Key state:**
- `_combat_target` — hostile being attacked
- `_stance` — AGGRESSIVE (chase far), DEFENSIVE (chase near), STAND_GROUND (no chase)
- `_attack_cooldown` — time until next attack
- `_scan_timer` — periodic enemy scanning interval
- `_attack_move_destination` — for attack-move commands
- `_patrol_point_a / _b` — for patrol commands
- `_formation_speed_override` — caps speed when in formation

**Stance behavior:**
- **Aggressive:** pursue enemies at max scan range
- **Defensive:** pursue only nearby enemies, return to position
- **Stand Ground:** attack only targets in range, never move

## Building Construction State

Located in `scripts/prototype/prototype_building.gd`

**Flow:**

    under_construction (translucent)
      --> (build_progress reaches 1.0) --> INTACT
    INTACT --> (HP drops) --> DAMAGED / CRITICAL (color-coded visual)
    DAMAGED / CRITICAL --> (hp <= 0) --> RUINS (decays into background)

**Key state:**
- `under_construction: bool` — translucent, being built by villagers
- `build_progress: float` (0.0-1.0) — construction progress
- `hp / max_hp` — health; visual changes at damage thresholds
- `_is_ruins: bool` — destroyed building decays into background

## AI Tick-Based State

AI systems (`scripts/ai/`) use tick-based evaluation rather than continuous state machines:

    IDLE --> (tick_interval elapses) --> EVALUATE (check needs) --> ONE ACTION (build/train/research) --> IDLE

- **AIEconomy:** 2-second tick — evaluate resource needs, execute one spending action
- **AIMilitary:** periodic scan — check for enemies, form attack groups
- **AITech:** research queue management — pick next tech by personality priority
- **AISingularity:** endgame strategy — AGI Core construction, tech chain monitoring

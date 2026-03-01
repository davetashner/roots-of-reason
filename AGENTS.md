# Agent Instructions — Roots of Reason

A civilization RTS inspired by Age of Empires where the endgame is achieving artificial general intelligence. Built with Godot 4 + GDScript, 2D isometric, single-player vs AI.

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.
See `CLAUDE.md` for beads commands, project structure, quality gates, and the standard ship cycle.

---

## System Architecture

Detailed architecture documentation lives in `docs/architecture/`:

| Document | Contents |
|----------|----------|
| [autoload_signals.md](docs/architecture/autoload_signals.md) | Autoload signal flow, responsibilities, and key signal chains |
| [scene_tree.md](docs/architecture/scene_tree.md) | Scene tree conventions for units, buildings, and map nodes |
| [state_machines.md](docs/architecture/state_machines.md) | Unit gather/combat state machines, building construction states |
| [system_relationships.md](docs/architecture/system_relationships.md) | How major systems connect: resource flow, tech effects, combat chain |

---

## Architecture Decisions (ADRs)

These are locked decisions. Do not deviate without creating a new ADR to supersede.

### ADR-001: Game Engine — Godot 4
- **GDScript** is the primary language for all gameplay code
- C# reserved only for proven hot paths after profiling (not speculative optimization)
- Target Godot version: pin to a specific stable release (e.g., 4.3-stable)

### ADR-002: Visual Style — 2D Isometric
- **128x64px diamond tiles** (2:1 ratio)
- Sprite-based units and buildings on isometric tilemap
- 8-direction sprites for all units (N, NE, E, SE, S, SW, W, NW)
- Use Godot's TileMap with terrain autotiling

### ADR-003: Single-player First
- AI opponents only — no networking code in the codebase
- Do not design systems with multiplayer "just in case" — keep it simple
- Multiplayer is a future expansion, not a hidden requirement

### ADR-004: Historical Civilizations — 3 at launch
| Civ | Playstyle | Bonus | Unique Building | Unique Unit |
|-----|-----------|-------|-----------------|-------------|
| Mesopotamia | Builder/economy | +15% build speed | Ziggurat (+50% Knowledge) | Immortal Guard (heavy inf, self-heal) |
| Rome | Military | +10% military attack & defense | Colosseum (morale aura) | Legionnaire (shield wall ability) |
| Polynesia | Naval | +20% naval speed | Marae (reveals coastline) | War Canoe (fast, carries 5 units) |

### ADR-005: Age Progression — 7 Ages
Stone → Bronze → Iron → Medieval → Industrial → Information → Singularity

- Each age unlocks buildings, units, and technologies
- Advancing requires resource cost + prerequisite buildings
- **Singularity Age** win chain: GPU Foundry → Transformer Lab → AGI Core

### ADR-006 & ADR-007
Project structure and quality pipeline are documented in `CLAUDE.md`.

### ADR-008: Art Pipeline — Phased Production
- **Phase 1 (prototype):** Colored geometric shapes. Diamonds for tiles, circles for units, rectangles for buildings. Zero art skill needed. Game is always playable.
- **Phase 2 (alpha):** AI-generated base sprites + manual cleanup in Aseprite. Fastest path to "looks like a game."
- **Phase 3 (polish):** Hand-pixel or commission professional sprites for hero units, unique buildings, UI.

**Sprite scale contract (do not violate):**
| Entity | Size | Footprint |
|--------|------|-----------|
| Villager | ~48px tall | 1 tile |
| Infantry | ~52-56px tall | 1 tile |
| Cavalry | ~64px tall | 1 tile |
| Building 1x1 | 128x128px max | 1 tile |
| Building 2x2 | 256x192px max | 4 tiles |
| Building 3x3 | 384x256px max | 9 tiles |
| Trees/resources | ~64-80px tall | 1 tile |

**Animation budget per unit (AUTHORING cost, not output):**
- Idle: 4 keyframes → rendered to 32 output frames (8 cameras)
- Walk: 8 keyframes → 64 output frames
- Attack: 6 keyframes → 48 output frames
- Death: 6 keyframes → 6 output frames (1 dir, mirrored)
- Military: ~24 keyframes authored → ~150 output frames (6x multiplication)
- Villager: ~48 keyframes authored → ~230 output frames

**3D-to-2D Render Pipeline (how sprites are actually made):**
This is the core production method, modeled after how Age of Empires was made.
1. Model once in Blender (low-poly, stylized)
2. Rig + animate once (one direction only)
3. Render rig (`blender/render_rig.blend`): 8 cameras at 45° intervals, isometric angle, ortho projection
4. Batch render script (`blender/batch_render.py`): renders all anims from all cameras headless
5. Spritesheet packer (`tools/spritesheet_packer.py`): packs PNGs → spritesheets + Godot SpriteFrames
6. One animation authored = 8 directions output. One model = all player colors via shader.

**Three production phases:**
- Phase 1: Fully procedural (Python generators, zero manual art, geometric shapes)
- Phase 2: Blender 3D → 2D pipeline (model once, render 8 dirs automatically)
- Phase 3: AI textures on 3D models + hand polish on hero units

**Player colors:** Runtime shader recoloring — NOT baked per-player sprites.
- Sprites rendered with magenta (#FF00FF) mask region
- Godot shader swaps mask to player color preserving luminance
- ONE sprite set serves all players
- Colors: Blue (#2E86DE), Red (#E74C3C), Teal (#1ABC9C), Orange (#F39C12)

**Asset naming:** snake_case, lowercase.
- Units: `{unit_name}_{animation}_{direction}_{frame}.png`
- Buildings: `{building_name}_{state}.png`
- Tiles: `{terrain}_{variant}_{index}.png`

**Asset toolchain:**
- `tools/generate_tiles.py` — procedural Phase 1 tileset
- `tools/generate_unit_sprites.py` — procedural Phase 1 unit sprites
- `tools/generate_building_sprites.py` — procedural Phase 1 building sprites
- `tools/spritesheet_packer.py` — pack PNGs → spritesheets + Godot resources
- `tools/validate_sprites.py` — CI validation (dimensions, frame counts, naming, masks)
- `tools/asset_pipeline.py` — orchestrator (runs full pipeline in one command)
- `blender/render_rig.blend` — 8-camera isometric render template
- `blender/batch_render.py` — headless Blender batch renderer
- `tools/asset_config.json` — single source of truth for all asset definitions

**Color palettes:**
- Player colors: Blue (#2E86DE), Red (#E74C3C), Teal (#1ABC9C), Orange (#F39C12)
- Stone/Bronze: earthy browns, muted greens, terracotta
- Iron/Medieval: deep greens, grays, steel blue
- Industrial: brick reds, iron gray, amber
- Information/Singularity: steel blue, white, neon cyan, holographic

---

## Core Game Systems

### Resources
5 types: **Food, Wood, Stone, Gold, Knowledge**
- Knowledge is unique — generated by Libraries, Ziggurats, and research, not gathered from the map
- All resource costs, gather rates, and building costs are **data-driven** (loaded from JSON in `data/`), never hardcoded in scripts

### ADR-009: River Resource Transport
Rivers are economic infrastructure, not just terrain. Key rules:
- **Rivers have flow direction** — generated from mountains downhill to ocean/lake
- **River Dock** (1x1, 100 Wood, Bronze Age): drop-off building placed adjacent to river
- Resources deposited at upstream River Dock are **auto-shipped downstream via barges** at 3x villager speed
- Barges are **visible, attackable entities** (15 HP, 0 defense) — raiding barges destroys carried resources
- River tiles are crossable by land units at **50% movement speed** (fording)
- Flow direction matters: rivers flowing TOWARD your base are valuable; flowing AWAY gives no transport benefit
- River Dock placement is a key strategic decision: build upstream near mines
- **River overlay** (toggle with R): shows flow direction colored green (toward base) / red (away)

### ADR-010: Wolf Domestication
Wolves spawn as hostile Gaia fauna near forests (3-5 packs of 2-3 wolves per map). Players choose: hunt them for 50 Food, or feed them to domesticate.
- **Feed command:** Shift+right-click wolf with villager. Costs 25 Food per feeding, 3 feedings to domesticate (75 Food total).
- **Contested:** If another player feeds the same wolf, progress resets to them.
- **Progress decays** at 10%/minute if not maintained — commit or lose your investment.
- **Dog companion** (0 pop cost, not trainable): HP 25, Speed 2.5, LOS 6
  - **Hunting assist:** +25% gather rate for nearby hunting villagers, deer flee less
  - **Danger alert:** 10-tile sense radius, bark + minimap ping + 10% speed boost to nearby friendlies for 5s
  - **Town patrol:** +2 LOS to buildings near Town Center per dog (max +4 with 2 dogs)
  - Dogs flee from combat, can be garrisoned in Town Center for protection

### Combat
Rock-paper-scissors: Infantry → Archers → Cavalry → Infantry. Siege → Buildings.
- Buildings take 80% reduced damage from non-siege units
- Damage formula: `attacker.attack - defender.defense` (minimum 1)

### ADR-011: Knowledge Burning — Tech Regression on City Destruction
When an enemy destroys a Town Center, the defender **loses their most recently researched tech**.
- Triggers on EVERY TC destruction by an enemy (not self-demolish, not Gaia)
- **Age advancements cannot be lost** — only individual techs within ages
- Lost tech bonuses are **immediately reverted** (unit stats, economic multipliers, unlocks)
- Existing units/buildings from lost unlocks **remain** but no new ones can be produced until re-researched
- Re-research at **full cost**, same prerequisites
- **Singularity interaction:** Losing Transformer Architecture PAUSES AGI Core construction (devastating but recoverable). Researching Singularity techs triggers a public alert to all players.
- **Strategic research order:** Research high-value techs early to push them deeper in the history stack (less likely to be the "most recent" lost)
- Visual: burning scroll particles, screen flash, distinctive audio chime
- Settings tunable via `data/settings/knowledge_burning.json`

### ADR-012: Error Handling Conventions
Standardized error handling across all GDScript code. Follow these patterns exactly.

**Recoverable errors — `push_warning()` + fallback value:**
Use when the game can continue with a sensible default. Return an empty container or default value.
```gdscript
# WRONG — silent failure, caller gets null and crashes later
func get_unit_stats(unit_name: String) -> Dictionary:
	var data = load_json("res://data/units/%s.json" % unit_name)
	return data

# RIGHT — warn and return empty dict so callers don't null-ref
func get_unit_stats(unit_name: String) -> Dictionary:
	var data: Variant = load_json("res://data/units/%s.json" % unit_name)
	if data == null:
		push_warning("DataLoader: No stats for unit '%s', returning defaults" % unit_name)
		return {}
	return data
```

**Unrecoverable errors — `push_error()` + `assert()` in debug:**
Use for logic bugs and invariant violations that should never happen in correct code.
```gdscript
# WRONG — silently accepts invalid state, bug hides until later
func advance_age(player_id: int) -> void:
	current_age = current_age + 1

# RIGHT — catch the bug immediately in debug, log in release
func advance_age(player_id: int) -> void:
	assert(current_age < AGE_NAMES.size() - 1, "Cannot advance past final age")
	if current_age >= AGE_NAMES.size() - 1:
		push_error("GameManager: Tried to advance past Singularity Age for player %d" % player_id)
		return
	current_age += 1
```

**Data validation — validate at load time, trust at runtime:**
- Validate JSON structure and required fields when data is first loaded (in `DataLoader` or system `_ready()`)
- After validation passes, trust the data at runtime — do not re-check on every access
- Use `push_error()` for malformed data files (they indicate a build/data bug)

**Missing data files — graceful degradation:**
- Return empty `Dictionary` or `Array` so callers can use `.is_empty()` checks
- Use `push_warning()` — missing files are recoverable (the system works with defaults)
- Never crash on missing optional data; use `push_error()` only for files that must exist (e.g., core settings)

**Signal-based error propagation for gameplay events:**
- Use signals for expected gameplay failures: `path_not_found`, `resource_depleted`, `build_failed`, `train_blocked`
- Do NOT use `push_warning`/`push_error` for normal gameplay situations (e.g., player can't afford a unit)
- Signals let the UI and AI react to failures without coupling systems together

**Logging severity levels:**
| Level | Function | When to use |
|-------|----------|-------------|
| `push_warning()` | Recoverable issues | Missing optional data, config fallback, deprecated usage |
| `push_error()` | Bugs / invariant violations | Malformed data, impossible state, programmer error |
| `assert()` | Debug-only invariants | Pre/postconditions, type checks, range checks (stripped in release) |
| `print()` | Never in production code | Use only in temporary debugging; remove before commit |

**Rules:**
- Prefix all warning/error messages with the class name: `"DataLoader: ..."`, `"GameManager: ..."`
- Do not catch errors that indicate code bugs — let `assert()` crash in debug so the bug is found immediately
- Do not use `push_warning()`/`push_error()` for normal gameplay flow (player out of resources, path blocked, etc.) — use signals instead
- Every `push_warning()` or `push_error()` call must include enough context to diagnose the issue (what happened, what input caused it)

### ADR-013: Research Acceleration
Research speed scales by age, with war bonuses and tech bonuses stacking multiplicatively.
- **Age multipliers:** 1.0 / 1.0 / 1.1 / 1.2 / 1.5 / 2.5 / 5.0 (Stone → Singularity)
- **War bonus by age:** +5% / +8% / +10% / +15% / +30% / +40% / +25% — activates when at least 1 military unit is in combat, lingers 30 seconds
- **Military tech spillovers:** defined per-tech in `data/tech/tech_tree.json` (e.g., Rifling grants Mining +15%)
- **Formula:** `effective_speed = base_speed * age_multiplier * (1 + sum(tech_bonuses)) * (1 + war_bonus)`
- Settings in `data/settings/research.json`

### ADR-014: Pandemic & Corruption Systems
Two early-game friction mechanics keep early ages from being pure economy sims. Both are data-driven from JSON settings.
- **Corruption:** Persistent scaling with empire size, reducing resource income (except Knowledge)
  - Active ages 1–4, starts above 8 buildings, 1.5%/building, caps at 30%
  - Counters: Code of Laws (-30%), Banking (-25%), Civil Service (eliminates)
  - Settings in `data/settings/corruption.json`
- **Pandemics:** Random events based on population density
  - Active ages 0–3, checked every 2 minutes, base 5% chance (+2% per villager above 15)
  - Effects: -30% work rate, 5% villager death chance, 45 second duration
  - Counters: Herbalism (-25% severity), Sanitation (-50% severity), Vaccines (full immunity)
  - Settings in `data/settings/pandemics.json`

### ADR-015: Pirate Spawning System
Gaia-controlled hostile naval units that spawn after any player researches Compass (deep ocean navigation).
- Spawn every 90 seconds from ocean edges, max 8 active pirates
- Carry 30–120 Gold bounty (drops on death, scaled by age)
- Target soft naval targets (fishing boats, trade barges, transport ships)
- Avoid military vessels and garrisoned docks
- Spawn rate decreases in later ages (1.0x Medieval → 0.2x Singularity)
- Settings in `data/settings/pirates.json`

### ADR-016: War Survival — Medical Tech Chain
The medical tech chain (Herbalism → Sanitation → Pasteurization → Vaccines → Antibiotics) creates an escalating war survival advantage. Each tech makes armies more durable, sustaining the war research bonus longer, accelerating tech progression.
- **Pasteurization:** +1 HP/s idle regen (after 5s idle), camp disease immunity
- **Vaccines:** +15% max HP for military units, pandemic immunity
- **Antibiotics:** 25% chance to stabilize at 1 HP instead of dying (60s cooldown per unit), villager pandemic death immunity
- **Compound effect:** ~60% more effective research output during wartime for medically advanced civs
- **Balance levers:** Stabilize chance (25%) and cooldown (60s) are tunable in `data/settings/war_survival.json`

### ADR-017: Historical Events System
Named scripted events that fire based on age progression or tech milestones, creating memorable turning points.
- **Black Plague:** Guaranteed mega-pandemic in Medieval Age affecting all players. -50% work rate, 15% villager death, 90s duration. Mitigated by medical techs (Herbalism, Sanitation), immune with Vaccines. Aftermath grants labor scarcity (+15% work rate) and innovation pressure (+20% research speed) for 2 minutes.
- **Renaissance:** Per-player golden age triggered by researching Printing Press + Banking + Guilds. +35% research speed, +50% Knowledge gen, +20% gold income for 3 minutes. Bonus for Libraries (3+) and Markets (2+).
- **Phoenix interaction:** Renaissance within 120s of Black Plague survival gives 1.5x bonus multiplier.
- Settings in `data/settings/historical_events.json`

### ADR-018: Pathfinding — AStarGrid2D
Godot's built-in `AStarGrid2D` is the pathfinding backend. No custom A* or NavMesh.
- **Grid size** matches the tilemap — one cell per isometric tile
- **Diagonal movement** enabled (8-directional), diagonal cost = `sqrt(2)`
- **Terrain costs** loaded from `data/settings/terrain.json`:
  - Grass/dirt: 1.0, Forest: 2.0, Shallows/ford: 3.0, Deep water: impassable (land), River: 0.5x speed (see ADR-009)
  - Buildings and resource nodes mark their footprint cells as **solid** (impassable)
- **Unit-type overrides:** Naval units invert land/water passability. Siege units treat forest as impassable.
- **Partial recalculation:** When buildings are placed/destroyed, update only affected cells — never rebuild the full grid
- **Path caching:** No cache. `AStarGrid2D` is fast enough for single-player scale (<200x200 maps). Re-evaluate if profiling shows otherwise.
- **Flow fields:** Not used. AStarGrid2D handles the expected unit counts (<200 simultaneous pathfinding requests). Revisit only if profiling proves a bottleneck.
- Settings in `data/settings/terrain.json`

### ADR-019: Population Cap System
Population limits how many units a player can field. Cap is raised by buildings, not age advancement.
- **Starting cap:** 5 (from initial Town Center's `population_bonus`)
- **Cap sources:** Each building defines a `population_bonus` field in its JSON (0 for most buildings). Key providers:
  - Town Center: +5
  - House (1x1, 25 Wood, Stone Age): +5, max 20 Houses
  - Castle (3x3, Medieval): +10
- **Hard cap:** 200 — no combination of buildings can exceed this
- **Pop cost per unit** defined in each unit's JSON (`population_cost` field — already exists on Villager)
- **At cap:** Training queues pause with "Population limit reached" message. Queued units resume automatically when pop frees up (unit dies or building grants more cap).
- **Garrison interaction:** Garrisoned units still count toward pop cap (no exploit)
- **Display:** HUD shows `current_pop / pop_cap` (e.g., "47/100")
- Settings in `data/settings/population.json`

### ADR-020: Playable Milestones
Four milestones define the path from prototype to content-complete. Each milestone is a playable game — not a feature checklist.

**Milestone 1 — "Gather & Build" (First Playable)**
- Isometric camera (pan, zoom, edge-scroll)
- Procedural map with terrain tiles and resource nodes (trees, berries, stone, gold)
- Villager: select, move (A* pathfinding), gather resources, return to Town Center
- Town Center: train villagers, resource drop-off
- House: build to raise pop cap
- HUD: resource counts, pop count, minimap placeholder
- One civilization (Mesopotamia), no enemy, no combat
- **Exit criteria:** A player can gather all 4 physical resources, build houses, and train villagers until pop cap

**Milestone 2 — "Fight"**
- 3 military units (Infantry, Archer, Cavalry) with rock-paper-scissors combat
- Barracks production building
- Unit selection: box-select, control groups, right-click commands (move, attack, gather, build)
- Basic AI opponent: builds economy, trains military, attacks
- Fog of war
- Win condition: Conquest (destroy enemy Town Center)
- **Exit criteria:** A full game can be played and won/lost against AI

**Milestone 3 — "Advance"**
- Full 7-age progression with tech tree (64 techs)
- All 3 civilizations with unique units/buildings
- All building types, all unit types (including Siege, Naval)
- Resource transport (rivers, barges)
- Knowledge generation and research queue
- Advanced mechanics: corruption, pandemics, Knowledge Burning, wolf domestication
- Victory conditions: Conquest, Singularity, Wonder
- **Exit criteria:** A full game from Stone Age to Singularity is winnable via all 3 victory conditions

**Milestone 4 — "Ship It"**
- AI difficulty levels (Easy, Medium, Hard)
- Historical events (Black Plague, Renaissance)
- Pirates, medical tech chain, research acceleration
- Save/load game state
- Audio, polished UI, Phase 2+ art
- Performance within budgets, export builds verified
- **Exit criteria:** A stranger can download, play a full game, and have fun

### Victory Conditions
1. **Conquest:** Destroy all enemy Town Centers
2. **Singularity:** First to complete AGI Core (requires full tech tree)
3. **Wonder:** Build Wonder, defend for 10-minute countdown

### ADR-021: Tech Tree Historical Expansion — Impact Analysis

**Status:** Proposed · **Bead:** roots-of-reason-02j · **Epic:** roots-of-reason-fxt.11

**Context:** The tech tree has 64 technologies across 7 ages but has significant historical gaps — no Agriculture, no Wheel, no Aviation, thin governance line, and missing foundational innovations that shaped civilization. Players who enjoy learning history through tech trees (a core audience for the genre) will notice these absences. The Singularity endgame is well-designed, but earlier ages feel rushed (Stone Age has only 4 techs for the longest period in human history).

**Decision:** Add 13 historically significant technologies across all ages, expanding the tree from 64 to 77 techs. Each addition fills a specific historical gap, creates more meaningful prerequisite chains, and deepens strategic decision-making.

**New Technologies:**

| Tech | Age | Prerequisites | Key Effects | Historical Rationale |
|------|-----|---------------|-------------|---------------------|
| Agriculture | 0 (Stone) | Stone Tools | Unlock Farm, +food gather | Neolithic Revolution (~10,000 BCE) — most important tech in human history, enabled permanent settlement |
| The Wheel | 1 (Bronze) | Stone Tools | +movement speed | ~3500 BCE — foundational for transport, pottery, and all machinery |
| Road Building | 2 (Iron) | Engineering | +movement on owned territory, +trade income | Roman roads — as strategically important as legions |
| Astronomy | 2 (Iron) | Mathematics | +naval LOS | Celestial navigation predates compass by millennia; bridges science chain |
| Mechanical Power | 3 (Medieval) | Engineering | +25% farm processing, +15% wood gather | Wind/water mills — proto-Industrial Revolution |
| Optics | 3 (Medieval) | Mathematics | +ranged LOS, +ranged accuracy | Spectacles → telescopes → microscopes; connects to lithography/semiconductor chain |
| Telegraph | 4 (Industrial) | Electricity | +diplomacy, espionage | Promoted from building unlock; 1837 "Victorian Internet" deserves its own node |
| Aviation | 4 (Industrial) | Steam Power, Ballistics | Unlock air recon, +trade range | Powered flight (1903) — major gap, tree jumps from ballistics to rocketry |
| Democracy | 4 (Industrial) | Code of Laws, Printing Press | -corruption, +villager efficiency | Deepens thin governance line; enables diplomatic playstyles |
| Trade Routes | 3–4 (Medieval/Industrial) | Guilds, Compass | +trade income, unlock trade caravan | Silk Road, maritime trade — as transformative as military tech |
| Spaceflight | 5 (Information) | Rocketry | Prestige, +research speed | Space Race drove miniaturization; parallel to military Guided Missiles |
| Renewable Energy | 5 (Information) | Electricity, Chemistry | +sustainable resource gen | AGI needs power; alternative to Nuclear Fission |
| Brain-Computer Interface | 6 (Singularity) | Neural Networks, Antibiotics | +research speed | Emerging parallel path to AGI; strategic fork vs pure software approach |

**Prerequisite Chain Changes:**
- Irrigation now requires Agriculture (not just Writing)
- Compass now requires Astronomy + Trireme (replaces Mathematics)
- Steam Power now requires Mechanical Power (not just Engineering)
- Rocketry now requires Aviation + Chemistry (replaces Ballistics + Chemistry)
- Railroad now requires Road Building + Steam Power
- Internet now requires Telegraph + Semiconductor Fab (replaces Computing Theory + Semiconductor Fab)
- Semiconductor Fab gains optional Optics prerequisite (lithography connection)

**Impact Assessment:**

1. **Research pacing:** 13 more techs at ~60-85s each adds ~15-18 minutes to a full-tree run. The age multipliers (2.5x–5.0x in late game) absorb this well. Earlier ages gain depth without dragging — Stone Age goes from 4→5 techs, still the quickest age.

2. **Balance:** New techs add strategic forks (Renewable Energy vs Nuclear Fission, BCI vs Transformer Architecture) rather than just lengthening the critical path. Players must choose branches, not just research everything.

3. **AI personalities:** All three AI personalities (Balanced, Economic, Aggressive) need updated priority orderings. Agriculture and Wheel are universal early picks. Democracy appeals to Economic AI. Aviation appeals to Aggressive AI. Trade Routes is an Economic priority.

4. **Knowledge Burning:** More techs = deeper research history stacks = more buffer before losing critical techs. This is a net positive — currently the late game has very thin stacks in some ages.

5. **Singularity Chain:** BCI creates an optional fork but does NOT add to the critical path length. Alignment Research still requires Transformer Architecture. BCI is an accelerator, not a gate.

6. **JSON data changes:** `tech_tree.json` (+13 entries), `ages.json` (no change — ages stay at 7), `research.json` (no change), `ai/tech_config.json` (update all 3 personality orderings).

7. **Milestone impact:** Milestone 3 description updates from "64 techs" to "77 techs." No milestone gating changes.

8. **Cost scaling:** New techs follow existing cost curves per age. Total resources required for full tree increases ~20%, requiring more economic investment — this is desirable, as it rewards players who balance military and economy.

**Alternatives Considered:**
- **Add fewer (top 5 only):** Lower risk but leaves gaps in aviation, governance, and trade that genre veterans will notice.
- **Add more (20+):** Diminishing returns. Cultural/artistic techs (Theatre, Cinema, Music) are interesting but don't connect to the AGI endgame mechanically.
- **Reorganize existing techs instead:** Some techs could be renamed or combined, but the existing 64 are individually well-designed. Adding is better than replacing.

**Risks:**
- UI clutter in tech tree viewer (fxt.4) — mitigated by age-column layout which scales horizontally
- Longer playthroughs — mitigated by age research multipliers and the fact that most games end before full tree completion
- AI research path tuning — requires playtesting each personality with the expanded tree

**Consequences:**
- Tech tree grows from 64→77 (20% increase)
- Average game length increases ~10-15% (offset by strategic depth gains)
- AI tech config needs retuning for all 3 personalities
- Tech tree UI (fxt.4) must handle wider columns gracefully
- All tests referencing tech counts need updating

### ADR-022: Civilization Expansion — From 3 to 7 Civilizations

**Status:** Accepted · **Bead:** roots-of-reason-kif

- 4 new civs: Egypt (wonder/defense), China (research), Vikings (raid/hybrid), Maya (knowledge economy)
- Each civ occupies exactly one primary + one secondary playstyle niche
- No civ gets bonuses in more than 2 categories
- Every unique unit must lose to at least one standard counter unit
- All balance tunable via JSON — no hardcoded stats
- Balance constraint: no civ >55% win rate vs any other at equal skill

### ADR-023: Debug Console & Integration Test Architecture

- In-game debug console (backtick toggle) + DebugAPI for automated tests
- Shared DebugCommandRegistry backend — commands registered as {name, args_spec, handler, help_text}
- Command categories: Spawn, Control, Economy, Tech, Vision, Time, Overlays, Query
- All mutations go through existing system APIs (GameManager, ResourceManager, etc.)
- Stripped from release builds via OS.is_debug_build() guards
- DebugServer HTTP API extended with write endpoints delegating to DebugCommandRegistry

---

## Coding Standards & Workflow

See `CLAUDE.md` for data-driven conventions, serialization requirements, test standards, quality gates, and the standard feature ship cycle.


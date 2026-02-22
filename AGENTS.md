# Agent Instructions — Roots of Reason

A civilization RTS inspired by Age of Empires where the endgame is achieving artificial general intelligence. Built with Godot 4 + GDScript, 2D isometric, single-player vs AI.

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git
```

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

### ADR-006: Project Structure
```
project/
├── scenes/          # Game scenes organized by feature
├── scripts/         # GDScript files (mirrors scenes/ structure)
├── autoloads/       # Global singletons (GameManager, ResourceManager, etc.)
├── data/            # JSON data files (tech trees, unit stats, civ data)
├── assets/          # Art, audio, fonts (see ADR-008 for full layout)
├── addons/          # Godot addons (GdUnit4, etc.)
└── tests/           # Test files (mirrors scripts/ structure)
```

### ADR-007: Quality Pipeline — 90% Coverage, Zero Warnings
- **GdUnit4** for all tests (unit + integration)
- **90% line coverage** enforced in CI on all gameplay scripts
- **gdtoolkit** (gdlint + gdformat) — zero warnings policy
- **Headless scene smoke tests** — every .tscn must load without errors
- **Playability integration tests** — automated gameplay scenarios run headless
- **Screenshot regression** — UI scenes compared against baseline images
- **Performance budgets** — frame time benchmarks, CI fails on >15% regression
- **Export validation** — macOS + Windows builds verified to launch
- Every PR must pass all gates before merge. No exceptions.

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

---

## Coding Standards

### All gameplay numbers must be data-driven
```gdscript
# WRONG — hardcoded stats
var hp = 100
var attack = 15

# RIGHT — loaded from data
var stats = DataLoader.get_unit_stats("infantry")
var hp = stats.hp
var attack = stats.attack
```

### All game state must be serializable
Every system that holds game state must implement save/load. Design for serialization from day one — do not bolt it on later.

### Test every system
- Unit tests for pure logic (damage calculation, resource math, pathfinding)
- Integration tests for gameplay flows (gather → return → deposit)
- Scene smoke tests for all .tscn files
- Target: 90% line coverage, enforced in CI

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds


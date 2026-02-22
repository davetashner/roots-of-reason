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


<p align="center">
  <img src="assets/branding/hero.png" alt="Roots of Reason" width="480">
</p>

# Roots of Reason

A civilization RTS inspired by Age of Empires where the endgame is achieving artificial general intelligence. Built with Godot 4.6 + GDScript, 2D isometric, single-player vs AI.

> Guide your civilization from the Stone Age through seven ages of discovery — and race to build AGI before your rivals do.

## Features

### Ages and Technology
- **7 ages of progression** — Stone, Bronze, Iron, Medieval, Industrial, Information, Singularity
- **92 technologies** spanning the full arc of human knowledge, viewable in a scrollable tech tree UI
- **Singularity Age endgame** — research GPU Foundry, Transformer Lab, and AGI Core to win
- **Tech regression** — lose your most recent tech when a Town Center falls; Singularity-age techs have special regression interactions
- **Unique civ techs** — Mesopotamia gets Cuneiform Writing and Hanging Gardens Legacy

### Combat
- **Rock-paper-scissors unit types** — infantry, archers, cavalry, siege, and naval units
- **Armor effectiveness matrix** — damage modifiers based on armor type vs. attack type
- **Formation movement** — line, box, and staggered formations
- **Garrison system** — shelter units inside buildings for protection
- **Knowledge Burning** — when a Town Center falls, the attacker triggers a dramatic knowledge-burning VFX and the defender loses tech
- **War survival** — medical tech chain (Triage, Field Surgery, Combat Medics) affects unit survivability
- **Victory conditions** — Conquest, Singularity (complete AGI Core), or Wonder

### Economy
- **5 resources** — Food, Wood, Stone, Gold, Knowledge
- **Trade system** — trade carts and merchant ships move goods between markets and docks
- **River transport** — build river docks and ship resources via attackable barges
- **Market mechanics** — buy/sell resources with dynamic supply-and-demand pricing
- **Resource depletion and regeneration** — natural resources deplete over time and slowly recover
- **Corruption** — resource drain scales with empire size, forcing expansion trade-offs

### World
- **Procedural map generation** — terrain types with weighted distribution
- **Wolf fauna AI** — wolves patrol, aggro, and flee; hunt them for food or domesticate them into loyal dog companions
- **9 building types** — Town Center, House, Farm, Barracks, Library, Market, Dock, River Dock, Wonder
- **Building damage states** — structures visually degrade, collapse into ruins, and release pop cap on destruction

### AI Opponent
- **4 personality types** — Builder (economic focus), Rusher (early aggression), Boomer (fast expansion), Turtle (defensive)
- **Configurable difficulty** — scaling bonuses and AI decision-making parameters
- **Personality-specific build orders** — each AI type follows a distinct opening strategy

## Project Status

**In active development.** Core gameplay systems are implemented and tested. Current focus areas:

- AI opponent intelligence (Singularity awareness, strategic decision-making)
- Civilizations system (3 planned: Mesopotamia, Rome, Polynesia)
- Naval and vehicle units
- UI/HUD polish (minimap, menus, game lobby)
- Map generation improvements (elevation, rivers)

## Architecture

Roots of Reason is fully **data-driven** — all gameplay numbers live in JSON files, not in scripts. This makes balancing, modding, and testing straightforward.

| | Count |
|-|-------|
| GDScript source files | 64 |
| JSON data files | 71 |
| Test files | 74 |
| Test functions | 1,194 |

## Getting Started

### Requirements
- [Godot 4.6](https://godotengine.org/download)
- Python 3.10+ (for tooling and tests)

### Run the Game
```bash
git clone https://github.com/mainstreetlogic/roots-of-reason.git
cd roots-of-reason
# Open project.godot in Godot and press F5
```

### Development
```bash
ror test        # Run GdUnit4 test suite
ror lint        # Lint + format check (gdtoolkit)
ror coverage    # Check test coverage
```

## License

All rights reserved.

# Scene Tree Conventions

## Main Scene Structure

`scenes/prototype/prototype_main.tscn` — assembled in `PrototypeMain._ready()`:

```
PrototypeMain (Node2D)
├── MapNode (TilemapTerrain)          ── terrain, rivers, resources
├── Camera2D
├── Units (Node2D)                    ── parent for all unit instances
├── Buildings (Node2D)                ── parent for all building instances
├── Resources (Node2D)               ── parent for resource nodes (berries, trees, mines)
├── Fauna (Node2D)                    ── parent for fauna (wolves, dogs)
│
├── PathfindingGrid                   ── A* pathfinder (AStarGrid2D wrapper)
├── TargetDetector                    ── spatial entity index for click detection
├── VisibilityManager                 ── LOS/FOW tracking per player
├── FogOfWarLayer (CanvasLayer)       ── visual fog overlay
│
├── BuildingPlacer                    ── ghost preview + placement validation
├── InputHandler                      ── keyboard/mouse input routing
├── CursorOverlay                     ── cursor feedback
│
├── PopulationManager                 ── population cap tracking
├── TechManager                       ── research queues + progression
├── UnitUpgradeManager                ── stat bonuses from research
├── CorruptionManager                 ── knowledge erosion
├── TradeManager                      ── trade routes + gold generation
├── RiverTransport                    ── river trade bonus
├── VictoryManager                    ── win/defeat conditions
├── WarSurvival                       ── medical tech chain
├── PandemicManager                   ── disease events
├── HistoricalEventManager            ── Black Plague, Renaissance
├── KnowledgeBurningVFX              ── visual effects for tech regression
├── SingularityRegression             ── knowledge burning logic
│
├── ResourceBar (UI)                  ── resource display
├── InfoPanel (UI)                    ── selected entity info
├── CommandPanel (UI)                 ── unit/building action buttons
├── NotificationPanel (UI)            ── event alerts
├── MinimapUI                         ── minimap
├── TechTreeViewer (UI)               ── scrollable tech tree
├── PauseMenu (UI)
├── CivSelectionScreen (UI)           ── initial civ choice
│
└── (Per AI player)
    ├── AIEconomy                     ── resource gathering, build orders
    ├── AIMilitary                    ── unit production, attacks
    ├── AITech                        ── research selection
    └── AISingularity                 ── endgame strategy
```

## Unit Node Structure

`scripts/prototype/prototype_unit.gd` — extends Node2D

```
PrototypeUnit (Node2D)
├── Sprite                            ── unit visual (8-direction)
├── SelectionIndicator                ── highlight ring when selected
├── HealthBar                         ── HP bar overlay
└── (attached via composition)
    ├── UnitStats (RefCounted)        ── dynamic stats with modifiers
    └── CombatVisual                  ── red flash, knockback, death anim
```

**Key properties:** `owner_id`, `unit_type`, `unit_category`, `hp/max_hp`, `kill_count`

## Building Node Structure

`scripts/prototype/prototype_building.gd` — extends Node2D

```
PrototypeBuilding (Node2D)
├── Sprite                            ── building visual
├── ConstructionOverlay               ── translucent during construction
├── HealthBar                         ── HP bar
├── GarrisonIndicator                 ── shows garrisoned unit count
├── RallyPointMarker                  ── rally point visual
└── (attached via composition)
    └── ProductionQueue (Node)        ── unit training queue (per building)
```

**Key properties:** `owner_id`, `building_name`, `footprint` (Vector2i), `grid_pos`, `under_construction`, `is_drop_off`, `garrison_capacity`

## Map Node Structure

`scripts/map/tilemap_terrain.gd` — extends TileMapLayer

```
TilemapTerrain (TileMapLayer)
└── (generates at runtime)
    ├── ElevationGenerator            ── Perlin noise height map
    ├── RiverGenerator                ── downhill flow tracing
    ├── CoastlineGenerator            ── water edge smoothing
    ├── ResourceGenerator             ── berries, trees, mines, fish
    ├── StartingLocationGenerator     ── safe starting positions
    └── FaunaGenerator                ── wolves
```

**Terrain types:** grass, dirt, sand, water, forest, stone, mountain, river

**Tile size:** 128x64 (isometric diamond)

## Conventions

1. **Entity parents** — all runtime entities go under typed parent nodes (Units, Buildings, Resources, Fauna)
2. **Composition over inheritance** — UnitStats is RefCounted, ProductionQueue is a child Node, CombatVisual is attached
3. **Owner tracking** — every entity has `owner_id: int` for player identification
4. **Grid coordinates** — buildings use `grid_pos: Vector2i`; units use world position with grid conversion via tilemap

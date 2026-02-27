# System Relationships

How the major systems connect and communicate.

## High-Level Architecture

```
AUTOLOADS (Global Singletons)
  GameManager ........... clock, pause/speed, age progression, civ assignments
  ResourceManager ....... per-player stockpiles (food, wood, stone, gold, knowledge)
  CivBonusManager ....... civilization bonuses, unique unit/building replacements
  DataLoader ............ JSON cache, data lookups (units, buildings, techs, civs)
  SaveManager ........... orchestrates save/load across all systems

GAMEPLAY SYSTEMS
  TechManager --------> UnitUpgradeManager --------> UnitStats
  (research queues)     (apply stat buffs)            (base + modifiers)

  VictoryManager <----- PrototypeUnit ------------> CombatResolver
  (win/defeat)          (gather, fight, move)        (damage calc, pure)

                        PrototypeBuilding <-------> ProductionQueue
                        (construction, garrison)     (unit training per building)

  PopulationManager <-> BuildingPlacer              TradeManager
  (pop cap tracking)    (ghost preview, placement)   (trade routes, gold)

MAP SYSTEMS
  TilemapTerrain ------> PathfindingGrid            VisibilityManager
  (terrain gen, tiles)   (A* pathfinding)            (LOS/FOW per player)

  TargetDetector                                    FogOfWarLayer
  (click detection)                                 (visual overlay)

EVENT SYSTEMS
  HistoricalEventManager    PandemicManager         WarSurvival
  (Black Plague, Renaissance) (disease events)       (medical tech chain)

  SingularityRegression     KnowledgeBurningVFX
  (tech loss logic)          (visual effects)

AI SYSTEMS (per player)
  AIEconomy     AIMilitary     AITech        AISingularity
  (villagers,   (army comp,    (research     (endgame AGI
   build order)  attacks)       priorities)   strategy)
```

## Key Integration Paths

### Resource Spending (who calls ResourceManager.spend)

| Caller | Trigger |
|--------|---------|
| BuildingPlacer | Player places a building |
| ProductionQueue | Unit added to training queue |
| TechManager | Research started |
| TradeManager | Trade route established |

### Tech Effects (who listens to TechManager.tech_researched)

| Listener | Action |
|----------|--------|
| UnitUpgradeManager | Apply stat modifiers to matching units |
| VictoryManager | Check for Singularity victory tech chain |
| HistoricalEventManager | Trigger Renaissance on tech milestones |
| AITech | Update research priorities |
| TechTreeViewer | Refresh UI display |

### Combat Chain

    PrototypeUnit._process()
        | (attack cooldown elapsed)
        v
    CombatResolver.calculate_damage(attacker_stats, defender_stats, config)
        | Formula: max(1, (atk - def) * bonus_vs * armor_mult * bldg_reduction)
        v
    target.damage(amount)
        | (if hp <= 0)
        v
    unit_died(unit, killer) signal
        |
        +--> VictoryManager -- check defeat (all TCs destroyed?)
        +--> PirateManager -- drop bounty gold on pirate kill
        +--> killer.kill_count += 1

### Victory Condition Checks

    VictoryManager monitors:
        |
        +-- Military Victory
        |   All enemy Town Centers destroyed (5-second grace period)
        |
        +-- Singularity Victory
        |   Reach age 6 (Singularity) + build AGI Core
        |
        +-- Wonder Victory
            Build Wonder + survive countdown (600s default)

### Save/Load Serialization Order

    SaveManager.save_game(slot)
        +-- GameManager.save_state()       --> time, speed, age, civs
        +-- ResourceManager.save_state()   --> stockpiles, multipliers
        +-- CivBonusManager.save_state()   --> active civ bonuses

    Per-entity (future expansion):
        +-- TechManager.save_state()       --> researched techs, queue, progress
        +-- PopulationManager.save_state() --> pop counts, building contributions
        +-- TilemapTerrain.save_map_data() --> tile grid, elevation, rivers
        +-- ProductionQueue.save_state()   --> per-building training queue
        +-- UnitStats.save_state()         --> per-unit modifiers

## Communication Patterns

1. **Autoloads emit signals** — GameManager, ResourceManager, CivBonusManager broadcast state changes; any system can listen
2. **Gameplay systems make direct calls** — TechManager calls ResourceManager.spend(); BuildingPlacer calls ResourceManager.can_afford()
3. **DataLoader is passive** — pure data lookup, no signals, no side effects
4. **AI issues player-like commands** — AI systems call the same methods as player input (move_to, gather_from, attack_target)
5. **Events apply timed effects** — HistoricalEventManager and PandemicManager apply temporary modifiers, then restore originals
6. **CombatResolver is pure** — stateless damage calculation, no side effects

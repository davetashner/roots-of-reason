# Technology Tree Design — Roots of Reason

The technology tree is the spine of the game. It drives age progression, gates buildings and units, and ultimately leads to the Singularity victory (AGI).

## Design Principles

1. **Work backwards from AGI** — every tech exists to serve a prerequisite chain or create meaningful strategic choices along that chain
2. **Accelerating research** — slow and manual early, exponential at Singularity (1.0x → 5.0x multiplier)
3. **War drives innovation** — combat grants escalating research bonuses (+5% Stone → +40% Information), with military techs having civilian spillovers
4. **Early-game friction** — pandemics (random events) and corruption (scaling drain) keep early ages from being pure economy sims
5. **Ocean risk/reward** — Compass unlocks deep ocean navigation but triggers Gaia pirate spawns
6. **Escalating density** — 4 → 6 → 8 → 10 → 13 → 15 → 8 techs per age (64 total)

## The AGI Critical Path

The minimum research chain from Stone Age to AGI Core is ~12 techs deep:

```
Writing → Mathematics → Electricity → Computing Theory → Machine Learning
→ Neural Networks → Deep Learning → Transformer Architecture → Alignment Research
                                                                    ↓
                                                                AGI Core ★
```

Supporting chain for buildings:
- Semiconductor Fab → Parallel Computing → GPU Foundry
- Transformer Architecture → Transformer Lab
- Alignment Research → AGI Core

A player rushing Singularity victory must research the right chain across 5+ ages while defending Town Centers against Knowledge Burning.

---

## Age Breakdown

### Stone Age — 4 techs
*Survival basics. No Knowledge generation. Everything is manual labor.*

| # | Tech | Cost | Time | Prerequisites | Effects |
|---|------|------|------|---------------|---------|
| 1 | Stone Tools | 50F | 25s | — | Gather rate +10% |
| 2 | Fire Mastery | 75F | 30s | — | Hunting yield +20%, night LOS +2 |
| 3 | Animal Husbandry | 100F | 40s | Stone Tools | Unlock Sheep Pen |
| 4 | Basket Weaving | 75F, 25W | 30s | Stone Tools | Carry capacity +25% |

**Notes:** Fast and linear. Food-only costs mirror the survival economy. Players research everything before advancing.

### Bronze Age — 6 techs
*First civilizations. Writing enables Knowledge generation.*

| # | Tech | Cost | Time | Prerequisites | Effects |
|---|------|------|------|---------------|---------|
| 5 | Bronze Working | 150F, 100G | 45s | — | Melee attack +1, unlock Barracks & Infantry |
| 6 | Writing | 100F, 75W | 50s | — | Unlock Library (Knowledge gen begins) |
| 7 | Pottery | 100F, 50W | 35s | — | Food decay -50%, unlock Market |
| 8 | Irrigation | 200F, 150W | 60s | Writing | Farm output +25% |
| 9 | Masonry | 150W, 100S | 50s | Bronze Working | Building HP +20%, unlock Stone Wall |
| 10 | Sailing | 200W, 75G | 55s | — | Unlock Dock & Fishing Boat |

**Notes:** Writing is pivotal — it unlocks Libraries which generate Knowledge. Without Knowledge, later ages are inaccessible. Bronze Working gates military. Sailing opens coastal naval game.

### Iron Age — 8 techs
*Classical civilizations. Philosophy, mathematics, law. Corruption becomes a factor.*

| # | Tech | Cost | Time | Prerequisites | Effects |
|---|------|------|------|---------------|---------|
| 11 | Iron Working | 200F, 150G | 55s | Bronze Working | Melee attack +2, unlock Swordsman |
| 12 | Philosophy | 150G, 100K | 60s | Writing | Knowledge gen +25% |
| 13 | Mathematics | 200G, 150K | 65s | Writing | Construction speed +15%, siege accuracy +10% |
| 14 | Currency | 250G | 50s | Pottery | Gold income +15%, Market upgrade |
| 15 | Engineering | 200W, 200S, 100K | 70s | Mathematics | Unlock Siege Workshop & Aqueduct |
| 16 | Code of Laws | 200G, 150K | 60s | Writing | Corruption -30%, villager efficiency +10% |
| 17 | Trireme | 300W, 100G | 65s | Sailing | Unlock War Galley |
| 18 | Herbalism | 150F, 100K | 50s | — | Pandemic severity -25%, slow HP regen out of combat |

**Notes:** Knowledge costs appear for the first time. Code of Laws is the first corruption counter. Herbalism is the first pandemic counter. Both are optional but punish players who skip them.

### Medieval Age — 10 techs
*Feudalism, castles, gunpowder, ocean exploration. PIRATES spawn after Compass.*

| # | Tech | Cost | Time | Prerequisites | Effects |
|---|------|------|------|---------------|---------|
| 19 | Steel Working | 300G, 200S | 70s | Iron Working | Defense +2 all military, building armor +10% |
| 20 | Feudalism | 250F, 150G | 60s | Code of Laws | Villager train time -20%, food income +10% |
| 21 | Compass | 200G, 150K | 65s | Trireme, Mathematics | Naval LOS +3, unlock deep ocean. **PIRATES SPAWN** |
| 22 | Printing Press | 300G, 200K | 80s | Writing, Philosophy | Knowledge gen +50%, research time -10% |
| 23 | Guilds | 350G, 100K | 60s | Currency | Trade rates +25%, gold income +15% |
| 24 | Castle Architecture | 400S, 200G | 90s | Masonry, Engineering | Unlock Castle, fortification HP +30% |
| 25 | Gunpowder | 350G, 200K | 85s | Iron Working | Unlock Hand Cannoneer, siege dmg +25%. *Spillover: Mining +10%* |
| 26 | Banking | 400G, 200K | 75s | Currency, Guilds | Gold income +20%, corruption -25% |
| 27 | Shipbuilding | 350W, 200G | 70s | Compass | Naval HP +25%, transport capacity +50% |
| 28 | Crop Rotation | 250F, 150W | 55s | Irrigation | Farm output +30% |

**Notes:** Compass triggers pirate spawning — "The Age of Exploration has begun." Ocean access enables trade routes but feeds the pirates. Gunpowder is the first tech with military→civilian spillover.

### Industrial Age — 13 techs
*MAJOR acceleration (1.5x). War bonus becomes significant (+30%). Corruption and pandemics can be eliminated.*

| # | Tech | Cost | Time | Prerequisites | Effects | War Spillover |
|---|------|------|------|---------------|---------|---------------|
| 29 | Steam Power | 400W, 300G, 200K | 80s | Engineering | Work rate +30%, unlock Factory | — |
| 30 | Rifling | 350G, 250K | 70s | Gunpowder | Ranged attack +30% | Mining +15% |
| 31 | Railroad | 500W, 400S, 200G | 90s | Steam Power | Resource transport 2x speed | — |
| 32 | Electricity | 400G, 350K | 85s | Mathematics, Steam Power | Knowledge gen +100%, unlock Telegraph | — |
| 33 | Steel Production | 400S, 300G, 200K | 80s | Steel Working | Building HP +30%, naval HP +30% | — |
| 34 | Chemistry | 350G, 300K | 75s | Mathematics | Prereq for Dynamite, Pasteurization, Atomic Theory | — |
| 35 | Sanitation | 300F, 200S, 200K | 65s | Engineering, Herbalism | Pandemic severity -50%, pop growth +25% | — |
| 36 | Pasteurization | 350F, 300K | 70s | Chemistry, Sanitation | Food decay eliminated, camp disease immunity, +1 HP/s idle regen | — |
| 37 | Vaccines | 400F, 500K | 80s | Pasteurization | **Pandemic immunity**, military units +15% max HP | — |
| 38 | Assembly Line | 500G, 300K | 85s | Steam Power | Unit train time -40% | — |
| 39 | Dynamite | 300G, 250K | 70s | Gunpowder, Chemistry | Siege damage +50% | Stone mining +25% |
| 40 | Civil Service | 400G, 300K | 70s | Code of Laws, Banking | **Corruption eliminated** | — |
| 41 | Ballistics | 400G, 350K | 80s | Mathematics, Rifling | Ranged accuracy +20%, unlock Artillery | Navigation +10% |

**The Medical Revolution:** Sanitation → Pasteurization → Vaccines mirrors 1850s–1900s history. Before these techs, wars are brutally attritional. After Vaccines, military units are 15% beefier and regenerate. This creates a compound advantage: medical tech → units survive longer → sustained war bonus → faster research.

**Corruption/Pandemic elimination:** Vaccines (pandemic immunity) and Civil Service (corruption eliminated) free players who invested in these chains to industrialize at full speed.

### Information Age — 15 techs
*Research acceleration dramatic (2.5x). War bonus at +40%. AGI precursor chain begins.*

| # | Tech | Cost | Time | Prerequisites | Effects | War Spillover |
|---|------|------|------|---------------|---------|---------------|
| 42 | Atomic Theory | 500G, 500K | 70s | Chemistry | Knowledge gen +50% | — |
| 43 | Computing Theory | 600K | 75s | Electricity, Mathematics | Knowledge gen +100% | — |
| 44 | Transistors | 500G, 600K | 70s | Electricity | Research speed +25% | — |
| 45 | Nuclear Fission | 600G, 700K | 90s | Atomic Theory | Unlock Nuclear Plant | — |
| 46 | Rocketry | 500G, 500K | 80s | Ballistics, Chemistry | Unlock Missile unit | Navigation +15% |
| 47 | Satellite | 700G, 600K | 85s | Rocketry | Map visibility (territory), GPS: unit speed +10% | — |
| 48 | Semiconductor Fab | 800G, 700K | 90s | Transistors | Research speed +15% | — |
| 49 | Internet | 600G, 900K | 85s | Computing Theory, Semiconductor Fab | Knowledge gen +200%, Libraries share research | — |
| 50 | Machine Learning | 500G, 800K | 80s | Computing Theory, Statistics | Knowledge gen +75% | — |
| 51 | Statistics | 400G, 500K | 65s | Mathematics | Economic forecast: Gold +10% | — |
| 52 | Radar | 500G, 600K | 70s | Electricity, Rocketry | Enemy detection +50% | Farm +10% |
| 53 | Guided Missiles | 700G, 700K | 85s | Rocketry, Computing Theory | Ranged attack +50% | — |
| 54 | Antibiotics | 500F, 800K | 80s | Vaccines, Chemistry | **War Survival: 25% chance stabilize at 1 HP** (60s cooldown). Pandemic cannot kill villagers. | — |
| 55 | Genetics | 400F, 700K | 75s | Antibiotics, Chemistry | Food output +40%, population health +20% | — |
| 56 | Cybersecurity | 500G, 800K | 80s | Internet | Espionage protection, +10% defense vs tech regression | — |

**Antibiotics is the crown jewel of the medical chain.** War Survival (25% stabilization at 1 HP) transforms late-game warfare. The compound effect: more units survive → army stays larger → war bonus lasts longer → research accelerates. A medically advanced civ gets ~60% more effective research output during wartime.

### Singularity Age — 8 techs
*Exponential research (5.0x). The AGI race. Every tech choice is critical.*

| # | Tech | Cost | Time | Prerequisites | Effects | Alert |
|---|------|------|------|---------------|---------|-------|
| 57 | Neural Networks | 800G, 1200K | 60s | Machine Learning | Knowledge gen +150% | — |
| 58 | Big Data | 600G, 1000K | 55s | Internet, Statistics | Economic optimization +20% | — |
| 59 | Parallel Computing | 1000G, 1500K | 70s | Semiconductor Fab | Research speed +50%, unlock GPU Foundry | — |
| 60 | Deep Learning | 1000G, 2000K | 80s | Neural Networks, Big Data | Knowledge gen +300% | — |
| 61 | Quantum Computing | 1500G, 2500K | 90s | Computing Theory, Parallel Computing | Research speed +100% | — |
| 62 | Robotics | 800G, 1500K | 65s | Machine Learning, Assembly Line | Villager work rate +50%, military production +30% | — |
| 63 | Transformer Architecture | 1500G, 3000K | 100s | Deep Learning, Parallel Computing | Unlock Transformer Lab | **PUBLIC ALERT** |
| 64 | Alignment Research | 1000G, 4000K | 120s | Transformer Architecture | Unlock AGI Core | **PUBLIC ALERT** |

**Notes:** Knowledge costs are enormous — you need a Knowledge-generation empire. Quantum Computing is optional but transformative. The two PUBLIC ALERT techs announce to all players that someone is approaching victory. This is the Knowledge Burning danger zone.

---

## Prerequisite Graph

```
STONE AGE (4)
  Stone Tools ──→ Animal Husbandry
       │
       └──→ Basket Weaving
  Fire Mastery

BRONZE AGE (6)
  Bronze Working ──→ [Iron Working]
  Writing ──→ [Philosophy, Irrigation, Code of Laws]
  Pottery ──→ [Currency]
  Masonry ──→ [Castle Architecture]
  Sailing ──→ [Trireme]

IRON AGE (8)
  Iron Working ──→ [Steel Working, Gunpowder]
  Philosophy ──→ [Printing Press]
  Mathematics ──→ [Engineering, Compass, Ballistics, Chemistry, Computing Theory, Statistics]
  Currency ──→ [Guilds]
  Engineering ──→ [Steam Power, Sanitation]
  Code of Laws ──→ [Feudalism, Civil Service]
  Trireme ──→ [Compass]
  Herbalism ──→ [Sanitation]

MEDIEVAL AGE (10)
  Steel Working ──→ [Steel Production]
  Compass ──→ [Shipbuilding] ⚓ PIRATES
  Printing Press
  Guilds ──→ [Banking]
  Gunpowder ──→ [Rifling, Dynamite]
  Banking ──→ [Civil Service]

INDUSTRIAL AGE (13)
  Steam Power ──→ [Railroad, Assembly Line]
  Electricity ──→ [Transistors, Radar, Computing Theory]
  Chemistry ──→ [Dynamite, Pasteurization, Atomic Theory]
  Sanitation ──→ [Pasteurization]
  Pasteurization ──→ [Vaccines]
  Vaccines ──→ [Antibiotics]
  Rifling ──→ [Ballistics]
  Ballistics ──→ [Rocketry]

INFORMATION AGE (15)
  Computing Theory ──→ [Machine Learning, Quantum Computing, Guided Missiles]
  Transistors ──→ [Semiconductor Fab]
  Semiconductor Fab ──→ [Parallel Computing, Internet]
  Rocketry ──→ [Satellite, Guided Missiles]
  Machine Learning ──→ [Neural Networks, Robotics]
  Statistics ──→ [Machine Learning, Big Data]
  Antibiotics ──→ [Genetics]

SINGULARITY AGE (8)
  Neural Networks ──→ Deep Learning
  Big Data ──→ Deep Learning
  Parallel Computing ──→ Transformer Architecture
  Deep Learning ──→ Transformer Architecture [PUBLIC ALERT]
  Transformer Architecture ──→ Alignment Research [PUBLIC ALERT]
  Alignment Research ──→ AGI Core ──→ ★ VICTORY
```

---

## New Game Mechanics

### Research Rate Acceleration

Base research speed is multiplied by an age-dependent factor. Individual tech bonuses stack additively on top.

| Age | Multiplier | War Bonus |
|-----|-----------|-----------|
| Stone | 1.0x | +5% |
| Bronze | 1.0x | +8% |
| Iron | 1.1x | +10% |
| Medieval | 1.2x | +15% |
| Industrial | 1.5x | +30% |
| Information | 2.5x | +40% |
| Singularity | 5.0x | +25% |

**Formula:** `effective_speed = base_speed * age_multiplier * (1 + sum(tech_bonuses)) * (1 + war_bonus)`

War bonus activates when at least 1 military unit is in combat, lingers for 30 seconds after combat ends.

### Corruption

Corruption scales with empire size, reducing resource income (except Knowledge).

- Active in ages 1–4 (Bronze through Industrial)
- Starts when building count exceeds 8, grows 1.5% per building beyond that
- Caps at 30% income loss
- Counters: Code of Laws (-30%), Banking (-25%), Civil Service (eliminates)

### Pandemics

Random events that trigger based on population density.

- Active in ages 0–3 (Stone through Medieval)
- Checked every 2 minutes, base 5% chance (+2% per villager above 15 population)
- Effects: -30% work rate, 5% villager death chance, lasts 45 seconds
- Counters: Herbalism (-25% severity), Sanitation (-50% severity), Vaccines (full immunity)

### Pirates

Gaia hostile naval units that spawn after any player researches Compass.

- Spawn every 90 seconds from ocean edges, max 8 active
- Carry 30–120 Gold bounty (scaled by age)
- Target fishing boats, trade barges, transport ships
- Avoid military vessels and garrisoned docks
- Spawn rate decreases in later ages, nearly gone by Singularity

### War Survival (Medical Tech Chain)

The medical chain creates an escalating war survival advantage:

| Tech | Cumulative Effect |
|------|-------------------|
| Herbalism | Pandemic severity -25% |
| Sanitation | Pandemic severity -50%, pop growth +25% |
| Pasteurization | +1 HP/s idle regen, camp disease immunity |
| Vaccines | +15% max HP for military, pandemic immunity |
| Antibiotics | 25% chance survive lethal hit at 1 HP (60s cooldown) |

**Compound effect:** More units survive → army stays larger → war bonus lasts longer → research accelerates. ~60% more effective research during wartime for a medically advanced civ vs one without.

---

## Data Files

| File | Purpose |
|------|---------|
| `data/tech/tech_tree.json` | All 64 techs with costs, prereqs, effects |
| `data/tech/ages.json` | 7 ages with costs, prereqs, research multipliers |
| `data/settings/research.json` | Research acceleration, war bonus settings |
| `data/settings/corruption.json` | Corruption scaling settings |
| `data/settings/pandemics.json` | Pandemic event settings |
| `data/settings/pirates.json` | Pirate spawning settings |
| `data/settings/war_survival.json` | Medical chain combat settings |

## Balance Levers

Key tunable values for playtesting:

- **Age research multipliers** — controls pacing curve across the game
- **War bonus by age** — how much combat accelerates research
- **War bonus linger** (30s) — how long bonus persists after combat ends
- **Corruption rate/cap** (1.5%/building, 30% max) — early-game economic friction
- **Pandemic probability/severity** — early-game risk events
- **Pirate spawn rate/bounty** — ocean risk/reward balance
- **Antibiotics stabilize chance** (25%) and cooldown (60s) — late-game war survival power
- **Singularity tech costs** — how much Knowledge empire is needed to win

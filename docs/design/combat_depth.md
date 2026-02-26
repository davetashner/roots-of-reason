# Combat Depth: Armor Types and Damage Modifiers

**Status:** Proposal
**Bead:** roots-of-reason-n32
**Date:** 2026-02-26

## 1. Current System Summary

The existing combat formula in `combat_resolver.gd`:

```
raw = (attack - defense) * bonus_vs_mult * armor_effectiveness_mult * building_reduction
damage = max(1, int(raw))
```

**Armor effectiveness matrix** (`combat.json`):

| Attack \ Armor | none | light | heavy | siege |
|---------------|------|-------|-------|-------|
| melee         | 1.0  | 1.0   | 0.75  | 1.5   |
| ranged        | 1.0  | 1.2   | 0.5   | 1.0   |
| siege         | 1.0  | 1.0   | 1.0   | 0.5   |

**Rock-paper-scissors bonuses** (via `bonus_vs`):

| Unit     | Bonus vs  | Multiplier |
|----------|-----------|------------|
| Infantry | archer    | 1.5x       |
| Archer   | cavalry   | 1.5x       |
| Cavalry  | infantry  | 1.5x       |
| Siege    | building  | 5.0x       |

### Current Unit Stats

| Unit           | HP  | ATK | DEF | Speed | Range | Armor  | Attack Type |
|---------------|-----|-----|-----|-------|-------|--------|-------------|
| Infantry      | 40  | 6   | 1   | 1.2   | 0     | light  | melee       |
| Archer        | 30  | 5   | 0   | 1.3   | 5     | none   | ranged      |
| Cavalry       | 50  | 8   | 1   | 2.2   | 0     | light  | melee       |
| Siege Ram     | 200 | 40  | 3   | 0.6   | 0     | siege  | siege       |
| Legionnaire   | 40  | 6   | 4   | 1.2   | 0     | heavy  | melee       |
| Immortal Guard| 60  | 6   | 1   | 1.2   | 0     | heavy  | melee       |

## 2. Problem Statement

The current system works but has structural limitations:

1. **Flat `bonus_vs` multipliers scale linearly with attack.** A 1.5x bonus on a 6-attack infantry does +3 damage. With tech upgrades pushing attack to 10, the same 1.5x gives +5. This makes bonuses grow unpredictably with progression and makes them hard to balance independently of base stats.

2. **Defense is weak.** With `attack - defense` as the base, defense=1 only removes 1 point from a 6-8 attack. The armor effectiveness matrix partially compensates (heavy armor halves ranged), but the multiplicative stacking means defense improvements have diminishing tactical value. A player who invests in defensive techs sees marginal returns.

3. **No flat bonus damage.** AoE-style "+8 vs cavalry" bonuses create sharp, legible counter relationships. Multiplicative-only bonuses create softer counters that are harder for players to read and harder to tune independently.

4. **Armor matrix lacks granularity for future units.** Three attack types serve the current roster but leave no room for mixed-type units (a Hand Cannoneer with both ranged and siege properties) or future armor classes (padded, mail, plate progression within an age).

## 3. Evaluated Approaches

### Option A: Split Damage Channels (AoE2-style)

Each attack has **melee damage** and **pierce damage** components. Each defender has **melee armor** and **pierce armor**. Damage is calculated per channel:

```
damage = max(1, (melee_atk - melee_armor) + (pierce_atk - pierce_armor))
```

**Pros:** Proven at scale (AoE2 has 100+ units balanced this way), allows fine-grained tuning.
**Cons:** Doubles the stat count per unit, significantly more complex JSON, harder to explain to players, overkill for our 6-unit roster. Would require rewriting the stat modifier system to handle per-channel bonuses.

**Verdict: Reject.** Too complex for the current roster size. Revisit if the unit count exceeds ~15.

### Option B: Flat + Multiplicative Bonus Damage (Recommended)

Keep the current formula structure but add a **flat bonus damage** component to `bonus_vs`, applied after base damage but before armor:

```
base      = attack - defense
bonus     = flat_bonus + (base * (multiplier - 1.0))
raw       = (base + bonus) * armor_mult * building_reduction
damage    = max(1, int(raw))
```

Each `bonus_vs` entry becomes `{ "flat": N, "mult": M }` instead of a bare multiplier.

**Pros:** Backward-compatible (existing multiplier-only entries work with `flat: 0`), flat bonuses are legible and tunable, multiplier bonuses still available for scaling effects (tech upgrades, civ bonuses). Minimal code change.
**Cons:** Slightly more complex JSON per bonus entry.

**Verdict: Recommended.** Best balance of expressiveness and simplicity.

### Option C: Expanded Armor Matrix Only

Keep the current formula but expand the armor matrix with more types (padded, mail, plate, wooden, stone) and more attack types (pierce, hack, crush).

**Pros:** No bonus_vs changes needed, armor identity becomes more meaningful.
**Cons:** Doesn't solve the flat bonus problem, adds complexity to every unit's armor assignment, and a 5x5+ matrix is hard to balance and communicate to players.

**Verdict: Reject for now.** The current 3x4 matrix is sufficient. Expanding it adds complexity without solving the core issue. The matrix can grow later if the unit roster demands it.

## 4. Proposed Formula (Option B)

### 4.1 Damage Calculation

```
Step 1: base_damage     = attacker.attack - defender.defense
Step 2: bonus_flat      = bonus_vs[defender_type].flat       (default 0)
Step 3: bonus_mult      = bonus_vs[defender_type].mult       (default 1.0)
Step 4: bonus_damage    = bonus_flat + base_damage * (bonus_mult - 1.0)
Step 5: effective       = (base_damage + bonus_damage) * armor_effectiveness
Step 6: building_mod    = apply building reduction if defender is building
Step 7: final_damage    = max(1, int(effective * building_mod))
```

When `bonus_mult = 1.0`, step 4 reduces to just `bonus_flat` (pure additive).
When `bonus_flat = 0`, step 4 reduces to `base_damage * (mult - 1.0)` (current behavior).

### 4.2 Updated `bonus_vs` JSON Format

```json
"bonus_vs": {
  "cavalry": { "flat": 8, "mult": 1.0 },
  "archer":  { "flat": 4, "mult": 1.2 }
}
```

**Backward compatibility:** If a bare number is found (e.g., `"archer": 1.5`), treat it as `{ "flat": 0, "mult": 1.5 }`. This means zero migration cost for existing data.

### 4.3 Updated Armor Effectiveness Matrix

No changes to the matrix structure. The current 3x4 matrix is retained:

| Attack \ Armor | none | light | heavy | siege |
|---------------|------|-------|-------|-------|
| melee         | 1.0  | 1.0   | 0.75  | 1.5   |
| ranged        | 1.0  | 1.2   | 0.5   | 1.0   |
| siege         | 1.0  | 1.0   | 1.0   | 0.5   |

This matrix already creates meaningful armor choices. Heavy armor is strong vs ranged (0.5x) but slightly weak vs melee (0.75x is close to neutral). Siege armor is strong vs siege but weak vs melee (1.5x).

### 4.4 Proposed Unit Stat Adjustments

Migrate from pure-multiplier bonuses to flat+mult:

| Unit           | Current `bonus_vs`       | Proposed `bonus_vs`                     | Rationale |
|---------------|--------------------------|----------------------------------------|-----------|
| Infantry      | `archer: 1.5`            | `archer: { flat: 4, mult: 1.0 }`       | Flat +4 is a fixed, readable counter. Doesn't scale with upgrades. |
| Archer        | `cavalry: 1.5`           | `cavalry: { flat: 6, mult: 1.0 }`      | Higher flat because archers need meaningful cavalry deterrent despite lower base attack. |
| Cavalry       | `infantry: 1.5`          | `infantry: { flat: 4, mult: 1.0 }`     | Cavalry already has high base attack (8); flat +4 is sufficient. |
| Siege Ram     | `building: 5.0`          | `building: { flat: 0, mult: 5.0 }`     | Keep multiplicative — siege vs buildings should scale with attack upgrades. |

## 5. Scenario Comparisons

### Scenario 1: Infantry vs Archer (counter matchup)

**Current formula:**
```
base    = 6 - 0 = 6
bonus   = 6 * 1.5 = 9 (bonus_vs: archer 1.5x)
armor   = 9 * 1.0 (melee vs none) = 9
damage  = 9
hits to kill = ceil(30 / 9) = 4 hits @ 1.5s = 6.0s
```

**Proposed formula:**
```
base    = 6 - 0 = 6
bonus   = 4 + 6 * (1.0 - 1.0) = 4 (flat +4, mult 1.0)
raw     = (6 + 4) = 10
armor   = 10 * 1.0 (melee vs none) = 10
damage  = 10
hits to kill = ceil(30 / 10) = 3 hits @ 1.5s = 4.5s
```

**With Iron Working (+2 melee attack):**
- Current: `(8 - 0) * 1.5 * 1.0 = 12 damage` (33% increase from tech)
- Proposed: `(8 - 0) + 4 = 12 damage` (20% increase from tech)

The flat bonus doesn't inflate with upgrades — the counter strength stays constant while raw power scales, which is healthier for late-game balance.

### Scenario 2: Archer vs Cavalry (counter matchup)

**Current formula:**
```
base    = 5 - 1 = 4
bonus   = 4 * 1.5 = 6 (bonus_vs: cavalry 1.5x)
armor   = 6 * 1.2 (ranged vs light) = 7.2
damage  = 7
hits to kill = ceil(50 / 7) = 8 hits @ 2.0s = 16.0s
```

**Proposed formula:**
```
base    = 5 - 1 = 4
bonus   = 6 + 4 * (1.0 - 1.0) = 6 (flat +6, mult 1.0)
raw     = (4 + 6) = 10
armor   = 10 * 1.2 (ranged vs light) = 12
damage  = 12
hits to kill = ceil(50 / 12) = 5 hits @ 2.0s = 10.0s
```

The flat +6 makes archers a meaningful cavalry deterrent. Currently 16s to kill cavalry is too slow — cavalry closes the gap and fights in melee where archers lose badly. At 10s, archers still don't win 1v1 (cavalry closes in ~3s at speed 2.2), but a group of archers creates a real threat. This pushes cavalry players toward flanking or mixing in infantry — more interesting decisions.

### Scenario 3: Cavalry vs Infantry (counter matchup)

**Current formula:**
```
base    = 8 - 1 = 7
bonus   = 7 * 1.5 = 10.5 (bonus_vs: infantry 1.5x)
armor   = 10.5 * 1.0 (melee vs light) = 10.5
damage  = 10
hits to kill = ceil(40 / 10) = 4 hits @ 1.2s = 4.8s
```

**Proposed formula:**
```
base    = 8 - 1 = 7
bonus   = 4 + 7 * (1.0 - 1.0) = 4 (flat +4, mult 1.0)
raw     = (7 + 4) = 11
armor   = 11 * 1.0 (melee vs light) = 11
damage  = 11
hits to kill = ceil(40 / 11) = 4 hits @ 1.2s = 4.8s
```

Similar result — cavalry remains a strong infantry counter. The difference shows in late game with upgrades.

### Scenario 4: Infantry vs Legionnaire (non-counter, heavy armor)

**Current formula:**
```
base    = 6 - 4 = 2
bonus   = 2 * 1.0 = 2 (no bonus_vs infantry)
armor   = 2 * 0.75 (melee vs heavy) = 1.5
damage  = 1
hits to kill = ceil(40 / 1) = 40 hits @ 1.5s = 60.0s
```

**Proposed formula (identical — no bonus_vs change):**
```
Same: damage = 1, 40 hits, 60.0s
```

This shows Legionnaire's extreme survivability vs generic infantry. Defense=4 plus heavy armor makes them near-invincible to same-tier melee. This is intentional — it's Rome's unique strength. Countered by massed archers (even at 0.5x armor effectiveness, archers still do `(5-4) * 0.5 = 1` damage per hit, but many archers chipping away beats a slow melee fight).

### Scenario 5: Archer vs Legionnaire (ranged vs heavy armor)

**Current formula:**
```
base    = 5 - 4 = 1
bonus   = 1 * 1.0 = 1 (no bonus vs legionnaire)
armor   = 1 * 0.5 (ranged vs heavy) = 0.5
damage  = 1 (min 1)
hits to kill = ceil(40 / 1) = 40 hits @ 2.0s = 80.0s
```

This is a problem. Heavy armor + high defense makes Legionnaires nearly immune to archers too. The min-1 damage floor means any unit eventually kills anything, but 80 seconds is effectively "can't kill."

**Proposed: No stat changes needed.** This is actually desirable design — Legionnaires *should* be hard for archers to kill. The counter is to use Cavalry (which has `bonus_vs: infantry` and is melee, getting 0.75x armor instead of 0.5x) or massed siege.

### Scenario 6: Siege Ram vs Building (specialization)

**Current formula:**
```
base    = 40 - 3 = 37 (assuming building def=3)
bonus   = 37 * 5.0 = 185 (bonus_vs: building 5.0x)
armor   = N/A (buildings don't have armor_type currently)
bldg    = 185 * (1.0 - 0.80 + 0.80) = 185 * 1.0 = 185
damage  = 185
```

**Proposed formula (unchanged — still multiplicative):**
```
Same: 185 damage
```

Siege keeps its multiplicative bonus because siege vs buildings *should* scale with attack upgrades — that's the whole point of investing in siege tech.

### Scenario 7: Infantry vs Cavalry (wrong side of the counter)

**Current formula:**
```
base    = 6 - 1 = 5
bonus   = 5 * 1.0 = 5 (infantry has no bonus_vs cavalry)
armor   = 5 * 1.0 (melee vs light) = 5
damage  = 5
hits to kill = ceil(50 / 5) = 10 hits @ 1.5s = 15.0s
```

**Proposed formula (same — no bonus_vs changes):**
```
Same: damage = 5, 10 hits, 15.0s
```

Meanwhile cavalry kills infantry in 4.8s. The counter ratio is 15.0/4.8 = 3.1x time advantage. This is a healthy asymmetry.

## 6. Late-Game Scaling Comparison

With Iron Working (+2 melee attack) and Steel Working (+2 defense):

### Infantry (8 atk / 3 def) vs Archer (5 atk / 0 def)

| Formula | Damage | Hits to Kill | Time |
|---------|--------|-------------|------|
| Current (1.5x mult) | `(8-0)*1.5*1.0 = 12` | 3 | 4.5s |
| Proposed (flat +4)   | `(8-0)+4 = 12 * 1.0 = 12` | 3 | 4.5s |

Identical at this upgrade level. But at even higher attack:

### Infantry with +4 attack total (10 atk) vs Archer

| Formula | Damage | Notes |
|---------|--------|-------|
| Current (1.5x mult) | `(10-0)*1.5 = 15` | Bonus grew from 3 to 5 (+67%) |
| Proposed (flat +4)   | `(10-0)+4 = 14` | Bonus stayed at 4 (flat) |

The multiplicative bonus inflates faster than intended. Flat bonuses stay constant, keeping counter relationships stable across ages.

## 7. Implementation Notes

### Code Changes (combat_resolver.gd)

The `bonus_vs` resolution block (lines 19-29) changes from:

```gdscript
# Current: bare multiplier
var bonus: float = 1.0
if bonus_vs.has(defender_type):
    bonus = float(bonus_vs[defender_type])
raw *= bonus
```

To:

```gdscript
# Proposed: flat + multiplier object, with bare-number backward compat
var bonus_entry = null
if bonus_vs.has(defender_type):
    bonus_entry = bonus_vs[defender_type]
elif bonus_vs.has(defender_category):
    bonus_entry = bonus_vs[defender_category]

if bonus_entry != null:
    var flat_bonus: float = 0.0
    var mult_bonus: float = 1.0
    if bonus_entry is Dictionary:
        flat_bonus = float(bonus_entry.get("flat", 0))
        mult_bonus = float(bonus_entry.get("mult", 1.0))
    else:
        mult_bonus = float(bonus_entry)  # backward compat
    raw = raw + flat_bonus + raw * (mult_bonus - 1.0)
```

### Data Changes

All in `data/units/*.json` — update `bonus_vs` entries from bare numbers to `{ "flat": N, "mult": M }` objects. Existing bare numbers continue to work via backward compatibility.

### Test Changes

Update `test_combat_resolver.gd` to cover:
- Pure flat bonus (flat > 0, mult = 1.0)
- Pure multiplicative bonus (flat = 0, mult > 1.0)
- Combined flat + multiplicative
- Backward compatibility with bare number bonus
- Late-game scenario with tech modifiers applied

### No Armor Matrix Changes

The current 3x4 armor effectiveness matrix is retained as-is. It already provides good differentiation and doesn't need expansion for the current roster.

## 8. Decision Summary

| Criterion | Decision |
|-----------|----------|
| Armor type system | **Keep current 3x4 matrix** — sufficient for roster size |
| Bonus damage system | **Add flat bonus alongside multiplier** — better late-game scaling |
| Damage formula | **Flat + mult hybrid** — backward compatible, data-driven |
| Data format | **Object `{ flat, mult }`** with bare-number fallback |
| Implementation scope | ~15 lines of code change + JSON migration |

## 9. Future Considerations (Not In Scope)

- **Split damage channels** (melee/pierce): Revisit when unit count > 15
- **Armor progression** (padded -> mail -> plate): Could replace armor_type per age
- **Damage variance** (random +-10%): Adds unpredictability, deferred to playtesting
- **Critical hits:** Percentage-based bonus damage, deferred to playtesting
- **Area-of-effect damage:** Siege splash damage, separate design task

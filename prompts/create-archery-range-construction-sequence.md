# Archery Range — Construction Sequence Art Prompt (Stone Age)

## Goal

Generate a **4-frame construction sequence** for the **Archery Range** — a Stone Age military building in the Roots of Reason RTS game. This is a formidable military training facility where archers are produced. It should feel dangerous and purposeful — a place where warriors train with primitive ranged weapons.

## Art Style Reference

Match the existing building sprites exactly:

| Building | Key Visual Traits |
|----------|-------------------|
| **Barracks** | Wooden longhouse with steep timber roof, palisade fence perimeter, campfire in courtyard, magenta banners — large imposing military building |
| **Lumber Camp** | Rough-hewn logs, open-sided wooden shelter, log piles, earthy palette |
| **Mining Camp** | Open wooden shelter with stone workbench, stone piles, rustic tools |
| **House** | Round hut with thatched conical roof, stone foundation ring, warm earthy tones |
| **Granary** | Thatched rectangular storehouse, wooden frame, magenta cloth accents |

**Common traits across ALL buildings:**
- Hand-painted digital art style with visible brushwork texture
- Warm earthy palette — browns, tans, ochre, muted greens
- Isometric 3/4 top-down view (~35 degrees), facing south-east
- Sandy/dirt ground patches beneath structures (no grass)
- Rough, rustic construction — nothing is perfectly straight or clean
- Magenta (#FF00FF) used as flat solid color for banners/cloth — NOT pink, NOT gradient, pure #FF00FF
- Transparent background (alpha channel)

## Sprite Specification

| Property | Value |
|----------|-------|
| Output | Single wide image with **4 equal-width frames** side by side (left to right) |
| Per-frame canvas | Each frame will be downscaled to **256x192px** (2x2 footprint) |
| Footprint | **2x2 tiles** — same size class as the Lumber Camp |
| Background | **Fully transparent** (alpha channel, no ground plane extending to edges) |
| View angle | Isometric 3/4 top-down (~35 degrees), facing south-east |
| Player color | **Magenta (#FF00FF)** flag/banner — present in frames 3 and 4 |

## Stone Age Context

This is the **Stone Age** version of the archery range — the earliest, most primitive era. Technology is limited to:
- **Materials:** Wood, stone, bone, leather, thatch, animal hide, sinew, vine rope
- **NO metal** of any kind — no bronze, no iron, no nails, no metal fittings
- **NO refined construction** — joints are lashed with rope/sinew, not nailed or mortared
- **Weapons present:** Stone-tipped arrows, primitive bows (short recurve or simple stick bows), flint arrowheads, bone-tipped javelins/spears, stone axes, leather quivers

## Frame-by-Frame Description

### Frame 1 — Ground Cleared & Materials Gathered (0% complete)

- Cleared flat dirt/sand ground area forming a rough rectangular patch
- Scattered **stone age weapons and training equipment** on the ground:
  - A few primitive short bows lying flat
  - Loose flint arrowheads and stone-tipped arrows in a small pile
  - A couple of wooden javelins/short spears with stone tips
- Small pile of wooden logs/stakes ready for construction
- A few post holes dug into the ground
- Stones and rocks gathered in a pile for the foundation
- Overall impression: a building site with military purpose evident from the weapons

### Frame 2 — Frame Erected (35% complete)

- Vertical wooden posts driven into the ground forming the building perimeter
- Partial stone foundation wall visible on one or two sides (rough stacked stones, no mortar)
- Cross-beams lashed to the uprights with visible vine/sinew rope
- Roof framing just beginning — a ridge pole resting across the top of two posts
- **Weapons still visible** — bows and arrows leaning against posts, a stone axe embedded in a log
- A crude wooden **archery target** (round log slice or bundled straw) propped against a post
- Construction debris: wood shavings, bark strips, rope coils

### Frame 3 — Walls & Roof Taking Shape (70% complete)

- Walls partially filled in with woven wattle (interlaced sticks) and daub (mud plaster)
- One side still open, showing interior
- Thatched roof partially covering the structure — bundled reed/straw thatch tied to the roof frame
- Inside visible: a wooden rack holding several bows, a barrel/basket of arrows
- **Archery target** now standing upright nearby — bundled straw circle with arrows stuck in it
- A **magenta (#FF00FF) flag** on a short pole, planted near the entrance — flat solid magenta, triangular pennant shape
- Scattered stone-tipped weapons around the perimeter: spears leaning on walls, quivers on the ground
- The building is starting to look formidable — taller than a house, wider stance

### Frame 4 — Completed Archery Range (100% complete)

- **Imposing rectangular structure** with thick wooden post-and-beam construction
- **Full thatched roof** — steep pitch, overhanging eaves, bundled straw/reed
- **Wattle-and-daub walls** on three sides, open front facing the viewer (south-east) showing the interior
- **Stone foundation** visible at base — rough stacked fieldstone, ~knee height
- Inside the open front: wooden weapon racks displaying bows and quivers, a workbench for arrow-crafting
- **Archery target range** on one side — two bundled straw targets with arrows embedded, at different distances
- **Magenta (#FF00FF) flag** prominently displayed — large triangular pennant on a tall pole mounted on the roof ridge or at the entrance. Flat solid magenta, clearly visible
- **Stone age weapons scattered around the perimeter:**
  - Quivers of stone-tipped arrows leaning against walls
  - Spare bows hung on exterior wall pegs
  - A few javelins/spears in a wooden rack or stuck into the ground
  - Flint knapping station (flat stone with flint chips) near the entrance
- **Defensive touches:** Sharpened wooden stakes angled outward at the base (primitive anti-approach), giving it a military/fortified feel
- Small campfire or torch holder near entrance for atmosphere
- Packed dirt courtyard in front — training ground area

## Critical Requirements

1. **4 frames in one horizontal strip**, left to right, evenly spaced with consistent framing
2. **2x2 tile scale** — must read clearly when downscaled to 256x192px per frame
3. **Transparent background** — clean alpha, no colored background
4. **Magenta (#FF00FF) player color** flag/banner in frames 3 and 4 — flat solid color, NO gradient, NO pink, exact hex #FF00FF
5. **Stone Age ONLY** — absolutely no metal. Wood, stone, bone, leather, thatch, rope/sinew only
6. **Military character** — this should look like a place that produces warriors, not a barn. Weapons visible in every frame. More formidable than economic buildings (lumber camp, mining camp)
7. **Consistent building position** — the structure should occupy the same footprint area across all 4 frames, growing upward and outward progressively
8. **Match existing art style** — hand-painted digital, warm earthy palette, same level of detail and rendering as the house, lumber camp, and barracks sprites shown above
9. **Archery targets** visible from frame 2 onward — this is the key visual identifier that distinguishes it from the barracks

## Post-Processing Pipeline

```bash
# Split the 4-frame strip into individual frames
python3 tools/split_spritesheet.py \
  assets/sprites/buildings/archery_range_sequence_raw.png \
  --grid 4x1 \
  --output-dir assets/sprites/buildings/placeholder \
  --prefix archery_range_building_sequence_04

# Stitch into game-ready horizontal strip (1024x192)
python3 -c "
from PIL import Image
frames = []
for i in range(1, 5):
    f = Image.open(f'assets/sprites/buildings/placeholder/archery_range_building_sequence_04_{i:02d}.png')
    f = f.resize((256, 192), Image.LANCZOS)
    frames.append(f)
strip = Image.new('RGBA', (1024, 192), (0, 0, 0, 0))
for i, f in enumerate(frames):
    strip.paste(f, (i * 256, 0))
strip.save('assets/sprites/buildings/placeholder/archery_range_building_sequence.png')
"

# Restore magenta after LANCZOS downscaling
python3 -c "
from PIL import Image
img = Image.open('assets/sprites/buildings/placeholder/archery_range_building_sequence.png')
pixels = img.load()
for y in range(img.height):
    for x in range(img.width):
        r, g, b, a = pixels[x, y]
        if r > 200 and g < 80 and b > 200 and a > 128:
            pixels[x, y] = (255, 0, 255, 255)
img.save('assets/sprites/buildings/placeholder/archery_range_building_sequence.png')
"

# Validate
./tools/ror validate-assets -v
```

The game loads `placeholder/{name}_building_sequence.png` and auto-detects frame count from strip width / (footprint_x * 128).

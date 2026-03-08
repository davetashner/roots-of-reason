# Barracks — Construction Sequence Art Prompt (Bronze Age)

## Goal

Generate a **4-frame construction sequence** for the **Barracks** — a Bronze Age military training compound in the Roots of Reason RTS game. The barracks is the primary melee military building where infantry and cavalry are trained. It should be the largest, most imposing military building in the Bronze Age — a fortified compound with a palisade perimeter, training yard, and a thatched longhouse.

A finished barracks sprite already exists (shown below in the reference section). The construction sequence must build toward that final design — a wooden longhouse with steep timber plank roof, surrounded by a palisade fence, with a campfire in the courtyard and magenta banners.

## Art Style Reference

Match these existing construction sequences **exactly** in style, rendering, and palette:

| Building | Sequence Pattern | Key Visual Traits |
|----------|-----------------|-------------------|
| **Lumber Camp** (4 frames, 2x2) | Rocks+logs on ground → Posts erected → Roof frame with magenta cloth → Finished shelter with log pile | Rough-hewn logs, open-sided wooden shelter, earthy palette, small magenta diamond on frame 3-4 |
| **Mining Camp** (4 frames, 2x2) | Rocks+planks on ground → Posts erected → Open shelter frame with magenta curtain → Finished open shelter with workbench | Wooden posts, stone piles, purple/magenta curtain accents on sides |
| **House** (3 frames, 2x2) | Stone foundation ring → Conical roof frame with magenta door panel → Finished round hut with thatch roof | Round hut, thatched conical roof, stone base, magenta rectangular door/panel |
| **Granary** (4 frames, 2x2) | Rocks+lumber scattered → Posts with platform → Wattle walls forming with magenta cloth → Finished storehouse with thatch roof | Rectangular, wooden frame, thatched roof, magenta cloth accents |
| **Archery Range** (4 frames, 2x2) | Stone foundation → Post-and-beam frame with target → Partial thatch roof with magenta flag → Finished range with weapons and magenta flag | Military feel, archery targets, stone base, thatched roof, magenta pennant flag |

**Critical style traits shared by ALL existing sequences:**
- Hand-painted digital art — visible brushwork, NOT 3D rendered, NOT pixel art
- Warm earthy palette: browns, tans, ochre, sandy yellows, muted stone grays
- Dark outlines and shadows give weight and definition
- Sandy/dirt ground patches beneath structures
- Isometric 3/4 top-down view (~35 degrees), facing **south-east**
- Buildings grow from bottom-left to upper-right in isometric space
- Frame 1 is always raw materials on cleared ground (lowest/flattest)
- Each frame grows progressively taller and more complete
- Magenta (#FF00FF) player color appears starting at frame 3 — as cloth, banners, or door panels
- Transparent background (alpha channel) — NO colored backdrop

## Sprite Specification

| Property | Value |
|----------|-------|
| Output | Single wide image with **4 equal-width frames** side by side (left to right) |
| Per-frame canvas | Each frame will be downscaled to **384x256px** (3x3 footprint) |
| Footprint | **3x3 tiles** — larger than lumber camp/archery range (2x2), same as town center |
| Background | **Fully transparent** (alpha channel) |
| View angle | Isometric 3/4 top-down (~35 degrees), facing south-east |
| Player color | **Magenta (#FF00FF)** banners/flags — present in frames 3 and 4 |

## Finished Barracks Reference

The completed barracks (frame 4) must match the existing finished sprite:
- **Steep timber plank roof** on a large wooden longhouse — dark brown planks, ridge beam running along the top
- **Palisade fence** surrounds the compound — sharpened vertical logs forming a perimeter wall
- **Open courtyard** inside the palisade with packed dirt ground
- **Campfire** burning in the center of the courtyard
- **Training dummy or warrior figure** visible in the yard
- **Multiple magenta (#FF00FF) banners** — tall rectangular banners on poles, prominently displayed (at least 2-3 visible)
- **Small magenta pennant** on the roof peak
- **Stone/log foundation** visible at the base of walls
- Overall impression: a fortified military compound, not just a building — the palisade fence makes it feel like a defended camp

## Frame-by-Frame Description

### Frame 1 — Ground Cleared & Materials Gathered (0% complete)

- Large cleared dirt/sand area — bigger than a 2x2 building, this is a 3x3 compound
- Scattered construction materials on the ground:
  - Pile of rough-hewn logs (for the palisade and longhouse frame)
  - Stack of timber planks (for the roof)
  - Mound of stones/rocks (for the foundation)
  - Coils of rope
- A few post holes dug in a rough perimeter pattern (hinting at the palisade layout)
- A bronze sword or shield lying on the ground — subtle military identity
- Small tool scatter: a stone axe embedded in a log stump, a wooden mallet
- Overall impression: a large building site with military purpose

### Frame 2 — Palisade & Frame Rising (35% complete)

- **Partial palisade fence** — sharpened vertical log stakes driven into the ground along 2-3 sides of the perimeter, gaps still open on other sides
- Horizontal cross-beams lashed to the palisade stakes with rope
- Inside the partial fence: **vertical posts** for the longhouse frame — 4-6 thick wooden uprights
- A ridge beam beginning to rest across the top of the tallest posts
- Stone foundation partially laid at the base of the longhouse posts — rough stacked fieldstone
- Construction debris: bark strips, wood shavings, spare logs leaning against the palisade
- A couple of wooden training weapons (practice swords, a shield) leaning against a post — the warriors are already claiming the space
- The compound is taking shape — you can see the perimeter and the building footprint

### Frame 3 — Structure Taking Shape (70% complete)

- **Palisade fence nearly complete** — sharpened stakes all around the perimeter, one section still being finished
- **Longhouse frame fully erected** with roof timbers in place — angled rafters visible
- **Partial roof coverage** — timber planks laid across the front half of the roof, rear half still open showing the rafter skeleton
- **Wattle-and-daub walls** partially filling in the longhouse sides — woven sticks visible through gaps
- Inside the courtyard: a stone-ringed fire pit (not yet lit), a simple wooden weapon rack
- **Magenta (#FF00FF) banners** — two tall rectangular banners on poles planted inside the courtyard, flat solid magenta color
- Entrance gap in the palisade clearly defined — the future gate opening
- The building reads as "almost done" — the overall shape and military character are clear

### Frame 4 — Completed Barracks (100% complete)

Must match the existing finished barracks sprite:
- **Large wooden longhouse** with a **steep timber plank roof** — dark brown planks, ridge beam along the peak
- **Complete palisade fence** surrounding the entire compound — sharpened vertical logs, tightly packed, with horizontal cross-beams
- **Open entrance** in the palisade facing south-east (toward the viewer)
- **Courtyard** inside the palisade:
  - **Campfire** burning in the center — orange/yellow flames, stone ring around it
  - Packed dirt ground
  - Training dummy or standing warrior figure
  - Weapon racks visible
- **Multiple magenta (#FF00FF) banners** prominently displayed:
  - At least 2 tall rectangular banners on poles in the courtyard
  - 1 small pennant on the roof ridge
  - All flat solid #FF00FF, clearly visible against the dark wood
- **Stone foundation** visible at the base of the longhouse walls
- **Military atmosphere** — this is the largest, most fortified building in the Bronze Age. It should feel like a defended camp, not just a shed

## Critical Requirements

1. **4 frames in one horizontal strip**, left to right, evenly spaced with consistent framing
2. **3x3 tile scale** — this is a LARGE building. Must read clearly when downscaled to 384x256px per frame. The barracks should be noticeably bigger than the 2x2 buildings (lumber camp, archery range)
3. **Transparent background** — clean alpha, no colored background
4. **Magenta (#FF00FF) player color** banners in frames 3 and 4 — flat solid color, NO gradient, NO pink, NO red, exact hex #FF00FF
5. **Bronze Age technology** — wood, stone, rope, thatch, bronze. No iron, no advanced masonry
6. **Palisade fence is key** — this is what distinguishes the barracks from other buildings. The wooden stake perimeter fence should be the most prominent feature, growing across the sequence
7. **Match the finished sprite** — frame 4 must match the existing barracks.png design: longhouse + palisade + campfire + banners
8. **Consistent building position** — the compound should occupy the same footprint area across all 4 frames, growing upward and filling in progressively
9. **Match existing art style EXACTLY** — hand-painted digital, warm earthy palette, same level of detail, same isometric angle, same shadow/outline treatment as the lumber camp, mining camp, house, and archery range sequences

## Post-Processing Pipeline

```bash
# Split the 4-frame strip into individual frames
python3 tools/split_spritesheet.py \
  assets/sprites/buildings/barracks_sequence_raw.png \
  --grid 4x1 \
  --output-dir assets/sprites/buildings/placeholder \
  --prefix barracks_building_sequence_04

# Stitch into game-ready horizontal strip (1536x256)
python3 -c "
from PIL import Image
frames = []
for i in range(1, 5):
    f = Image.open(f'assets/sprites/buildings/placeholder/barracks_building_sequence_04_{i:02d}.png')
    f = f.resize((384, 256), Image.LANCZOS)
    frames.append(f)
strip = Image.new('RGBA', (1536, 256), (0, 0, 0, 0))
for i, f in enumerate(frames):
    strip.paste(f, (i * 384, 0))
strip.save('assets/sprites/buildings/placeholder/barracks_building_sequence.png')
"

# Restore magenta after LANCZOS downscaling
python3 -c "
from PIL import Image
img = Image.open('assets/sprites/buildings/placeholder/barracks_building_sequence.png')
pixels = img.load()
for y in range(img.height):
    for x in range(img.width):
        r, g, b, a = pixels[x, y]
        if a > 128:
            # Snap blended pink/purple back to pure magenta
            if r > 150 and g < 100 and b > 150:
                pixels[x, y] = (255, 0, 255, 255)
            # Catch red/crimson flag pixels that should be magenta
            elif r > 180 and g < 60 and b > 80:
                pixels[x, y] = (255, 0, 255, 255)
img.save('assets/sprites/buildings/placeholder/barracks_building_sequence.png')
"

# Validate
./tools/ror validate-assets -v
```

The game loads `placeholder/{name}_building_sequence.png` and auto-detects frame count from strip width / (footprint_x * 128). For the 3x3 barracks: 1536 / 384 = 4 frames.

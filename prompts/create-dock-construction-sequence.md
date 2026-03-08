# Dock — Construction Sequence Art Prompt (Bronze Age)

## Goal

Generate a **4-frame construction sequence** for the **Dock** — a Bronze Age waterfront building in the Roots of Reason RTS game. The dock is a naval production building built at the water's edge where fishing boats, transport ships, and warships are constructed. It should read as a sturdy wooden pier and boathouse extending out over water, with a covered workshop area for shipbuilding.

No finished dock sprite exists yet — design a Bronze Age dock that fits naturally alongside the existing building set (lumber camp, mining camp, barracks, etc.).

## Art Style Reference

Match these existing construction sequences **exactly** in style, rendering, and palette:

| Building | Sequence Pattern | Key Visual Traits |
|----------|-----------------|-------------------|
| **Lumber Camp** (4 frames, 2x2) | Rocks+logs on ground → Posts erected → Roof frame with magenta cloth → Finished shelter with log pile | Rough-hewn logs, open-sided wooden shelter, earthy palette, small magenta diamond on frame 3-4 |
| **Mining Camp** (4 frames, 2x2) | Rocks+planks on ground → Posts erected → Open shelter frame with magenta curtain → Finished open shelter with workbench | Wooden posts, stone piles, purple/magenta curtain accents on sides |
| **House** (3 frames, 2x2) | Stone foundation ring → Conical roof frame with magenta door panel → Finished round hut with thatch roof | Round hut, thatched conical roof, stone base, magenta rectangular door/panel |
| **Granary** (4 frames, 2x2) | Rocks+lumber scattered → Posts with platform → Wattle walls forming with magenta cloth → Finished storehouse with thatch roof | Rectangular, wooden frame, thatched roof, magenta cloth accents |
| **Archery Range** (4 frames, 2x2) | Stone foundation → Post-and-beam frame with target → Partial thatch roof with magenta flag → Finished range with weapons and magenta flag | Military feel, archery targets, stone base, thatched roof, magenta pennant flag |
| **Barracks** (4 frames, 3x3) | Materials on ground → Palisade+posts rising → Roof timbers+magenta banners → Finished longhouse compound with palisade, campfire, banners | Large fortified compound, palisade fence, steep timber roof, multiple magenta banners |

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
| Footprint | **3x3 tiles** — same size as barracks and town center |
| Background | **Fully transparent** (alpha channel) |
| View angle | Isometric 3/4 top-down (~35 degrees), facing south-east |
| Player color | **Magenta (#FF00FF)** banners/flags — present in frames 3 and 4 |

## Design Concept — Bronze Age Dock

The dock is a waterfront structure — a wooden pier extending out over water with a covered boathouse/workshop. Key design elements:

- **Wooden pier/jetty** — thick timber planks on heavy log pilings driven into the water
- **Covered workshop area** — a thatched roof shelter on the pier for shipbuilding/repairs
- **Water visible** — the lower portion of the sprite should show water (blue-green, semi-transparent) lapping at the pilings. The dock extends FROM land (upper-left in isometric space) OUT over water (lower-right)
- **Mooring posts** — thick upright posts with rope coiled around them for tying boats
- **Nautical details** — rope coils, wooden oars, a fishing net draped to dry, a small anchor
- **Boatbuilding evidence** — timber ribs of a hull under construction, planks being shaped
- The land/shore edge should be visible in the upper-left portion of the sprite, transitioning to water

## Frame-by-Frame Description

### Frame 1 — Shore Cleared & Materials Gathered (0% complete)

- The shore edge — sandy/rocky beach meeting water — visible as a diagonal line (isometric)
- **Water** in the lower-right portion — calm blue-green, shallow and translucent near shore
- Construction materials piled on the shore:
  - Long straight logs for pilings (stacked parallel)
  - Rough-cut timber planks for the deck
  - Coils of heavy rope
  - Stone weights or anchors
- A few starter pilings driven into the shallows — thick logs sticking up out of the water at angles
- A wooden mallet and stone tools on the beach
- A small rowboat or dugout canoe pulled up on shore — suggesting the nautical purpose
- Overall impression: a waterfront construction site, materials ready

### Frame 2 — Pilings & Deck Frame Rising (35% complete)

- **Pilings driven in** — a grid of thick vertical log posts standing in the water, supporting the pier structure
- **Partial deck planking** — timber planks laid across the pilings nearest to shore, creating the beginning of the walkable pier surface
- Cross-bracing visible between pilings below the deck level — logs lashed together with rope for structural support
- The pier extends partway out over the water from the shore
- On shore: vertical posts beginning to rise for the workshop/boathouse structure
- Loose planks and construction materials still scattered on the finished portion of the deck
- Rope lashing visible at every joint — Bronze Age construction, no nails
- The water is visible between and beneath the pilings

### Frame 3 — Structure Taking Shape (70% complete)

- **Pier deck mostly complete** — timber planking extends the full length out over water
- **Boathouse frame erected** — vertical posts and a ridge beam for the covered workshop area on the pier
- **Partial thatched roof** — reed/straw thatch covering the front portion of the boathouse, rear still showing the rafter skeleton
- **Mooring posts** — thick timber uprights at the pier edges with rope coiled around them
- On the deck: a partially built boat hull (curved wooden ribs visible) — showing the dock's purpose
- Rope and tools scattered on the deck
- **Magenta (#FF00FF) elements** — a magenta sail cloth or banner hanging from the boathouse frame, and a small magenta pennant on one of the mooring posts
- Water visible around and beneath the pier structure
- The structure reads clearly as a dock/pier now

### Frame 4 — Completed Dock (100% complete)

- **Full wooden pier** extending from shore over water — thick timber deck on heavy log pilings
- **Covered boathouse/workshop** with a complete **thatched roof** — a rectangular shelter on the pier, open on the water-facing side for boats to approach
- Inside the boathouse: a workbench, boat-building tools, timber hull ribs of a ship under construction
- **Mooring posts** with rope at the pier edges — at least 2-3 prominent ones
- A **fishing net** draped to dry on a rack or stretched between posts
- Wooden oars leaning against the boathouse wall
- A coil of rope, a small wooden crane or boom for lifting cargo
- **Magenta (#FF00FF) player color elements:**
  - A large magenta sail cloth or banner hanging from the boathouse (the primary player color indicator)
  - A small magenta pennant flag on a mooring post
  - All flat solid #FF00FF, clearly visible
- **Water** visible around the pier — calm, blue-green, with subtle ripple texture near the pilings
- **Shore/land** visible in the upper-left corner where the pier connects to land
- Overall impression: a functional Bronze Age shipyard — sturdy, weathered wood, nautical atmosphere

## Critical Requirements

1. **4 frames in one horizontal strip**, left to right, evenly spaced with consistent framing
2. **3x3 tile scale** — this is a LARGE building. Must read clearly when downscaled to 384x256px per frame
3. **Transparent background** — clean alpha, no colored background. The WATER should be rendered as part of the sprite (not the background), with visible transparency beneath the water where appropriate
4. **Magenta (#FF00FF) player color** sail cloth/banners in frames 3 and 4 — flat solid color, NO gradient, NO pink, NO red, exact hex #FF00FF
5. **Bronze Age technology** — wood, stone, rope, thatch, reed. No iron, no advanced masonry, no metal fittings
6. **Water is key** — this is the ONLY building that sits partially over water. The lower-right portion of each frame should show water. This is what distinguishes the dock from all other buildings
7. **Shore-to-water transition** — the sprite must show the land/shore edge in the upper-left transitioning to water in the lower-right, with the pier extending out from land over the water
8. **Consistent building position** — the pier/dock should occupy the same footprint area across all 4 frames, growing upward and filling in progressively
9. **Match existing art style EXACTLY** — hand-painted digital, warm earthy palette, same level of detail, same isometric angle, same shadow/outline treatment as the lumber camp, mining camp, house, barracks, and archery range sequences

## Post-Processing Pipeline

```bash
# Split the 4-frame strip into individual frames
python3 tools/split_spritesheet.py \
  assets/sprites/buildings/dock_sequence_raw.png \
  --grid 4x1 \
  --output-dir assets/sprites/buildings/placeholder \
  --prefix dock_building_sequence_04

# Stitch into game-ready horizontal strip (1536x256)
python3 -c "
from PIL import Image
frames = []
for i in range(1, 5):
    f = Image.open(f'assets/sprites/buildings/placeholder/dock_building_sequence_04_{i:02d}.png')
    f = f.resize((384, 256), Image.LANCZOS)
    frames.append(f)
strip = Image.new('RGBA', (1536, 256), (0, 0, 0, 0))
for i, f in enumerate(frames):
    strip.paste(f, (i * 384, 0))
strip.save('assets/sprites/buildings/placeholder/dock_building_sequence.png')
"

# Restore magenta after LANCZOS downscaling
python3 -c "
from PIL import Image
img = Image.open('assets/sprites/buildings/placeholder/dock_building_sequence.png')
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
img.save('assets/sprites/buildings/placeholder/dock_building_sequence.png')
"

# Validate
./tools/ror validate-assets -v
```

The game loads `placeholder/{name}_building_sequence.png` and auto-detects frame count from strip width / (footprint_x * 128). For the 3x3 dock: 1536 / 384 = 4 frames.

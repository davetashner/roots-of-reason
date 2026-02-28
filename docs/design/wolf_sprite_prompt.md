# Wolf & Dog Sprite Generation Prompts

Reusable prompt templates for generating wolf (wild fauna) and dog (domesticated companion) sprites for Roots of Reason. Follows the same conventions as villager sprites.

## Technical Specs

| Parameter | Value |
|-----------|-------|
| Canvas size | 128x128 pixels per frame |
| Sprite height | ~48-52px (smaller than infantry, larger than nothing) |
| Directions | 8: S, SE, E, NE, N, NW, W, SW |
| Magenta mask | #FF00FF region for player color recoloring (dog only) |
| Naming | `{wolf\|dog}_{animation}_{direction}_{frame}.png` |
| Output path | `assets/sprites/units/wolf/` and `assets/sprites/units/dog/` |

## Animations Required

### Wolf (wild)
| Animation | Frames | Loop | Notes |
|-----------|--------|------|-------|
| idle | 2 | yes | Standing alert, ears up, slight breathing |
| walk | 4 | yes | Stalking gait, head level with spine |
| attack | 3 | no | Lunge/snap, mouth open |
| death | 2 | no | Collapse to side |

### Dog (domesticated)
| Animation | Frames | Loop | Notes |
|-----------|--------|------|-------|
| idle | 2 | yes | Sitting or standing calm, tongue out |
| walk | 4 | yes | Trotting gait, tail up |
| death | 2 | no | Lying down |

## Base Prompt — Wolf

```
Create a 2D isometric sprite sheet for a wild wolf in an RTS game (Age of Empires style).

TECHNICAL REQUIREMENTS:
- Each frame on a 128x128 pixel canvas (or 512x512 for downscaling to 128x128)
- Sprite height approximately 48-52 pixels within the canvas
- Transparent background (PNG with alpha)
- Centered on canvas with feet near the bottom-center
- Isometric 3/4 top-down view (diamond-down layout, ~30 degree camera angle)
- Consistent lighting: top-left light source
- No drop shadow (handled by the engine)
- Clean pixel art with defined outlines (1-2px dark outline)

COLOR PALETTE:
- Fur base: warm gray-brown (#8B7355 to #A0896B)
- Fur highlights: lighter tan (#C4A882)
- Fur shadows: dark brown-gray (#5C4A3A)
- Belly/chest: cream-white (#D4C5A9)
- Eyes: amber-gold (#DAA520)
- Nose/mouth/paws: charcoal (#36454F)
- Inside ears: dusty pink (#B08080)

ANATOMY & POSE:
- Lean, predatory build — visible shoulder blades, narrow waist
- Head roughly level with or slightly below shoulder line
- Ears pointed upward and slightly forward (alert)
- Tail held horizontally or slightly down (neutral/alert, not tucked)
- Four visible legs in isometric view (near legs darker, far legs lighter for depth)
- Muzzle visible with slight underbite definition

DIRECTION: [DIRECTION]
ANIMATION: [ANIMATION]
FRAME: [FRAME] of [TOTAL]
```

### Per-Animation Pose Descriptions — Wolf

**idle** (2 frames, looping):
- Frame 1: Standing neutral, weight even on all four legs, mouth closed, ears forward
- Frame 2: Subtle weight shift — one front paw slightly lifted or head turned ~15 degrees, ears twitch

**walk** (4 frames, looping):
- Frame 1: Left front + right rear legs forward (contact)
- Frame 2: Left front + right rear passing under body (passing)
- Frame 3: Right front + left rear legs forward (contact)
- Frame 4: Right front + left rear passing under body (passing)
- Head stays level throughout, slight body bob

**attack** (3 frames, not looping):
- Frame 1: Crouch — rear legs compressed, head low, weight back
- Frame 2: Lunge — body extended forward, jaws open wide, front paws off ground
- Frame 3: Snap — head forward and down as if biting, front paws landing

**death** (2 frames, not looping):
- Frame 1: Stumble — legs buckling, body tilting to one side
- Frame 2: Collapsed — lying on side, legs extended, eyes closed, tongue slightly out

## Base Prompt — Dog (Domesticated Wolf)

```
Create a 2D isometric sprite sheet for a domesticated dog companion in an RTS game (Age of Empires style).

TECHNICAL REQUIREMENTS:
- Each frame on a 128x128 pixel canvas (or 512x512 for downscaling to 128x128)
- Sprite height approximately 44-48 pixels within the canvas (slightly smaller than wolf)
- Transparent background (PNG with alpha)
- Centered on canvas with feet near the bottom-center
- Isometric 3/4 top-down view (diamond-down layout, ~30 degree camera angle)
- Consistent lighting: top-left light source
- No drop shadow (handled by the engine)
- Clean pixel art with defined outlines (1-2px dark outline)
- Include a magenta (#FF00FF) region on the collar/bandana area for player color recoloring

COLOR PALETTE:
- Fur base: warmer golden-brown (#A08050 to #B8965A) — friendlier tone than wolf
- Fur highlights: light gold (#D4B87A)
- Fur shadows: medium brown (#6B5530)
- Belly/chest: white-cream (#E8DCC8)
- Eyes: warm brown (#8B6914) — softer than wolf's amber
- Nose: dark (#36454F)
- Collar/bandana: magenta (#FF00FF) — player color mask
- Tongue: pink (#E88080)

ANATOMY & POSE:
- Stockier than wolf — broader chest, shorter muzzle, more rounded features
- Ears semi-floppy or perked forward (friendly, attentive)
- Tail held up and slightly curved (happy)
- Visible collar or bandana in magenta (#FF00FF) around neck
- Overall posture more upright and eager vs wolf's predatory crouch
- Tongue visible in idle (panting happily)

DIRECTION: [DIRECTION]
ANIMATION: [ANIMATION]
FRAME: [FRAME] of [TOTAL]
```

### Per-Animation Pose Descriptions — Dog

**idle** (2 frames, looping):
- Frame 1: Standing upright, tongue out (panting), tail wagging left, ears perked
- Frame 2: Slight head tilt, tongue still out, tail wagging right

**walk** (4 frames, looping):
- Frame 1: Left front + right rear forward (contact), tail up
- Frame 2: Passing position, slight body bounce
- Frame 3: Right front + left rear forward (contact)
- Frame 4: Passing position, ears bouncing slightly
- Trotting gait — bouncier and more energetic than wolf's stalking walk

**death** (2 frames, not looping):
- Frame 1: Whimper pose — legs giving way, head drooping
- Frame 2: Lying on side, peaceful expression, collar visible

## Direction Reference (Isometric Diamond-Down)

When generating each direction, the wolf/dog faces:

| Direction | Camera Angle | Body Orientation |
|-----------|-------------|-----------------|
| S | Facing toward viewer (down-screen) | Head at bottom, tail at top |
| SE | Facing lower-right | 3/4 view, right flank visible |
| E | Facing right | Full side profile, right side |
| NE | Facing upper-right | 3/4 back view, right side |
| N | Facing away from viewer (up-screen) | Tail toward viewer |
| NW | Facing upper-left | 3/4 back view, left side |
| W | Facing left | Full side profile, left side |
| SW | Facing lower-left | 3/4 view, left flank visible |

## Batch Generation Workflow

1. Generate all wolf frames: 4 animations x 8 directions x 2-4 frames = ~88 PNGs
2. Generate all dog frames: 3 animations x 8 directions x 2-4 frames = ~64 PNGs
3. Save to `assets/sprites/units/wolf/` and `assets/sprites/units/dog/`
4. Downscale to 128x128 if generated at higher resolution
5. Run `tools/validate_sprites.py` to check naming, dimensions, magenta masks
6. Create manifest.json files for each (see villager manifest for format reference)

## Example Complete Prompt

```
Create a 2D isometric sprite sheet for a wild wolf in an RTS game (Age of Empires style).

TECHNICAL REQUIREMENTS:
- Each frame on a 128x128 pixel canvas (or 512x512 for downscaling to 128x128)
- Sprite height approximately 48-52 pixels within the canvas
- Transparent background (PNG with alpha)
- Centered on canvas with feet near the bottom-center
- Isometric 3/4 top-down view (diamond-down layout, ~30 degree camera angle)
- Consistent lighting: top-left light source
- No drop shadow (handled by the engine)
- Clean pixel art with defined outlines (1-2px dark outline)

COLOR PALETTE:
- Fur base: warm gray-brown (#8B7355 to #A0896B)
- Fur highlights: lighter tan (#C4A882)
- Fur shadows: dark brown-gray (#5C4A3A)
- Belly/chest: cream-white (#D4C5A9)
- Eyes: amber-gold (#DAA520)
- Nose/mouth/paws: charcoal (#36454F)
- Inside ears: dusty pink (#B08080)

ANATOMY & POSE:
- Lean, predatory build — visible shoulder blades, narrow waist
- Head roughly level with or slightly below shoulder line
- Ears pointed upward and slightly forward (alert)
- Tail held horizontally or slightly down (neutral/alert, not tucked)
- Four visible legs in isometric view (near legs darker, far legs lighter for depth)
- Muzzle visible with slight underbite definition

DIRECTION: SE
ANIMATION: attack
FRAME: 2 of 3

POSE: Lunge — body extended forward, jaws open wide, front paws off ground. Wolf is mid-leap toward prey, maximum extension. Teeth and tongue visible. Ears pinned back from speed.
```

## Sprite Config File

Create at `data/units/sprites/wolf.json` when sprites are ready:

```json
{
  "variants": ["wolf", "dog"],
  "base_path": "res://assets/sprites/units",
  "scale": 0.5,
  "offset_y": -16.0,
  "frame_duration": 0.3,
  "directions": ["s", "se", "e", "ne", "n", "nw", "w", "sw"],
  "animation_map": {
    "wolf": {
      "idle": ["idle"],
      "walk": ["walk"],
      "attack": ["attack"],
      "death": ["death"]
    },
    "dog": {
      "idle": ["idle"],
      "walk": ["walk"],
      "attack": ["idle"],
      "death": ["death"]
    }
  }
}
```

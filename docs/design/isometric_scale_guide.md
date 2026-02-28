# RTS Isometric Scale Guide

Compatible with the project's asset pipeline. Keeps units, buildings, and terrain visually consistent so assets read correctly once downscaled. Follows conventions from ADR-008 and classic RTS games.

## 1. Core Isometric Geometry

| Property | Value |
|----------|-------|
| Tile width | 128 px |
| Tile height | 64 px |
| Projection | 30 degree isometric |
| Ratio | 2:1 width:height |

## 2. Tile Grid Dimensions

| Footprint | Pixel Width | Pixel Height |
|-----------|-------------|--------------|
| 1x1 | 128 | 64 |
| 2x2 | 256 | 128 |
| 3x3 | 384 | 192 |
| 4x4 | 512 | 256 |
| 5x5 | 640 | 320 |

These are the diamond footprint sizes. Sprite canvases are taller to accommodate roofs, flags, and vertical detail. See ADR-008 for max sprite dimensions per footprint.

## 3. Vertical Scale Rules

Isometric games exaggerate height slightly so buildings read well.

| Object | Height relative to tile |
|--------|------------------------|
| Human unit | ~1 tile tall |
| Small building (1x1) | ~1.5 tiles |
| Medium building (2x2) | ~2 tiles |
| Major building (3x3, Town Center) | ~2.5 tiles |

### Approximate pixel heights (at game resolution)

| Object | Height |
|--------|--------|
| Villager | 48-64 px |
| House (2x2) | 96-110 px |
| Barracks (3x3) | 120-140 px |
| Town Center (3x3) | 160-200 px |

Roof peaks and banners can extend higher.

## 4. Anchor Point System

Every sprite needs a consistent anchor so the engine places it correctly.

```
        top of sprite
           |
       [ BUILDING ]
           |
      ANCHOR POINT
```

Anchor = center of the diamond footprint.

```
anchor_x = sprite_width / 2
anchor_y = base_of_building
```

Example for Town Center (1024x768 source canvas):

```
anchor_x = 512
anchor_y = ~620
```

## 5. Canvas Layout

Recommended placement inside the source canvas:

```
          flag
           |
       roof peak

     [ BUILDING ]

   stone courtyard

    --- footprint ---
         anchor
```

| Element | Position |
|---------|----------|
| Roof peak | upper 30-35% |
| Building body | middle |
| Footprint base | bottom 20% |
| Anchor point | center of diamond |

## 6. Unit Scale Reference

Villager sprite: ~48-52 px tall on a 128x128 canvas (per ADR-008).

| Comparison | Scale |
|------------|-------|
| Town Center height | ~3 villagers |
| Door height | ~1.5 villagers |
| Crate height | ~0.4 villagers |

## 7. Lighting Standard

All assets must share lighting direction.

| Property | Value |
|----------|-------|
| Light direction | Top-left |
| Shadow direction | Bottom-right |
| Highlight side | NW roof edges |
| Darkest wall | SE wall |

## 8. Color Mask Convention

Player color mask: `#FF00FF` (magenta).

Use on: banners, shields, roof flags, trims.

Engine replaces with player color at runtime via shader (see ADR-008).

## 9. Building Footprints (from data/buildings/)

Authoritative footprints live in `data/buildings/*.json`. Key buildings:

| Building | Footprint | Max Sprite Size (ADR-008) |
|----------|-----------|--------------------------|
| River Dock | 1x1 | 128x128 |
| Stone Wall | 1x1 | 128x128 |
| House | 2x2 | 256x192 |
| Farm | 2x2 | 256x192 |
| Library | 2x2 | 256x192 |
| Ziggurat | 2x2 | 256x192 |
| Town Center | 3x3 | 384x256 |
| Barracks | 3x3 | 384x256 |
| Market | 3x3 | 384x256 |
| Dock | 3x3 | 384x256 |
| Factory | 3x3 | 384x256 |
| Castle | 4x4 | 512x320 |
| AGI Core | 4x4 | 512x320 |
| Wonder | 5x5 | 640x384 |

## 10. Asset Pipeline

### Source images

Generate at high resolution for quality, then downscale to game-ready size.

| Asset Type | Source Size | Final Size |
|------------|-----------|------------|
| Terrain tile | 1024x1024 (quad sheet) | 128x64 per tile |
| Unit frame | 512x512 or 1024x1024 | 128x128 |
| Building 1x1 | 512x512 | 128x128 |
| Building 2x2 | 768x576 | 256x192 |
| Building 3x3 | 1024x768 or 1536x1024 | 384x256 |
| Building 4x4 | 1536x1024 | 512x320 |
| Building 5x5 | 2048x1280 | 640x384 |
| Resource node | 512x512 | 80x80 |

Source images go in `assets/sprites/buildings/` (alongside final sprites).
Game-ready downscaled sprites go in `assets/sprites/buildings/placeholder/`.

### Downscale steps

1. Generate at source resolution
2. Paint magenta (#FF00FF) mask on player color regions
3. Downscale to final size (LANCZOS)
4. Re-snap near-magenta pixels to exact #FF00FF after antialiasing
5. Export: PNG, RGBA, premultiplied alpha off

## 11. Visual Debug Overlay

When generating assets, use this layout reference:

```
      source canvas
  +------------------+
  |                  |
  |        ^ roof    |
  |                  |
  |     building     |
  |                  |
  |   --- footprint  |
  |        * anchor  |
  +------------------+
```

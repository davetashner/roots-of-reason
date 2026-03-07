#!/usr/bin/env python3
"""Split sheep spritesheets into individual animation frames.

Reads source spritesheets from assets/sprites/units/sheep/source/,
splits them into individual frames, crops to content, places on 128x128
canvas, generates mirrors for opposite directions, and writes a manifest.

Run from project root:
    python3 tools/split_sheep_sprites.py
"""

import json
import os
import sys

from PIL import Image, ImageOps


SHEEP_DIR = "assets/sprites/units/sheep"
SOURCE_DIR = os.path.join(SHEEP_DIR, "source")
CANVAS_SIZE = (128, 128)
# Background is uniform gray/white in the 235-254 range with near-equal channels.
# Sheep wool is light but has color variation (different R/G/B values, spread > 10).
# Use uniformity check (low spread) to distinguish background from wool.
BG_MIN = 235  # minimum channel value to consider as potential background
BG_MAX_SPREAD = 6  # max difference between channels for uniform background


def remove_background(img: Image.Image) -> Image.Image:
    """Convert uniform near-white pixels to transparent, returning RGBA image.

    Background pixels are identified as those where ALL channels are above
    BG_MIN and the spread between min/max channel is <= BG_MAX_SPREAD
    (i.e., uniformly gray/white). This preserves light-colored sheep wool
    which has visible color variation across channels.
    """
    img = img.convert("RGBA")
    pixels = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if (r >= BG_MIN and g >= BG_MIN and b >= BG_MIN
                    and max(r, g, b) - min(r, g, b) <= BG_MAX_SPREAD):
                pixels[x, y] = (0, 0, 0, 0)
    return img


def content_bbox(img: Image.Image):
    """Return bounding box of non-transparent content, or None if empty."""
    # getbbox() on the alpha channel
    alpha = img.split()[3]
    return alpha.getbbox()


def clean_resize_halo(img: Image.Image) -> Image.Image:
    """Remove semi-transparent uniform gray pixels created by LANCZOS blending.

    When LANCZOS resamples transparent/opaque boundaries, it creates semi-
    transparent pixels blending background gray with transparent black.
    Real sheep wool edges have color channel variation (spread > 6).
    """
    pixels = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if a == 0:
                continue
            spread = max(r, g, b) - min(r, g, b)
            # Semi-transparent uniform gray = LANCZOS halo artifact
            if 0 < a < 255 and spread <= BG_MAX_SPREAD:
                pixels[x, y] = (0, 0, 0, 0)
            # Fully opaque uniform near-white that survived removal
            elif a == 255 and r >= BG_MIN and g >= BG_MIN and b >= BG_MIN and spread <= BG_MAX_SPREAD:
                pixels[x, y] = (0, 0, 0, 0)
    return img


def crop_and_place(img: Image.Image, canvas_size: tuple = CANVAS_SIZE) -> Image.Image:
    """Crop to content bounding box, scale to fit, then center on canvas."""
    bbox = content_bbox(img)
    if bbox is None:
        # Empty frame — return blank canvas
        return Image.new("RGBA", canvas_size, (0, 0, 0, 0))

    cropped = img.crop(bbox)
    cw, ch = cropped.size

    # Scale down to fit within canvas with some padding (90% of canvas)
    max_w = int(canvas_size[0] * 0.90)
    max_h = int(canvas_size[1] * 0.90)
    scale = min(max_w / cw, max_h / ch)
    if scale < 1.0:
        new_w = max(1, int(cw * scale))
        new_h = max(1, int(ch * scale))
        cropped = cropped.resize((new_w, new_h), Image.LANCZOS)
        cropped = clean_resize_halo(cropped)
        cw, ch = cropped.size

    canvas = Image.new("RGBA", canvas_size, (0, 0, 0, 0))

    # Center on canvas
    ox = (canvas_size[0] - cw) // 2
    oy = (canvas_size[1] - ch) // 2
    canvas.paste(cropped, (ox, oy), cropped)
    return canvas


def split_2x2(sheet_path: str) -> list:
    """Split a 2x2 spritesheet into 4 cells [TL, TR, BL, BR]."""
    sheet = Image.open(sheet_path)
    w, h = sheet.size
    hw, hh = w // 2, h // 2
    cells = [
        sheet.crop((0, 0, hw, hh)),       # top-left
        sheet.crop((hw, 0, w, hh)),        # top-right
        sheet.crop((0, hh, hw, h)),        # bottom-left
        sheet.crop((hw, hh, w, h)),        # bottom-right
    ]
    return cells


def mirror_h(img: Image.Image) -> Image.Image:
    """Horizontally mirror an image."""
    return ImageOps.mirror(img)


def process_cell(cell: Image.Image) -> Image.Image:
    """Remove background from cell, crop, and place on canvas."""
    rgba = remove_background(cell)
    return crop_and_place(rgba)


def main():
    # Verify we're in the project root
    if not os.path.isdir(SOURCE_DIR):
        print(f"Error: {SOURCE_DIR} not found. Run from project root.", file=sys.stderr)
        sys.exit(1)

    sprites = []  # manifest entries
    output_dir = SHEEP_DIR

    # ── IDLE ANIMATION ──────────────────────────────────────────────
    idle_sheet = os.path.join(SOURCE_DIR, "sheep_idle_spritesheet_04.png")
    cells = split_2x2(idle_sheet)
    # TL=s, TR=se, BL=w, BR=ne
    idle_map = {
        "s": cells[0],
        "se": cells[1],
        "w": cells[2],
        "ne": cells[3],
    }

    # Process direct idle frames
    idle_processed = {}
    for direction, cell in idle_map.items():
        frame = process_cell(cell)
        idle_processed[direction] = frame
        fname = f"sheep_idle_{direction}_01.png"
        frame.save(os.path.join(output_dir, fname))
        sprites.append({
            "filename": fname,
            "animation": "idle",
            "direction": direction,
            "frame": 1,
        })

    # Generate mirrors for idle
    mirror_pairs_idle = [
        ("se", "sw"),   # se mirrors to sw
        ("w", "e"),     # w mirrors to e
        ("ne", "nw"),   # ne mirrors to nw
    ]
    for src_dir, dst_dir in mirror_pairs_idle:
        src_frame = idle_processed[src_dir]
        mirrored = mirror_h(src_frame)
        fname = f"sheep_idle_{dst_dir}_01.png"
        src_fname = f"sheep_idle_{src_dir}_01.png"
        mirrored.save(os.path.join(output_dir, fname))
        sprites.append({
            "filename": fname,
            "animation": "idle",
            "direction": dst_dir,
            "frame": 1,
            "mirrored_from": src_fname,
        })

    # Idle north: use the ne frame (partial rear view)
    n_idle = idle_processed["ne"]
    fname = "sheep_idle_n_01.png"
    n_idle.save(os.path.join(output_dir, fname))
    sprites.append({
        "filename": fname,
        "animation": "idle",
        "direction": "n",
        "frame": 1,
    })

    # ── WALK ANIMATION ──────────────────────────────────────────────
    v1_sheet = os.path.join(SOURCE_DIR, "sheep_walking_spritesheet_04_v1.png")
    v2_sheet = os.path.join(SOURCE_DIR, "sheep_walking_spritesheet_04_v2.png")
    north_sheet = os.path.join(SOURCE_DIR, "sheep_walking_north_01.png")

    v1_cells = split_2x2(v1_sheet)  # TL, TR, BL, BR
    v2_cells = split_2x2(v2_sheet)  # TL, TR, BL, BR

    # West-facing walk cycle (4 frames):
    #   walk_a: v1 BL (contact)
    #   walk_b: v2 TL (passing)
    #   walk_c: v2 BL (full extension)
    #   walk_d: v1 BR (recovery)
    walk_w_cells = {
        "walk_a": v1_cells[2],  # v1 bottom-left
        "walk_b": v2_cells[0],  # v2 top-left
        "walk_c": v2_cells[2],  # v2 bottom-left
        "walk_d": v1_cells[3],  # v1 bottom-right
    }

    walk_w_processed = {}
    for anim, cell in walk_w_cells.items():
        frame = process_cell(cell)
        walk_w_processed[anim] = frame
        fname = f"sheep_{anim}_w_01.png"
        frame.save(os.path.join(output_dir, fname))
        sprites.append({
            "filename": fname,
            "animation": anim,
            "direction": "w",
            "frame": 1,
        })

    # East-facing: mirror west
    for anim in ["walk_a", "walk_b", "walk_c", "walk_d"]:
        mirrored = mirror_h(walk_w_processed[anim])
        fname = f"sheep_{anim}_e_01.png"
        src_fname = f"sheep_{anim}_w_01.png"
        mirrored.save(os.path.join(output_dir, fname))
        sprites.append({
            "filename": fname,
            "animation": anim,
            "direction": "e",
            "frame": 1,
            "mirrored_from": src_fname,
        })

    # South-facing walk: v1 TL for all 4 walk phases (single pose)
    s_walk = process_cell(v1_cells[0])
    for anim in ["walk_a", "walk_b", "walk_c", "walk_d"]:
        fname = f"sheep_{anim}_s_01.png"
        s_walk.save(os.path.join(output_dir, fname))
        sprites.append({
            "filename": fname,
            "animation": anim,
            "direction": "s",
            "frame": 1,
        })

    # North-facing walk: single frame from north sheet
    north_img = Image.open(north_sheet)
    n_walk = process_cell(north_img)
    for anim in ["walk_a", "walk_b", "walk_c", "walk_d"]:
        fname = f"sheep_{anim}_n_01.png"
        n_walk.save(os.path.join(output_dir, fname))
        sprites.append({
            "filename": fname,
            "animation": anim,
            "direction": "n",
            "frame": 1,
        })

    # SE/SW walk: use angled frames from v1/v2
    # v1 TR = right-facing walk mid-stride (east-ish / SE)
    # v2 TR = right-facing stride (east-ish / SE)
    # For SE we use v1 TR and v2 TR as 2 unique poses, repeat for 4 frames
    se_cells = {
        "walk_a": v1_cells[1],  # v1 top-right
        "walk_b": v2_cells[1],  # v2 top-right
        "walk_c": v1_cells[1],  # repeat v1 TR
        "walk_d": v2_cells[3],  # v2 bottom-right
    }

    se_processed = {}
    for anim, cell in se_cells.items():
        frame = process_cell(cell)
        se_processed[anim] = frame
        fname = f"sheep_{anim}_se_01.png"
        frame.save(os.path.join(output_dir, fname))
        sprites.append({
            "filename": fname,
            "animation": anim,
            "direction": "se",
            "frame": 1,
        })

    # SW walk: mirror SE
    for anim in ["walk_a", "walk_b", "walk_c", "walk_d"]:
        mirrored = mirror_h(se_processed[anim])
        fname = f"sheep_{anim}_sw_01.png"
        src_fname = f"sheep_{anim}_se_01.png"
        mirrored.save(os.path.join(output_dir, fname))
        sprites.append({
            "filename": fname,
            "animation": anim,
            "direction": "sw",
            "frame": 1,
            "mirrored_from": src_fname,
        })

    # NE walk: use the ne idle frame as base (limited source material)
    # Use the v1 BR (recovery, rear-right) for all NE walk frames
    ne_walk = process_cell(v1_cells[3])
    for anim in ["walk_a", "walk_b", "walk_c", "walk_d"]:
        fname = f"sheep_{anim}_ne_01.png"
        ne_walk.save(os.path.join(output_dir, fname))
        sprites.append({
            "filename": fname,
            "animation": anim,
            "direction": "ne",
            "frame": 1,
        })

    # NW walk: mirror NE
    nw_walk = mirror_h(ne_walk)
    for anim in ["walk_a", "walk_b", "walk_c", "walk_d"]:
        fname = f"sheep_{anim}_nw_01.png"
        src_fname = f"sheep_{anim}_ne_01.png"
        nw_walk.save(os.path.join(output_dir, fname))
        sprites.append({
            "filename": fname,
            "animation": anim,
            "direction": "nw",
            "frame": 1,
            "mirrored_from": src_fname,
        })

    # ── MANIFEST ────────────────────────────────────────────────────
    # Sort sprites by animation then direction order
    dir_order = ["s", "se", "e", "ne", "n", "nw", "w", "sw"]
    anim_order = ["idle", "walk_a", "walk_b", "walk_c", "walk_d"]

    def sort_key(entry):
        a = anim_order.index(entry["animation"]) if entry["animation"] in anim_order else 99
        d = dir_order.index(entry["direction"]) if entry["direction"] in dir_order else 99
        return (a, d, entry["frame"])

    sprites.sort(key=sort_key)

    manifest = {
        "canvas_size": list(CANVAS_SIZE),
        "directions": dir_order,
        "animations": anim_order,
        "sprites": sprites,
    }

    manifest_path = os.path.join(output_dir, "manifest.json")
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")

    print(f"Generated {len(sprites)} sprite entries")
    print(f"Manifest written to {manifest_path}")

    # List generated files
    generated = set(e["filename"] for e in sprites)
    print(f"\nGenerated {len(generated)} unique PNG files")


if __name__ == "__main__":
    main()

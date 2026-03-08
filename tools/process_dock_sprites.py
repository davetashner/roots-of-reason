#!/usr/bin/env python3
"""Process dock construction sequence sprites.

Removes the near-white background, resizes to 384x256 (3x3 footprint),
restores magenta player color, and stitches into a horizontal strip.
"""

from PIL import Image


FRAME_W = 384
FRAME_H = 256
NUM_FRAMES = 4
BG_THRESHOLD = 230  # pixels brighter than this in all channels are background candidates
TOLERANCE = 30  # flood fill color tolerance


def _flood_fill_transparent(img: Image.Image, start: tuple[int, int], tolerance: int) -> Image.Image:
    """Flood fill from start pixel, making connected similar-color pixels transparent."""
    rgba = img.convert("RGBA")
    pixels = rgba.load()
    w, h = rgba.size
    sr, sg, sb = pixels[start[0], start[1]][:3]

    visited = set()
    stack = [start]

    while stack:
        x, y = stack.pop()
        if (x, y) in visited:
            continue
        if x < 0 or x >= w or y < 0 or y >= h:
            continue
        r, g, b, a = pixels[x, y]
        if abs(r - sr) <= tolerance and abs(g - sg) <= tolerance and abs(b - sb) <= tolerance:
            visited.add((x, y))
            pixels[x, y] = (0, 0, 0, 0)
            stack.extend([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])
        else:
            visited.add((x, y))

    return rgba


def remove_background(img: Image.Image) -> Image.Image:
    """Remove near-white background by flood filling from all four corners."""
    rgba = img.convert("RGBA")

    # Flood fill from each corner
    w, h = rgba.size
    corners = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]
    for corner in corners:
        r, g, b = rgba.getpixel(corner)[:3]
        # Only flood fill if the corner is light enough to be background
        if r > BG_THRESHOLD and g > BG_THRESHOLD and b > BG_THRESHOLD:
            rgba = _flood_fill_transparent(rgba, corner, TOLERANCE)

    # Also flood fill from edge midpoints in case corners aren't enough
    edge_mids = [(w // 2, 0), (w // 2, h - 1), (0, h // 2), (w - 1, h // 2)]
    for pt in edge_mids:
        r, g, b, a = rgba.getpixel(pt)
        if a > 0 and r > BG_THRESHOLD and g > BG_THRESHOLD and b > BG_THRESHOLD:
            rgba = _flood_fill_transparent(rgba, pt, TOLERANCE)

    return rgba


def restore_magenta(img: Image.Image) -> Image.Image:
    """Snap blended pink/purple pixels back to pure magenta after scaling."""
    pixels = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if a > 128:
                if r > 150 and g < 100 and b > 150:
                    pixels[x, y] = (255, 0, 255, 255)
                elif r > 180 and g < 60 and b > 80:
                    pixels[x, y] = (255, 0, 255, 255)
    return img


def process_dock_sprites() -> None:
    base = "assets/sprites/buildings/placeholder"
    frames = []

    for i in range(1, NUM_FRAMES + 1):
        path = f"{base}/dock_{i:02d}.png"
        print(f"Processing {path}...")
        img = Image.open(path)

        # Remove background
        img = remove_background(img)

        # Resize to target canvas, preserving aspect ratio and centering
        img.thumbnail((FRAME_W, FRAME_H), Image.LANCZOS)
        canvas = Image.new("RGBA", (FRAME_W, FRAME_H), (0, 0, 0, 0))
        offset_x = (FRAME_W - img.width) // 2
        offset_y = FRAME_H - img.height  # anchor to bottom
        canvas.paste(img, (offset_x, offset_y), img)

        # Restore magenta player color
        canvas = restore_magenta(canvas)

        frames.append(canvas)

    # Stitch into horizontal strip
    strip_w = FRAME_W * NUM_FRAMES
    strip = Image.new("RGBA", (strip_w, FRAME_H), (0, 0, 0, 0))
    for i, frame in enumerate(frames):
        strip.paste(frame, (i * FRAME_W, 0))

    out_path = f"{base}/dock_building_sequence.png"
    strip.save(out_path)
    print(f"Saved {out_path} ({strip_w}x{FRAME_H})")


if __name__ == "__main__":
    process_dock_sprites()

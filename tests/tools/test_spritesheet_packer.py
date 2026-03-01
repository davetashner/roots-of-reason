"""Tests for tools/spritesheet_packer.py — atlas spritesheet generation."""
from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

# Ensure tools/ is importable
TOOLS_DIR = Path(__file__).resolve().parent.parent.parent / "tools"
sys.path.insert(0, str(TOOLS_DIR))

import spritesheet_packer as sp

try:
    from PIL import Image as _PIL_Image
    HAS_PIL = True
except ImportError:
    HAS_PIL = False

requires_pil = pytest.mark.skipif(not HAS_PIL, reason="Pillow not installed")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def make_frame_png(path, width=128, height=128, color=(100, 50, 50, 255)):
    """Create a minimal PNG frame."""
    from PIL import Image
    img = Image.new("RGBA", (width, height), color)
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, "PNG")


def make_test_manifest(sprite_dir, animations=None, directions=None, frames_per_anim=None):
    """Create a manifest.json with test frame entries and corresponding PNGs."""
    if animations is None:
        animations = ["idle", "walk"]
    if directions is None:
        directions = ["s", "n"]
    if frames_per_anim is None:
        frames_per_anim = {"idle": 2, "walk": 3}

    sprites = []
    for anim in animations:
        n_frames = frames_per_anim.get(anim, 2)
        for d in directions:
            for f in range(1, n_frames + 1):
                filename = f"test_{anim}_{d}_{f:02d}.png"
                sprites.append({
                    "filename": filename,
                    "animation": anim,
                    "direction": d,
                    "frame": f,
                })

    manifest = {
        "canvas_size": [128, 128],
        "directions": directions,
        "animations": animations,
        "sprites": sprites,
    }

    sprite_dir.mkdir(parents=True, exist_ok=True)
    with open(sprite_dir / "manifest.json", "w") as fp:
        json.dump(manifest, fp, indent=2)

    return manifest, sprites


# ---------------------------------------------------------------------------
# Unit tests — compute_grid
# ---------------------------------------------------------------------------

class TestComputeGrid:
    def test_small_frame_count_fits_one_sheet(self):
        cols, rows, sheets = sp.compute_grid(10, 128, 128, 1536, 1536)
        assert sheets == 1
        assert cols * rows >= 10

    def test_single_frame(self):
        cols, rows, sheets = sp.compute_grid(1, 128, 128, 1536, 1536)
        assert sheets == 1
        assert cols >= 1
        assert rows >= 1

    def test_large_frame_count_needs_multiple_sheets(self):
        # 128px frames in 256x256 atlas → max 4 per sheet
        cols, rows, sheets = sp.compute_grid(10, 128, 128, 256, 256)
        assert cols == 2
        assert rows == 2
        assert sheets == 3  # ceil(10/4)

    def test_respects_max_dimensions(self):
        cols, rows, sheets = sp.compute_grid(100, 128, 128, 512, 512)
        assert cols <= 512 // 128
        assert rows <= 512 // 128


# ---------------------------------------------------------------------------
# Integration tests — pack_spritesheet
# ---------------------------------------------------------------------------

@requires_pil
class TestPackSpritesheet:
    def test_dry_run_produces_no_files(self, tmp_path):
        sprite_dir = tmp_path / "test_unit"
        manifest, sprites = make_test_manifest(sprite_dir)

        atlas, paths = sp.pack_spritesheet(
            sprite_dir, manifest, 1536, 1536, dry_run=True
        )

        assert atlas is not None
        assert len(atlas["sheets"]) >= 1
        # No files written
        assert not (sprite_dir / "spritesheet_00.png").exists()

    def test_packs_frames_into_atlas(self, tmp_path):
        sprite_dir = tmp_path / "test_unit"
        manifest, sprites = make_test_manifest(sprite_dir)

        # Create actual PNG frames
        for entry in sprites:
            make_frame_png(sprite_dir / entry["filename"])

        atlas, paths = sp.pack_spritesheet(
            sprite_dir, manifest, 1536, 1536, dry_run=False
        )

        assert atlas is not None
        assert len(paths) == 1
        assert paths[0].exists()

        # Verify atlas metadata
        sheet = atlas["sheets"][0]
        assert len(sheet["frames"]) == len(sprites)
        assert sheet["width"] > 0
        assert sheet["height"] > 0

    def test_frame_rects_are_grid_aligned(self, tmp_path):
        sprite_dir = tmp_path / "test_unit"
        manifest, sprites = make_test_manifest(sprite_dir)
        for entry in sprites:
            make_frame_png(sprite_dir / entry["filename"])

        atlas, _ = sp.pack_spritesheet(
            sprite_dir, manifest, 1536, 1536, dry_run=False
        )

        for frame in atlas["sheets"][0]["frames"]:
            assert frame["x"] % 128 == 0
            assert frame["y"] % 128 == 0
            assert frame["w"] == 128
            assert frame["h"] == 128

    def test_spritesheet_dimensions_match_grid(self, tmp_path):
        sprite_dir = tmp_path / "test_unit"
        manifest, sprites = make_test_manifest(sprite_dir)
        for entry in sprites:
            make_frame_png(sprite_dir / entry["filename"])

        atlas, paths = sp.pack_spritesheet(
            sprite_dir, manifest, 1536, 1536, dry_run=False
        )

        from PIL import Image
        img = Image.open(paths[0])
        sheet = atlas["sheets"][0]
        assert img.size == (sheet["width"], sheet["height"])

    def test_empty_manifest_returns_none(self, tmp_path):
        sprite_dir = tmp_path / "test_unit"
        sprite_dir.mkdir(parents=True)
        manifest = {"canvas_size": [128, 128], "sprites": []}

        atlas, paths = sp.pack_spritesheet(
            sprite_dir, manifest, 1536, 1536, dry_run=False
        )

        assert atlas is None

    def test_magenta_pixels_preserved(self, tmp_path):
        """Magenta mask pixels in frames survive packing."""
        sprite_dir = tmp_path / "test_unit"
        manifest, sprites = make_test_manifest(
            sprite_dir, animations=["idle"], directions=["s"],
            frames_per_anim={"idle": 1}
        )
        # Create frame with magenta content
        make_frame_png(
            sprite_dir / sprites[0]["filename"],
            color=(255, 0, 255, 255)
        )

        atlas, paths = sp.pack_spritesheet(
            sprite_dir, manifest, 1536, 1536, dry_run=False
        )

        from PIL import Image
        img = Image.open(paths[0])
        pixel = img.getpixel((64, 64))  # Center of first frame
        assert pixel == (255, 0, 255, 255)


# ---------------------------------------------------------------------------
# Integration tests — write_atlas_json
# ---------------------------------------------------------------------------

class TestWriteAtlasJson:
    def test_writes_valid_json(self, tmp_path):
        atlas = {
            "canvas_size": [128, 128],
            "sheets": [{"filename": "test.png", "frames": []}],
        }
        path = sp.write_atlas_json(tmp_path, atlas)
        assert path.exists()
        with open(path) as f:
            loaded = json.load(f)
        assert loaded == atlas

    def test_dry_run_writes_nothing(self, tmp_path):
        atlas = {"canvas_size": [128, 128], "sheets": []}
        path = sp.write_atlas_json(tmp_path, atlas, dry_run=True)
        assert not path.exists()


# ---------------------------------------------------------------------------
# CLI test — main()
# ---------------------------------------------------------------------------

@requires_pil
class TestMain:
    def test_missing_sprite_dir_returns_error(self, tmp_path):
        result = sp.main(["nonexistent", "--sprite-dir", str(tmp_path / "nope")])
        assert result == 1

    def test_missing_manifest_returns_error(self, tmp_path):
        empty_dir = tmp_path / "empty"
        empty_dir.mkdir()
        result = sp.main(["test", "--sprite-dir", str(empty_dir)])
        assert result == 1

    def test_full_pipeline(self, tmp_path):
        sprite_dir = tmp_path / "archer"
        manifest, sprites = make_test_manifest(sprite_dir)
        for entry in sprites:
            make_frame_png(sprite_dir / entry["filename"])

        result = sp.main(["archer", "--sprite-dir", str(sprite_dir)])

        assert result == 0
        assert (sprite_dir / "atlas.json").exists()
        assert (sprite_dir / "spritesheet_00.png").exists()

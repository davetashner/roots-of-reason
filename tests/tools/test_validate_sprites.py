"""Tests for tools/validate_sprites.py — rendered sprite validation."""
from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

import pytest

# Ensure tools/ is importable
TOOLS_DIR = Path(__file__).resolve().parent.parent.parent / "tools"
sys.path.insert(0, str(TOOLS_DIR))

import validate_sprites as vs


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def make_png_header(path, width=128, height=128):
    """Create a minimal valid PNG file (header only, no real image data)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    signature = b"\x89PNG\r\n\x1a\n"
    ihdr_data = struct.pack(">II", width, height)
    # Minimal IHDR: length(4) + "IHDR"(4) + width(4) + height(4)
    ihdr_chunk = struct.pack(">I", 13) + b"IHDR" + ihdr_data
    with open(path, "wb") as f:
        f.write(signature + ihdr_chunk)


def make_unit_sprites(sprite_dir, unit_name, animations=None, directions=None,
                      frame_counts=None, create_files=True):
    """Create a manifest.json and optional PNG stubs for a unit."""
    if animations is None:
        animations = ["idle", "walk", "attack", "death"]
    if directions is None:
        directions = vs.REQUIRED_DIRECTIONS
    if frame_counts is None:
        frame_counts = {"idle": 4, "walk": 8, "attack": 6, "death": 6}

    sprites = []
    for anim in animations:
        n_frames = frame_counts.get(anim, 2)
        for d in directions:
            for f in range(1, n_frames + 1):
                filename = f"{unit_name}_{anim}_{d}_{f:02d}.png"
                sprites.append({
                    "filename": filename,
                    "animation": anim,
                    "direction": d,
                    "frame": f,
                })
                if create_files:
                    make_png_header(sprite_dir / filename)

    manifest = {
        "canvas_size": [128, 128],
        "directions": directions,
        "animations": animations,
        "sprites": sprites,
    }
    sprite_dir.mkdir(parents=True, exist_ok=True)
    with open(sprite_dir / "manifest.json", "w") as fp:
        json.dump(manifest, fp, indent=2)

    return manifest


# ---------------------------------------------------------------------------
# Tests — validate_manifest
# ---------------------------------------------------------------------------

class TestValidateManifest:
    def test_valid_unit_passes(self, tmp_path):
        unit_dir = tmp_path / "archer"
        make_unit_sprites(unit_dir, "archer")
        name, errors, warnings = vs.validate_manifest(
            unit_dir, vs.DEFAULT_FRAME_COUNTS
        )
        assert name == "archer"
        assert errors == []
        assert warnings == []

    def test_missing_manifest_is_error(self, tmp_path):
        unit_dir = tmp_path / "nounit"
        unit_dir.mkdir()
        name, errors, warnings = vs.validate_manifest(
            unit_dir, vs.DEFAULT_FRAME_COUNTS
        )
        assert len(errors) == 1
        assert "Missing manifest.json" in errors[0]

    def test_missing_direction_is_error(self, tmp_path):
        unit_dir = tmp_path / "archer"
        make_unit_sprites(unit_dir, "archer", directions=["s", "n"])
        name, errors, warnings = vs.validate_manifest(
            unit_dir, vs.DEFAULT_FRAME_COUNTS
        )
        assert any("missing directions" in e for e in errors)

    def test_missing_animation_is_warning(self, tmp_path):
        unit_dir = tmp_path / "archer"
        make_unit_sprites(
            unit_dir, "archer",
            animations=["idle", "walk"],
            frame_counts={"idle": 4, "walk": 8},
        )
        name, errors, warnings = vs.validate_manifest(
            unit_dir, vs.DEFAULT_FRAME_COUNTS
        )
        assert any("missing required animation 'attack'" in w for w in warnings)
        assert any("missing required animation 'death'" in w for w in warnings)

    def test_wrong_frame_count_is_warning(self, tmp_path):
        unit_dir = tmp_path / "archer"
        make_unit_sprites(
            unit_dir, "archer",
            frame_counts={"idle": 2, "walk": 8, "attack": 6, "death": 6},
        )
        name, errors, warnings = vs.validate_manifest(
            unit_dir, vs.DEFAULT_FRAME_COUNTS
        )
        assert any("idle" in w and "2 frames" in w for w in warnings)

    def test_wrong_dimensions_is_error(self, tmp_path):
        unit_dir = tmp_path / "archer"
        make_unit_sprites(unit_dir, "archer", create_files=False)
        # Create one file with wrong dimensions
        sprites = json.loads((unit_dir / "manifest.json").read_text())["sprites"]
        for s in sprites:
            make_png_header(unit_dir / s["filename"])
        # Overwrite first file with wrong dims
        make_png_header(unit_dir / sprites[0]["filename"], width=256, height=256)
        name, errors, warnings = vs.validate_manifest(
            unit_dir, vs.DEFAULT_FRAME_COUNTS
        )
        assert any("256x256" in e for e in errors)

    def test_missing_files_warned(self, tmp_path):
        unit_dir = tmp_path / "archer"
        make_unit_sprites(unit_dir, "archer", create_files=False)
        name, errors, warnings = vs.validate_manifest(
            unit_dir, vs.DEFAULT_FRAME_COUNTS
        )
        assert any("frame files missing" in w for w in warnings)


# ---------------------------------------------------------------------------
# Tests — validate_atlas
# ---------------------------------------------------------------------------

class TestValidateAtlas:
    def test_valid_atlas_passes(self, tmp_path):
        unit_dir = tmp_path / "archer"
        manifest = make_unit_sprites(unit_dir, "archer")
        atlas = {
            "canvas_size": [128, 128],
            "sheets": [{
                "filename": "spritesheet_00.png",
                "frames": [
                    {"filename": s["filename"]} for s in manifest["sprites"]
                ],
            }],
        }
        # Create the spritesheet file
        make_png_header(unit_dir / "spritesheet_00.png", 1280, 1152)
        atlas_path = unit_dir / "atlas.json"
        with open(atlas_path, "w") as f:
            json.dump(atlas, f)

        errors = vs.validate_atlas(unit_dir, manifest, atlas_path)
        assert errors == []

    def test_canvas_size_mismatch_is_error(self, tmp_path):
        unit_dir = tmp_path / "archer"
        unit_dir.mkdir(parents=True)
        manifest = {"canvas_size": [128, 128], "sprites": []}
        atlas = {"canvas_size": [64, 64], "sheets": []}
        atlas_path = unit_dir / "atlas.json"
        with open(atlas_path, "w") as f:
            json.dump(atlas, f)

        errors = vs.validate_atlas(unit_dir, manifest, atlas_path)
        assert any("canvas_size" in e for e in errors)

    def test_missing_sheet_file_is_error(self, tmp_path):
        unit_dir = tmp_path / "archer"
        unit_dir.mkdir(parents=True)
        manifest = {"canvas_size": [128, 128], "sprites": []}
        atlas = {
            "canvas_size": [128, 128],
            "sheets": [{"filename": "missing.png", "frames": []}],
        }
        atlas_path = unit_dir / "atlas.json"
        with open(atlas_path, "w") as f:
            json.dump(atlas, f)

        errors = vs.validate_atlas(unit_dir, manifest, atlas_path)
        assert any("missing sheet" in e for e in errors)


# ---------------------------------------------------------------------------
# Tests — find_unit_dirs
# ---------------------------------------------------------------------------

class TestFindUnitDirs:
    def test_finds_dirs_with_manifests(self, tmp_path):
        make_unit_sprites(tmp_path / "archer", "archer")
        make_unit_sprites(tmp_path / "villager", "villager")
        (tmp_path / "empty").mkdir()  # no manifest

        dirs = vs.find_unit_dirs(tmp_path)
        names = [d.name for d in dirs]
        assert "archer" in names
        assert "villager" in names
        assert "empty" not in names

    def test_skips_placeholder_dir(self, tmp_path):
        (tmp_path / "placeholder").mkdir()
        (tmp_path / "placeholder" / "manifest.json").write_text("{}")

        dirs = vs.find_unit_dirs(tmp_path)
        assert len(dirs) == 0

    def test_filters_specific_unit(self, tmp_path):
        make_unit_sprites(tmp_path / "archer", "archer")
        make_unit_sprites(tmp_path / "villager", "villager")

        dirs = vs.find_unit_dirs(tmp_path, specific_unit="archer")
        assert len(dirs) == 1
        assert dirs[0].name == "archer"


# ---------------------------------------------------------------------------
# Tests — CLI
# ---------------------------------------------------------------------------

class TestMain:
    def test_nonexistent_unit_returns_error(self):
        result = vs.main(["--unit", "nonexistent", "--sprites-dir", "/tmp/empty"])
        assert result == 1

    def test_valid_unit_returns_success(self, tmp_path):
        unit_dir = tmp_path / "archer"
        make_unit_sprites(unit_dir, "archer")
        result = vs.main(["--sprites-dir", str(tmp_path)])
        assert result == 0

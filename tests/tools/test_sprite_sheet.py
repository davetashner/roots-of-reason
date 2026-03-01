"""Tests for tools/sprite_sheet.py — sprite animation GIF and contact sheet generator."""
from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

# Ensure tools/ is importable
TOOLS_DIR = Path(__file__).resolve().parent.parent.parent / "tools"
sys.path.insert(0, str(TOOLS_DIR))

import sprite_sheet as ss

try:
    from PIL import Image as _PIL_Image

    HAS_PIL = True
except ImportError:
    HAS_PIL = False

requires_pil = pytest.mark.skipif(not HAS_PIL, reason="Pillow not installed")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def make_variant(tmp_path: Path, variant: str, animations: dict) -> Path:
    """Create a fake variant directory with manifest and PNG frames.

    animations: {anim_name: {direction: frame_count}}
    """
    variant_dir = tmp_path / "assets" / "sprites" / "units" / variant
    variant_dir.mkdir(parents=True)

    canvas_w, canvas_h = 64, 64
    sprites = []
    for anim, dirs in animations.items():
        for direction, count in dirs.items():
            for frame in range(1, count + 1):
                fname = f"{variant}_{anim}_{direction}_{frame:02d}.png"
                sprites.append(
                    {
                        "filename": fname,
                        "animation": anim,
                        "direction": direction,
                        "frame": frame,
                        "source_bbox": [0, 0, 64, 64],
                    }
                )
                # Create a small PNG with distinct color per frame
                from PIL import Image

                c = 50 + frame * 40
                img = Image.new("RGBA", (48, 48), (c, 150, 200, 255))
                img.save(variant_dir / fname, "PNG")

    manifest = {
        "source": f"{variant}_spritesheet.png",
        "canvas_size": [canvas_w, canvas_h],
        "directions": ["s", "se", "e", "ne", "n", "nw", "w", "sw"],
        "animations": list(animations.keys()),
        "sprites": sprites,
    }
    (variant_dir / "manifest.json").write_text(json.dumps(manifest))
    return variant_dir


# ---------------------------------------------------------------------------
# Unit tests
# ---------------------------------------------------------------------------


class TestGetFrames:
    def test_filters_by_animation_and_direction(self):
        manifest = {
            "sprites": [
                {"animation": "walk", "direction": "s", "frame": 2},
                {"animation": "walk", "direction": "s", "frame": 1},
                {"animation": "idle", "direction": "s", "frame": 1},
                {"animation": "walk", "direction": "n", "frame": 1},
            ]
        }
        result = ss.get_frames(manifest, "walk", "s")
        assert len(result) == 2
        assert result[0]["frame"] == 1
        assert result[1]["frame"] == 2

    def test_empty_for_missing_animation(self):
        manifest = {"sprites": [{"animation": "idle", "direction": "s", "frame": 1}]}
        assert ss.get_frames(manifest, "walk", "s") == []


class TestGetAnimations:
    def test_preserves_order(self):
        manifest = {
            "sprites": [
                {"animation": "idle", "direction": "s", "frame": 1},
                {"animation": "walk", "direction": "s", "frame": 1},
                {"animation": "idle", "direction": "n", "frame": 1},
            ]
        }
        assert ss.get_animations(manifest) == ["idle", "walk"]


class TestGetDirections:
    def test_canonical_order(self):
        manifest = {
            "sprites": [
                {"animation": "walk", "direction": "n", "frame": 1},
                {"animation": "walk", "direction": "s", "frame": 1},
                {"animation": "walk", "direction": "e", "frame": 1},
            ]
        }
        assert ss.get_directions(manifest) == ["s", "e", "n"]


# ---------------------------------------------------------------------------
# Integration tests (require PIL)
# ---------------------------------------------------------------------------


@requires_pil
class TestBuildStrip:
    def test_strip_dimensions(self, tmp_path):
        variant_dir = tmp_path / "variant"
        variant_dir.mkdir()
        from PIL import Image

        for i in range(1, 4):
            img = Image.new("RGBA", (48, 48), (100, 100, 100, 255))
            img.save(variant_dir / f"walk_s_{i:02d}.png", "PNG")

        frames = [
            {"filename": f"walk_s_{i:02d}.png", "frame": i} for i in range(1, 4)
        ]
        strip = ss.build_strip(variant_dir, frames, 64, 64)
        assert strip.width == 3 * 64
        assert strip.height == 64 + ss.LABEL_HEIGHT

    def test_empty_frames(self):
        strip = ss.build_strip(Path("/nonexistent"), [], 64, 64)
        assert strip.width == 64
        assert strip.height == 64 + ss.LABEL_HEIGHT


@requires_pil
class TestSaveGif:
    def test_creates_animated_gif(self, tmp_path):
        from PIL import Image

        frames = [
            Image.new("RGBA", (64, 64), (100, 0, 0, 255)),
            Image.new("RGBA", (64, 64), (0, 100, 0, 255)),
            Image.new("RGBA", (64, 64), (0, 0, 100, 255)),
        ]
        out_path = tmp_path / "test.gif"
        ss.save_gif(frames, out_path, frame_ms=200)
        assert out_path.is_file()

        gif = Image.open(out_path)
        assert gif.is_animated
        assert gif.n_frames == 3

    def test_empty_frames_no_crash(self, tmp_path):
        out_path = tmp_path / "empty.gif"
        ss.save_gif([], out_path)
        assert not out_path.exists()


@requires_pil
class TestGenerateGif:
    def test_multi_frame_produces_gif(self, tmp_path, monkeypatch):
        make_variant(tmp_path, "test_unit", {"walk": {"s": 4}})
        monkeypatch.setattr(ss, "SPRITES_DIR", tmp_path / "assets" / "sprites" / "units")
        monkeypatch.setattr(ss, "OUTPUT_DIR", tmp_path / "output")

        outputs = ss.generate_gif("test_unit", "walk", "s")
        assert len(outputs) == 1
        assert outputs[0].suffix == ".gif"
        assert outputs[0].is_file()

        from PIL import Image

        gif = Image.open(outputs[0])
        assert gif.is_animated
        assert gif.n_frames == 4

    def test_single_frame_produces_png(self, tmp_path, monkeypatch):
        make_variant(tmp_path, "test_unit", {"idle": {"s": 1}})
        monkeypatch.setattr(ss, "SPRITES_DIR", tmp_path / "assets" / "sprites" / "units")
        monkeypatch.setattr(ss, "OUTPUT_DIR", tmp_path / "output")

        outputs = ss.generate_gif("test_unit", "idle", "s")
        assert len(outputs) == 1
        assert outputs[0].suffix == ".png"

    def test_all_directions_produces_per_direction_gifs(self, tmp_path, monkeypatch):
        make_variant(
            tmp_path,
            "test_unit",
            {"walk": {"s": 3, "n": 3}},
        )
        monkeypatch.setattr(ss, "SPRITES_DIR", tmp_path / "assets" / "sprites" / "units")
        monkeypatch.setattr(ss, "OUTPUT_DIR", tmp_path / "output")

        outputs = ss.generate_gif("test_unit", "walk")
        assert len(outputs) == 2
        names = {p.name for p in outputs}
        assert "test_unit_walk_s.gif" in names
        assert "test_unit_walk_n.gif" in names


@requires_pil
class TestGenerateSheet:
    def test_single_direction(self, tmp_path, monkeypatch):
        make_variant(tmp_path, "test_unit", {"walk": {"s": 3}})
        monkeypatch.setattr(ss, "SPRITES_DIR", tmp_path / "assets" / "sprites" / "units")
        monkeypatch.setattr(ss, "OUTPUT_DIR", tmp_path / "output")

        outputs = ss.generate_sheet("test_unit", "walk", "s")
        assert len(outputs) == 1
        assert outputs[0].name == "test_unit_walk_s.png"
        assert outputs[0].is_file()

        from PIL import Image

        img = Image.open(outputs[0])
        assert img.width == 3 * 64  # 3 frames * 64px canvas

    def test_all_directions(self, tmp_path, monkeypatch):
        make_variant(
            tmp_path,
            "test_unit",
            {"walk": {"s": 2, "n": 2, "e": 1}},
        )
        monkeypatch.setattr(ss, "SPRITES_DIR", tmp_path / "assets" / "sprites" / "units")
        monkeypatch.setattr(ss, "OUTPUT_DIR", tmp_path / "output")

        outputs = ss.generate_sheet("test_unit", "walk")
        assert len(outputs) == 1
        assert outputs[0].name == "test_unit_walk.png"

        from PIL import Image

        img = Image.open(outputs[0])
        row_h = 64 + ss.LABEL_HEIGHT
        assert img.height == 3 * row_h  # 3 directions

    def test_all_animations(self, tmp_path, monkeypatch):
        make_variant(
            tmp_path,
            "test_unit",
            {"idle": {"s": 1}, "walk": {"s": 2}},
        )
        monkeypatch.setattr(ss, "SPRITES_DIR", tmp_path / "assets" / "sprites" / "units")
        monkeypatch.setattr(ss, "OUTPUT_DIR", tmp_path / "output")

        outputs = ss.generate_sheet("test_unit")
        assert len(outputs) == 2
        names = {p.name for p in outputs}
        assert "test_unit_idle.png" in names
        assert "test_unit_walk.png" in names


@requires_pil
class TestCLI:
    def test_invalid_variant(self, tmp_path, monkeypatch):
        monkeypatch.setattr(ss, "SPRITES_DIR", tmp_path / "assets" / "sprites" / "units")
        assert ss.main(["nonexistent"]) == 1

    def test_default_generates_gif(self, tmp_path, monkeypatch):
        make_variant(tmp_path, "test_unit", {"walk": {"s": 3}})
        monkeypatch.setattr(ss, "SPRITES_DIR", tmp_path / "assets" / "sprites" / "units")
        monkeypatch.setattr(ss, "OUTPUT_DIR", tmp_path / "output")

        assert ss.main(["test_unit", "walk", "s"]) == 0
        assert (tmp_path / "output" / "test_unit_walk_s.gif").is_file()

    def test_png_flag_generates_sheet(self, tmp_path, monkeypatch):
        make_variant(tmp_path, "test_unit", {"walk": {"s": 3}})
        monkeypatch.setattr(ss, "SPRITES_DIR", tmp_path / "assets" / "sprites" / "units")
        monkeypatch.setattr(ss, "OUTPUT_DIR", tmp_path / "output")

        assert ss.main(["test_unit", "walk", "s", "--png"]) == 0
        assert (tmp_path / "output" / "test_unit_walk_s.png").is_file()

    def test_speed_flag(self, tmp_path, monkeypatch):
        make_variant(tmp_path, "test_unit", {"walk": {"s": 3}})
        monkeypatch.setattr(ss, "SPRITES_DIR", tmp_path / "assets" / "sprites" / "units")
        monkeypatch.setattr(ss, "OUTPUT_DIR", tmp_path / "output")

        assert ss.main(["test_unit", "walk", "s", "--speed", "100"]) == 0
        assert (tmp_path / "output" / "test_unit_walk_s.gif").is_file()

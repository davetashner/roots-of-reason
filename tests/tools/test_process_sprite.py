"""Tests for tools/process_sprite.py — building sprite processor."""
from __future__ import annotations

import json
import struct
import sys
from pathlib import Path
from unittest import mock

import pytest

# Ensure tools/ is importable
TOOLS_DIR = Path(__file__).resolve().parent.parent.parent / "tools"
sys.path.insert(0, str(TOOLS_DIR))

import process_sprite as ps


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def make_png(path: Path, width: int, height: int, rgba_fill: tuple = (0, 0, 0, 0)) -> None:
    """Create a minimal valid PNG file with the given dimensions.

    Uses PIL to create a real PNG so process_sprite can open it.
    """
    from PIL import Image

    img = Image.new("RGBA", (width, height), rgba_fill)
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, "PNG")


def make_png_with_content(path: Path, width: int, height: int) -> None:
    """Create a PNG with some opaque content and a magenta region."""
    from PIL import Image

    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    # Draw a brown rectangle (building body) in the center
    for y in range(height // 4, 3 * height // 4):
        for x in range(width // 4, 3 * width // 4):
            img.putpixel((x, y), (139, 115, 85, 255))
    # Add a magenta flag region
    for y in range(height // 4, height // 4 + 20):
        for x in range(width // 2, width // 2 + 15):
            img.putpixel((x, y), (255, 0, 255, 255))
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, "PNG")


def make_building_data(data_dir: Path, name: str, footprint: list) -> None:
    """Create a minimal building data JSON file."""
    buildings_dir = data_dir / "buildings"
    buildings_dir.mkdir(parents=True, exist_ok=True)
    data_path = buildings_dir / f"{name}.json"
    data_path.write_text(json.dumps({
        "name": name.replace("_", " ").title(),
        "footprint": footprint,
    }))


def make_config(config_path: Path) -> None:
    """Create a minimal asset config."""
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(json.dumps({
        "dimensions": {
            "buildings_1x1": {"max_width": 128, "max_height": 128},
            "buildings_2x2": {"max_width": 256, "max_height": 192},
            "buildings_3x3": {"max_width": 384, "max_height": 256},
            "buildings_4x4": {"max_width": 512, "max_height": 320},
            "buildings_5x5": {"max_width": 640, "max_height": 384},
        }
    }))


# ---------------------------------------------------------------------------
# Building name extraction
# ---------------------------------------------------------------------------

class TestExtractBuildingName:
    def test_simple_name(self):
        assert ps.extract_building_name(Path("lumber_camp_01.png")) == "lumber_camp"

    def test_multi_digit_suffix(self):
        assert ps.extract_building_name(Path("town_center_02.png")) == "town_center"

    def test_no_suffix(self):
        assert ps.extract_building_name(Path("barracks.png")) == "barracks"

    def test_name_with_numbers(self):
        # Underscore-number at end should be stripped
        assert ps.extract_building_name(Path("house_01.png")) == "house"

    def test_nested_path(self):
        assert ps.extract_building_name(Path("assets/sprites/buildings/farm_03.png")) == "farm"


class TestStripNumericSuffix:
    def test_strips_suffix(self):
        assert ps.strip_numeric_suffix("lumber_camp_01") == "lumber_camp"

    def test_no_suffix(self):
        assert ps.strip_numeric_suffix("barracks") == "barracks"

    def test_multi_digit(self):
        assert ps.strip_numeric_suffix("house_123") == "house"


# ---------------------------------------------------------------------------
# Footprint lookup
# ---------------------------------------------------------------------------

class TestLookupFootprint:
    def test_found(self, tmp_path):
        make_building_data(tmp_path, "lumber_camp", [2, 2])
        assert ps.lookup_footprint("lumber_camp", tmp_path) == (2, 2)

    def test_not_found(self, tmp_path):
        with pytest.raises(FileNotFoundError, match="No building data file"):
            ps.lookup_footprint("nonexistent", tmp_path)

    def test_3x3_footprint(self, tmp_path):
        make_building_data(tmp_path, "town_center", [3, 3])
        assert ps.lookup_footprint("town_center", tmp_path) == (3, 3)

    def test_defaults_to_1x1(self, tmp_path):
        # Missing footprint field defaults to [1, 1]
        buildings_dir = tmp_path / "buildings"
        buildings_dir.mkdir(parents=True)
        (buildings_dir / "farm.json").write_text(json.dumps({"name": "Farm"}))
        assert ps.lookup_footprint("farm", tmp_path) == (1, 1)


# ---------------------------------------------------------------------------
# Footprint to canvas mapping
# ---------------------------------------------------------------------------

class TestFootprintToCanvas:
    @pytest.fixture
    def config(self, tmp_path):
        config_path = tmp_path / "config.json"
        make_config(config_path)
        return ps.load_config(config_path)

    def test_1x1(self, config):
        assert ps.footprint_to_canvas((1, 1), config) == (128, 128)

    def test_2x2(self, config):
        assert ps.footprint_to_canvas((2, 2), config) == (256, 192)

    def test_3x3(self, config):
        assert ps.footprint_to_canvas((3, 3), config) == (384, 256)

    def test_4x4(self, config):
        assert ps.footprint_to_canvas((4, 4), config) == (512, 320)

    def test_5x5(self, config):
        assert ps.footprint_to_canvas((5, 5), config) == (640, 384)

    def test_asymmetric_uses_max(self, config):
        # 2x3 → max(2,3) = 3 → buildings_3x3
        assert ps.footprint_to_canvas((2, 3), config) == (384, 256)


# ---------------------------------------------------------------------------
# Magenta restoration
# ---------------------------------------------------------------------------

class TestRestoreMagenta:
    def test_restores_blended_magenta(self):
        from PIL import Image

        img = Image.new("RGBA", (4, 1), (0, 0, 0, 0))
        # Pure magenta — should be preserved as-is
        img.putpixel((0, 0), (255, 0, 255, 255))
        # Blended magenta from LANCZOS — should be restored
        img.putpixel((1, 0), (200, 50, 200, 200))
        # Brown pixel — should NOT be touched
        img.putpixel((2, 0), (139, 115, 85, 255))
        # Transparent — should NOT be touched
        img.putpixel((3, 0), (0, 0, 0, 0))

        result, count = ps.restore_magenta(img)
        pixels = list(result.getdata())

        assert pixels[0] == (255, 0, 255, 255)  # already magenta
        assert pixels[1] == (255, 0, 255, 200)  # restored, alpha preserved
        assert pixels[2] == (139, 115, 85, 255)  # untouched
        assert pixels[3] == (0, 0, 0, 0)  # untouched
        assert count == 2  # both magenta pixels matched

    def test_no_magenta(self):
        from PIL import Image

        img = Image.new("RGBA", (2, 2), (100, 100, 100, 255))
        result, count = ps.restore_magenta(img)
        assert count == 0

    def test_does_not_modify_original(self):
        from PIL import Image

        img = Image.new("RGBA", (1, 1), (200, 50, 200, 255))
        original_pixel = img.getpixel((0, 0))
        _, _ = ps.restore_magenta(img)
        assert img.getpixel((0, 0)) == original_pixel


# ---------------------------------------------------------------------------
# Full processing
# ---------------------------------------------------------------------------

class TestProcessSprite:
    def test_basic_processing(self, tmp_path):
        source = tmp_path / "source.png"
        output = tmp_path / "output.png"
        make_png_with_content(source, 1536, 1024)

        summary = ps.process_sprite(source, output, (256, 192))

        assert output.is_file()
        assert summary["canvas_size"] == "256x192"
        assert summary["dry_run"] is False

        from PIL import Image
        result = Image.open(output)
        assert result.size == (256, 192)

    def test_dry_run(self, tmp_path):
        source = tmp_path / "source.png"
        output = tmp_path / "output.png"
        make_png_with_content(source, 1536, 1024)

        summary = ps.process_sprite(source, output, (256, 192), dry_run=True)

        assert not output.exists()
        assert summary["dry_run"] is True

    def test_transparent_source_raises(self, tmp_path):
        source = tmp_path / "empty.png"
        output = tmp_path / "out.png"
        make_png(source, 100, 100, (0, 0, 0, 0))

        with pytest.raises(ValueError, match="fully transparent"):
            ps.process_sprite(source, output, (128, 128))

    def test_creates_output_directory(self, tmp_path):
        source = tmp_path / "source.png"
        output = tmp_path / "nested" / "dir" / "output.png"
        make_png_with_content(source, 512, 512)

        ps.process_sprite(source, output, (128, 128))
        assert output.is_file()

    def test_magenta_preserved(self, tmp_path):
        from PIL import Image

        source = tmp_path / "source.png"
        output = tmp_path / "output.png"
        make_png_with_content(source, 1536, 1024)

        ps.process_sprite(source, output, (256, 192))

        result = Image.open(output)
        pixels = list(result.getdata())
        magenta = [p for p in pixels if p[0] == 255 and p[1] == 0 and p[2] == 255 and p[3] > 0]
        assert len(magenta) > 0, "Processed sprite should contain magenta mask pixels"


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

class TestCLI:
    def test_dry_run_cli(self, tmp_path):
        source = tmp_path / "house_01.png"
        config = tmp_path / "config.json"
        data_dir = tmp_path / "data"
        make_png_with_content(source, 800, 600)
        make_config(config)
        make_building_data(data_dir, "house", [2, 2])

        exit_code = ps.main([
            str(source),
            "--config", str(config),
            "--data-dir", str(data_dir),
            "--dry-run",
        ])
        assert exit_code == 0

    def test_missing_source(self, tmp_path):
        exit_code = ps.main([str(tmp_path / "nonexistent.png")])
        assert exit_code == 1

    def test_missing_building_data(self, tmp_path):
        source = tmp_path / "unknown_01.png"
        config = tmp_path / "config.json"
        make_png_with_content(source, 100, 100)
        make_config(config)

        exit_code = ps.main([
            str(source),
            "--config", str(config),
            "--data-dir", str(tmp_path / "data"),
        ])
        assert exit_code == 1

    def test_canvas_override(self, tmp_path):
        source = tmp_path / "custom.png"
        output = tmp_path / "out.png"
        config = tmp_path / "config.json"
        make_png_with_content(source, 800, 600)
        make_config(config)

        exit_code = ps.main([
            str(source),
            "--canvas", "200x150",
            "--output", str(output),
            "--config", str(config),
        ])
        assert exit_code == 0
        assert output.is_file()

        from PIL import Image
        result = Image.open(output)
        assert result.size == (200, 150)

    def test_invalid_canvas_format(self, tmp_path):
        source = tmp_path / "test.png"
        config = tmp_path / "config.json"
        make_png_with_content(source, 100, 100)
        make_config(config)

        exit_code = ps.main([
            str(source),
            "--canvas", "bad",
            "--config", str(config),
        ])
        assert exit_code == 1

    def test_building_name_override(self, tmp_path):
        source = tmp_path / "mystery_01.png"
        output = tmp_path / "out.png"
        config = tmp_path / "config.json"
        data_dir = tmp_path / "data"
        make_png_with_content(source, 800, 600)
        make_config(config)
        make_building_data(data_dir, "barracks", [3, 3])

        exit_code = ps.main([
            str(source),
            "--building", "barracks",
            "--output", str(output),
            "--config", str(config),
            "--data-dir", str(data_dir),
        ])
        assert exit_code == 0

        from PIL import Image
        result = Image.open(output)
        assert result.size == (384, 256)

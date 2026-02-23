"""Tests for tools/validate_assets.py asset validation logic."""
from __future__ import annotations

import json
import re
import struct
import tempfile
from pathlib import Path

import pytest

# Import the module under test
import sys

TOOLS_DIR = Path(__file__).resolve().parent.parent.parent / "tools"
sys.path.insert(0, str(TOOLS_DIR))

import validate_assets  # noqa: E402


# ---------------------------------------------------------------------------
# Config loading
# ---------------------------------------------------------------------------

class TestLoadConfig:
    def test_loads_valid_config(self, tmp_path: Path) -> None:
        config = {
            "naming": {"pattern": "^[a-z][a-z0-9_]*\\.png$", "description": "test"},
            "dimensions": {},
            "excluded_dirs": [],
        }
        config_file = tmp_path / "config.json"
        config_file.write_text(json.dumps(config))

        loaded = validate_assets.load_config(config_file)
        assert loaded["naming"]["pattern"] == "^[a-z][a-z0-9_]*\\.png$"

    def test_real_config_loads(self) -> None:
        """Ensure the shipped asset_config.json is valid."""
        config = validate_assets.load_config(validate_assets.DEFAULT_CONFIG)
        assert "naming" in config
        assert "dimensions" in config
        assert "animations" in config
        assert "excluded_dirs" in config


# ---------------------------------------------------------------------------
# Naming validation
# ---------------------------------------------------------------------------

class TestCheckNaming:
    PATTERN = re.compile(r"^[a-z][a-z0-9_]*\.png$")

    @pytest.mark.parametrize("name", [
        "grass.png",
        "desert_01.png",
        "villager_idle_n_0.png",
        "town_center_built.png",
        "a.png",
        "x1.png",
    ])
    def test_valid_names(self, name: str) -> None:
        assert validate_assets.check_naming(name, self.PATTERN) is None

    @pytest.mark.parametrize("name", [
        "Grass.png",          # uppercase
        "DESERT.png",         # all caps
        "my-sprite.png",      # hyphen
        "1_grass.png",        # starts with digit
        "grass.PNG",          # uppercase extension
        "grass.jpg",          # wrong extension
        ".hidden.png",        # starts with dot
        "grass tile.png",     # space
    ])
    def test_invalid_names(self, name: str) -> None:
        err = validate_assets.check_naming(name, self.PATTERN)
        assert err is not None
        assert "Naming violation" in err


# ---------------------------------------------------------------------------
# PNG dimension reading
# ---------------------------------------------------------------------------

def _make_png(tmp_path: Path, width: int, height: int, name: str = "test.png") -> Path:
    """Create a minimal valid PNG file with the given dimensions."""
    filepath = tmp_path / name
    # Minimal PNG: signature + IHDR chunk
    signature = b"\x89PNG\r\n\x1a\n"
    # IHDR chunk: length=13, type=IHDR, data, CRC
    ihdr_data = struct.pack(">II", width, height) + b"\x08\x02\x00\x00\x00"
    import zlib
    ihdr_crc = struct.pack(">I", zlib.crc32(b"IHDR" + ihdr_data) & 0xFFFFFFFF)
    ihdr_chunk = struct.pack(">I", 13) + b"IHDR" + ihdr_data + ihdr_crc
    # IEND chunk
    iend_crc = struct.pack(">I", zlib.crc32(b"IEND") & 0xFFFFFFFF)
    iend_chunk = struct.pack(">I", 0) + b"IEND" + iend_crc

    filepath.write_bytes(signature + ihdr_chunk + iend_chunk)
    return filepath


class TestReadPngDimensions:
    def test_reads_correct_dimensions(self, tmp_path: Path) -> None:
        filepath = _make_png(tmp_path, 128, 64)
        dims = validate_assets.read_png_dimensions(filepath)
        assert dims == (128, 64)

    def test_reads_small_dimensions(self, tmp_path: Path) -> None:
        filepath = _make_png(tmp_path, 48, 48)
        dims = validate_assets.read_png_dimensions(filepath)
        assert dims == (48, 48)

    def test_reads_large_dimensions(self, tmp_path: Path) -> None:
        filepath = _make_png(tmp_path, 384, 256)
        dims = validate_assets.read_png_dimensions(filepath)
        assert dims == (384, 256)

    def test_returns_none_for_non_png(self, tmp_path: Path) -> None:
        filepath = tmp_path / "not_a_png.png"
        filepath.write_bytes(b"not a png file at all")
        dims = validate_assets.read_png_dimensions(filepath)
        assert dims is None

    def test_returns_none_for_missing_file(self, tmp_path: Path) -> None:
        filepath = tmp_path / "missing.png"
        dims = validate_assets.read_png_dimensions(filepath)
        assert dims is None

    def test_returns_none_for_truncated_file(self, tmp_path: Path) -> None:
        filepath = tmp_path / "truncated.png"
        filepath.write_bytes(b"\x89PNG\r\n\x1a\n\x00")
        dims = validate_assets.read_png_dimensions(filepath)
        assert dims is None


# ---------------------------------------------------------------------------
# Asset classification
# ---------------------------------------------------------------------------

class TestClassifyAsset:
    def test_units(self) -> None:
        assert validate_assets.classify_asset("sprites/units/villager.png") == "units"

    def test_buildings_default(self) -> None:
        assert validate_assets.classify_asset("sprites/buildings/house.png") == "buildings_1x1"

    def test_buildings_2x2(self) -> None:
        assert validate_assets.classify_asset("sprites/buildings/2x2/barracks.png") == "buildings_2x2"

    def test_buildings_3x3(self) -> None:
        assert validate_assets.classify_asset("sprites/buildings/3x3/castle.png") == "buildings_3x3"

    def test_tiles(self) -> None:
        assert validate_assets.classify_asset("tiles/terrain/grass.png") == "tiles"

    def test_unknown(self) -> None:
        assert validate_assets.classify_asset("effects/explosion.png") is None


# ---------------------------------------------------------------------------
# Dimension checking
# ---------------------------------------------------------------------------

class TestCheckDimensions:
    CONFIG = {
        "dimensions": {
            "units": {"max_width": 64, "max_height": 64},
            "buildings_1x1": {"max_width": 128, "max_height": 128},
            "tiles": {"max_width": 256, "max_height": 256},
        }
    }

    def test_within_limits(self, tmp_path: Path) -> None:
        filepath = _make_png(tmp_path, 48, 48, "sprite.png")
        err = validate_assets.check_dimensions(filepath, "sprites/units/sprite.png", self.CONFIG)
        assert err is None

    def test_exceeds_width(self, tmp_path: Path) -> None:
        filepath = _make_png(tmp_path, 100, 48, "big.png")
        err = validate_assets.check_dimensions(filepath, "sprites/units/big.png", self.CONFIG)
        assert err is not None
        assert "Dimension violation" in err

    def test_exceeds_height(self, tmp_path: Path) -> None:
        filepath = _make_png(tmp_path, 48, 100, "tall.png")
        err = validate_assets.check_dimensions(filepath, "sprites/units/tall.png", self.CONFIG)
        assert err is not None
        assert "Dimension violation" in err

    def test_unknown_category_skipped(self, tmp_path: Path) -> None:
        filepath = _make_png(tmp_path, 9999, 9999, "fx.png")
        err = validate_assets.check_dimensions(filepath, "effects/fx.png", self.CONFIG)
        assert err is None


# ---------------------------------------------------------------------------
# Full validation integration
# ---------------------------------------------------------------------------

class TestValidateAssets:
    def _make_assets_dir(self, tmp_path: Path) -> Path:
        """Create a minimal assets directory with valid files."""
        assets = tmp_path / "assets"
        tiles_dir = assets / "tiles" / "terrain"
        tiles_dir.mkdir(parents=True)
        _make_png(tiles_dir, 128, 128, "grass.png")
        _make_png(tiles_dir, 128, 128, "desert.png")
        return assets

    def _default_config(self) -> dict:
        return validate_assets.load_config(validate_assets.DEFAULT_CONFIG)

    def test_valid_assets_no_errors(self, tmp_path: Path) -> None:
        assets = self._make_assets_dir(tmp_path)
        config = self._default_config()
        errors = validate_assets.validate_assets(assets, config)
        assert len(errors) == 0

    def test_bad_naming_reported(self, tmp_path: Path) -> None:
        assets = self._make_assets_dir(tmp_path)
        tiles_dir = assets / "tiles" / "terrain"
        _make_png(tiles_dir, 128, 128, "BadName.png")
        config = self._default_config()
        errors = validate_assets.validate_assets(assets, config)
        assert any("Naming violation" in e for e in errors)

    def test_oversized_tile_reported(self, tmp_path: Path) -> None:
        assets = self._make_assets_dir(tmp_path)
        tiles_dir = assets / "tiles" / "terrain"
        _make_png(tiles_dir, 512, 512, "huge.png")
        config = self._default_config()
        errors = validate_assets.validate_assets(assets, config)
        assert any("Dimension violation" in e for e in errors)

    def test_excluded_dirs_skipped(self, tmp_path: Path) -> None:
        assets = self._make_assets_dir(tmp_path)
        branding = assets / "branding"
        branding.mkdir()
        _make_png(branding, 9999, 9999, "BadName.png")
        config = self._default_config()
        errors = validate_assets.validate_assets(assets, config)
        # branding is excluded, so no errors from it
        assert len(errors) == 0


# ---------------------------------------------------------------------------
# CLI exit codes
# ---------------------------------------------------------------------------

class TestMainExitCodes:
    def _make_assets_dir(self, tmp_path: Path) -> Path:
        assets = tmp_path / "assets"
        tiles_dir = assets / "tiles" / "terrain"
        tiles_dir.mkdir(parents=True)
        _make_png(tiles_dir, 128, 128, "grass.png")
        return assets

    def test_exit_0_on_pass(self, tmp_path: Path) -> None:
        assets = self._make_assets_dir(tmp_path)
        config_path = validate_assets.DEFAULT_CONFIG
        exit_code = validate_assets.main([
            "--assets-dir", str(assets),
            "--config", str(config_path),
        ])
        assert exit_code == 0

    def test_exit_1_on_failure(self, tmp_path: Path) -> None:
        assets = self._make_assets_dir(tmp_path)
        tiles_dir = assets / "tiles" / "terrain"
        _make_png(tiles_dir, 512, 512, "huge.png")
        config_path = validate_assets.DEFAULT_CONFIG
        exit_code = validate_assets.main([
            "--assets-dir", str(assets),
            "--config", str(config_path),
        ])
        assert exit_code == 1

    def test_exit_1_on_missing_assets_dir(self, tmp_path: Path) -> None:
        exit_code = validate_assets.main([
            "--assets-dir", str(tmp_path / "nonexistent"),
        ])
        assert exit_code == 1

    def test_verbose_flag(self, tmp_path: Path) -> None:
        assets = self._make_assets_dir(tmp_path)
        config_path = validate_assets.DEFAULT_CONFIG
        exit_code = validate_assets.main([
            "--assets-dir", str(assets),
            "--config", str(config_path),
            "--verbose",
        ])
        assert exit_code == 0

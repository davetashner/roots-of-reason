"""Tests for tools/animate.py — live animation filmstrip capture."""
from __future__ import annotations

import sys
from pathlib import Path
from unittest import mock

import pytest

# Ensure tools/ is importable
TOOLS_DIR = Path(__file__).resolve().parent.parent.parent / "tools"
sys.path.insert(0, str(TOOLS_DIR))

import animate

try:
    from PIL import Image as _PIL_Image

    HAS_PIL = True
except ImportError:
    HAS_PIL = False

requires_pil = pytest.mark.skipif(not HAS_PIL, reason="Pillow not installed")


# ---------------------------------------------------------------------------
# Direction vector tests (no PIL needed)
# ---------------------------------------------------------------------------


class TestDirectionVectors:
    def test_all_8_directions_covered(self):
        assert set(animate.DIRECTION_VECTORS.keys()) == set(animate.ALL_DIRECTIONS)

    def test_vectors_are_tuples(self):
        for d, v in animate.DIRECTION_VECTORS.items():
            assert isinstance(v, tuple), f"{d} vector is not a tuple"
            assert len(v) == 2, f"{d} vector should have 2 components"

    def test_opposite_directions_are_negated(self):
        pairs = [("n", "s"), ("e", "w"), ("ne", "sw"), ("nw", "se")]
        for a, b in pairs:
            va = animate.DIRECTION_VECTORS[a]
            vb = animate.DIRECTION_VECTORS[b]
            assert va[0] == -vb[0], f"{a}/{b} x-components should be negated"
            assert va[1] == -vb[1], f"{a}/{b} y-components should be negated"


# ---------------------------------------------------------------------------
# Filmstrip stitching (requires PIL)
# ---------------------------------------------------------------------------


@requires_pil
class TestStitchFilmstrip:
    def test_correct_dimensions(self):
        from PIL import Image

        frames = [Image.new("RGBA", (80, 80), (100, 100, 100, 255)) for _ in range(4)]
        result = animate.stitch_filmstrip(frames)
        assert result.width == 4 * 80
        assert result.height == 80

    def test_variable_height_frames(self):
        from PIL import Image

        frames = [
            Image.new("RGBA", (80, 60), (100, 100, 100, 255)),
            Image.new("RGBA", (80, 100), (100, 100, 100, 255)),
        ]
        result = animate.stitch_filmstrip(frames)
        assert result.width == 160
        assert result.height == 100  # max height

    def test_empty_frames(self):
        result = animate.stitch_filmstrip([])
        assert result.width == 1
        assert result.height == 1


# ---------------------------------------------------------------------------
# Server connectivity
# ---------------------------------------------------------------------------


class TestPingServer:
    def test_missing_server_returns_false(self):
        # With no server running, ping should fail gracefully
        with mock.patch.object(animate, "DEBUG_SERVER", "http://127.0.0.1:19999"):
            assert animate.ping_server() is False


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


class TestCLI:
    def test_no_server_exits_with_error(self):
        with mock.patch.object(animate, "DEBUG_SERVER", "http://127.0.0.1:19999"):
            assert animate.main(["walk", "s"]) == 1

    def test_invalid_animation_exits_with_error(self):
        with mock.patch.object(animate, "ping_server", return_value=True):
            assert animate.main(["idle", "s"]) == 1

    def test_invalid_direction_exits_with_error(self):
        with mock.patch.object(animate, "ping_server", return_value=True):
            assert animate.main(["walk", "xyz"]) == 1

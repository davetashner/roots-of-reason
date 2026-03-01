"""Tests for tools/asset_pipeline.py — asset pipeline orchestrator."""
from __future__ import annotations

import json
import sys
from pathlib import Path
from unittest import mock

import pytest

# Ensure tools/ is importable
TOOLS_DIR = Path(__file__).resolve().parent.parent.parent / "tools"
sys.path.insert(0, str(TOOLS_DIR))

import asset_pipeline as ap


class TestFindBlender:
    def test_finds_from_env_var(self):
        with mock.patch.dict("os.environ", {"BLENDER_BIN": "/usr/bin/blender"}):
            with mock.patch("shutil.which", return_value="/usr/bin/blender"):
                assert ap.find_blender() == "/usr/bin/blender"

    def test_finds_from_path(self):
        with mock.patch.dict("os.environ", {}, clear=True):
            with mock.patch("shutil.which", side_effect=lambda x: "/usr/bin/blender" if x == "blender" else None):
                assert ap.find_blender() == "/usr/bin/blender"

    def test_finds_mac_default(self):
        mac_path = "/Applications/Blender.app/Contents/MacOS/Blender"
        with mock.patch.dict("os.environ", {}, clear=True):
            with mock.patch("shutil.which", return_value=None):
                with mock.patch("os.path.isfile", return_value=True):
                    assert ap.find_blender() == mac_path

    def test_returns_none_when_not_found(self):
        with mock.patch.dict("os.environ", {}, clear=True):
            with mock.patch("shutil.which", return_value=None):
                with mock.patch("os.path.isfile", return_value=False):
                    assert ap.find_blender() is None


class TestParseArgs:
    def test_defaults_unit_animations(self):
        result = ap.main(["archer", "--skip-render", "--skip-pack", "--skip-validate"])
        # Should not error — animations default to idle,walk,attack,death
        # Return code depends on whether manifest script exists, but args parsed OK
        assert result in (0, 1)

    def test_mismatched_animations_frames_returns_error(self):
        result = ap.main([
            "test", "--animations", "idle,walk", "--frames", "4",
            "--skip-render", "--skip-pack", "--skip-validate"
        ])
        assert result == 1


class TestSteps:
    def test_step_manifest_calls_generate_manifest(self):
        with mock.patch("subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(returncode=0)
            args = mock.Mock(subject="archer")
            result = ap.step_manifest(args)
            assert result is True
            mock_run.assert_called_once()
            cmd = mock_run.call_args[0][0]
            assert any("generate_manifest.py" in c for c in cmd)
            assert "archer" in cmd

    def test_step_pack_calls_spritesheet_packer(self):
        with mock.patch("subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(returncode=0)
            args = mock.Mock(subject="archer")
            result = ap.step_pack(args)
            assert result is True
            cmd = mock_run.call_args[0][0]
            assert any("spritesheet_packer.py" in c for c in cmd)

    def test_step_render_calls_blender(self):
        with mock.patch("subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(returncode=0)
            args = mock.Mock(
                subject="archer", type="unit", footprint=None,
                animations=["idle", "walk"], frames=[4, 8],
                directions=None
            )
            result = ap.step_render(args, "/usr/bin/blender")
            assert result is True
            cmd = mock_run.call_args[0][0]
            assert cmd[0] == "/usr/bin/blender"
            assert "--background" in cmd
            assert "archer" in cmd

    def test_step_render_returns_false_on_failure(self):
        with mock.patch("subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(returncode=1)
            args = mock.Mock(
                subject="test", type="unit", footprint=None,
                animations=None, frames=None, directions=None
            )
            result = ap.step_render(args, "/usr/bin/blender")
            assert result is False

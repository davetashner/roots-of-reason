"""Tests for tools/scene_tree.py — Godot .tscn scene tree parser."""
from __future__ import annotations

import textwrap
import tempfile
from pathlib import Path

import pytest
import sys
import os

# Add tools directory to path so we can import scene_tree
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "tools"))

from scene_tree import (
    ExtResource,
    SceneNode,
    parse_tscn,
    build_tree,
    format_tree,
    scene_tree,
    main,
)


# --- Fixtures ---

SIMPLE_SCENE = textwrap.dedent("""\
    [gd_scene load_steps=2 format=3]

    [ext_resource type="Script" path="res://scripts/main.gd" id="1"]

    [node name="Main" type="Node2D"]
    script = ExtResource("1")
""")

NESTED_SCENE = textwrap.dedent("""\
    [gd_scene load_steps=3 format=3]

    [ext_resource type="Script" path="res://scripts/main.gd" id="1"]
    [ext_resource type="Script" path="res://scripts/ui/hud.gd" id="2"]

    [node name="Root" type="Node2D"]
    script = ExtResource("1")

    [node name="Camera" type="Camera2D" parent="."]

    [node name="UI" type="CanvasLayer" parent="."]
    script = ExtResource("2")

    [node name="TopBar" type="HBoxContainer" parent="UI"]

    [node name="BottomBar" type="HBoxContainer" parent="UI"]

    [node name="Label" type="Label" parent="UI/TopBar"]
""")

INSTANCE_SCENE = textwrap.dedent("""\
    [gd_scene load_steps=2 format=3]

    [ext_resource type="PackedScene" path="res://scenes/unit.tscn" id="1"]

    [node name="World" type="Node2D"]

    [node name="Unit1" parent="." instance=ExtResource("1")]
""")


# --- parse_tscn ---

class TestParseTscn:
    def test_simple_root_node(self):
        resources, nodes = parse_tscn(SIMPLE_SCENE)
        assert len(nodes) == 1
        assert nodes[0].name == "Main"
        assert nodes[0].type == "Node2D"
        assert nodes[0].parent is None
        assert nodes[0].script == "res://scripts/main.gd"

    def test_ext_resources_parsed(self):
        resources, _ = parse_tscn(SIMPLE_SCENE)
        assert "1" in resources
        assert resources["1"].type == "Script"
        assert resources["1"].path == "res://scripts/main.gd"

    def test_nested_nodes(self):
        _, nodes = parse_tscn(NESTED_SCENE)
        assert len(nodes) == 6
        names = [n.name for n in nodes]
        assert names == ["Root", "Camera", "UI", "TopBar", "BottomBar", "Label"]

    def test_parent_relationships(self):
        _, nodes = parse_tscn(NESTED_SCENE)
        # Root has no parent
        assert nodes[0].parent is None
        # Camera is child of root
        assert nodes[1].parent == "."
        # TopBar is child of UI
        assert nodes[3].parent == "UI"
        # Label is grandchild
        assert nodes[5].parent == "UI/TopBar"

    def test_script_association(self):
        _, nodes = parse_tscn(NESTED_SCENE)
        assert nodes[0].script == "res://scripts/main.gd"  # Root
        assert nodes[1].script is None  # Camera
        assert nodes[2].script == "res://scripts/ui/hud.gd"  # UI

    def test_instance_resource(self):
        _, nodes = parse_tscn(INSTANCE_SCENE)
        assert nodes[1].name == "Unit1"
        assert nodes[1].instance == "1"

    def test_empty_source(self):
        resources, nodes = parse_tscn("")
        assert resources == {}
        assert nodes == []


# --- build_tree ---

class TestBuildTree:
    def test_single_root(self):
        _, nodes = parse_tscn(SIMPLE_SCENE)
        root = build_tree(nodes)
        assert root is not None
        assert root.name == "Main"
        assert root.children == []

    def test_nested_tree(self):
        _, nodes = parse_tscn(NESTED_SCENE)
        root = build_tree(nodes)
        assert root is not None
        assert root.name == "Root"
        assert len(root.children) == 2  # Camera, UI
        assert root.children[0].name == "Camera"
        assert root.children[1].name == "UI"
        # UI children
        ui = root.children[1]
        assert len(ui.children) == 2  # TopBar, BottomBar
        assert ui.children[0].name == "TopBar"
        assert ui.children[1].name == "BottomBar"
        # TopBar children
        assert len(ui.children[0].children) == 1
        assert ui.children[0].children[0].name == "Label"

    def test_empty_nodes(self):
        assert build_tree([]) is None


# --- format_tree ---

class TestFormatTree:
    def test_single_node(self):
        node = SceneNode(name="Root", type="Node2D", parent=None)
        lines = format_tree(node)
        assert lines == ["Root (Node2D)"]

    def test_with_script(self):
        node = SceneNode(name="Root", type="Node2D", parent=None, script="res://main.gd")
        lines = format_tree(node)
        assert lines == ["Root (Node2D) [res://main.gd]"]

    def test_nested_tree_formatting(self):
        _, nodes = parse_tscn(NESTED_SCENE)
        root = build_tree(nodes)
        lines = format_tree(root)
        assert lines[0] == "Root (Node2D) [res://scripts/main.gd]"
        assert lines[1] == "\u251c\u2500\u2500 Camera (Camera2D)"
        assert lines[2] == "\u2514\u2500\u2500 UI (CanvasLayer) [res://scripts/ui/hud.gd]"
        assert lines[3] == "    \u251c\u2500\u2500 TopBar (HBoxContainer)"
        assert lines[4] == "    \u2502   \u2514\u2500\u2500 Label (Label)"
        assert lines[5] == "    \u2514\u2500\u2500 BottomBar (HBoxContainer)"

    def test_deep_nesting_connectors(self):
        _, nodes = parse_tscn(NESTED_SCENE)
        root = build_tree(nodes)
        lines = format_tree(root)
        # Label is under TopBar which is under UI
        # TopBar is not last sibling so its children use │ connector
        label_line = [l for l in lines if "Label" in l][0]
        assert "\u2502" in label_line  # vertical bar from TopBar not being last


# --- depth limiting ---

class TestDepthLimiting:
    def test_depth_zero_shows_only_root(self):
        _, nodes = parse_tscn(NESTED_SCENE)
        root = build_tree(nodes)
        lines = format_tree(root, max_depth=0)
        assert len(lines) == 1
        assert lines[0].startswith("Root")

    def test_depth_one_shows_root_and_children(self):
        _, nodes = parse_tscn(NESTED_SCENE)
        root = build_tree(nodes)
        lines = format_tree(root, max_depth=1)
        assert len(lines) == 3  # Root, Camera, UI (but not TopBar/BottomBar)
        names_in_output = " ".join(lines)
        assert "Camera" in names_in_output
        assert "UI" in names_in_output
        assert "TopBar" not in names_in_output

    def test_depth_none_shows_all(self):
        _, nodes = parse_tscn(NESTED_SCENE)
        root = build_tree(nodes)
        lines = format_tree(root, max_depth=None)
        assert len(lines) == 6  # All nodes


# --- scene_tree convenience function ---

class TestSceneTree:
    def test_simple(self):
        output = scene_tree(SIMPLE_SCENE)
        assert "Main (Node2D)" in output
        assert "res://scripts/main.gd" in output

    def test_empty_raises(self):
        with pytest.raises(ValueError, match="No nodes found"):
            scene_tree("")


# --- CLI main ---

class TestMain:
    def test_valid_file(self, tmp_path):
        tscn = tmp_path / "test.tscn"
        tscn.write_text(SIMPLE_SCENE)
        assert main([str(tscn)]) == 0

    def test_missing_file(self):
        assert main(["/nonexistent/file.tscn"]) == 1

    def test_non_tscn_file(self, tmp_path):
        txt = tmp_path / "test.txt"
        txt.write_text("hello")
        assert main([str(txt)]) == 1

    def test_depth_flag(self, tmp_path):
        tscn = tmp_path / "test.tscn"
        tscn.write_text(NESTED_SCENE)
        assert main([str(tscn), "--depth", "1"]) == 0

    def test_empty_scene_file(self, tmp_path):
        tscn = tmp_path / "empty.tscn"
        tscn.write_text("[gd_scene format=3]\n")
        assert main([str(tscn)]) == 1

#!/usr/bin/env python3
"""Parse Godot .tscn files and print the node tree.

Usage:
    python3 tools/scene_tree.py <path.tscn> [--depth N]
"""
from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import TextIO


@dataclass
class ExtResource:
    """An external resource entry from a .tscn file."""

    id: str
    type: str
    path: str


@dataclass
class SceneNode:
    """A node in the scene tree."""

    name: str
    type: str
    parent: str | None  # None for root, "." for child of root, path otherwise
    script: str | None = None
    instance: str | None = None
    children: list[SceneNode] = field(default_factory=list)


# --- Parsing helpers ---

_EXT_RESOURCE_RE = re.compile(
    r'\[ext_resource\s+'
    r'type="(?P<type>[^"]+)"\s+'
    r'path="(?P<path>[^"]+)"\s+'
    r'id="(?P<id>[^"]+)"\s*\]'
)

_NODE_RE = re.compile(
    r'\[node\s+name="(?P<name>[^"]+)"'
    r'(?:\s+type="(?P<type>[^"]+)")?'
    r'(?:\s+parent="(?P<parent>[^"]+)")?'
    r'(?:\s+instance=ExtResource\("(?P<instance>[^"]+)"\))?'
)

_SCRIPT_RE = re.compile(r'^script\s*=\s*ExtResource\("(?P<id>[^"]+)"\)')


def parse_tscn(source: str) -> tuple[dict[str, ExtResource], list[SceneNode]]:
    """Parse a .tscn file's text content.

    Returns:
        A tuple of (ext_resources dict keyed by id, flat list of SceneNodes).
    """
    ext_resources: dict[str, ExtResource] = {}
    nodes: list[SceneNode] = []
    current_node: SceneNode | None = None

    for line in source.splitlines():
        stripped = line.strip()

        # ext_resource
        m = _EXT_RESOURCE_RE.match(stripped)
        if m:
            res = ExtResource(id=m.group("id"), type=m.group("type"), path=m.group("path"))
            ext_resources[res.id] = res
            continue

        # node
        m = _NODE_RE.match(stripped)
        if m:
            current_node = SceneNode(
                name=m.group("name"),
                type=m.group("type") or "",
                parent=m.group("parent"),
                instance=m.group("instance"),
            )
            nodes.append(current_node)
            continue

        # script assignment (must follow a [node] section)
        if current_node is not None:
            m = _SCRIPT_RE.match(stripped)
            if m:
                res_id = m.group("id")
                if res_id in ext_resources:
                    current_node.script = ext_resources[res_id].path
                continue

        # Any other section header resets current_node context
        if stripped.startswith("[") and not stripped.startswith("[node"):
            current_node = None

    return ext_resources, nodes


def build_tree(nodes: list[SceneNode]) -> SceneNode | None:
    """Build the tree structure from a flat list of nodes.

    Returns the root node with children populated, or None if no nodes.
    """
    if not nodes:
        return None

    root = nodes[0]
    # Map path -> node for parent resolution
    path_map: dict[str, SceneNode] = {root.name: root}

    for node in nodes[1:]:
        if node.parent == ".":
            parent_path = root.name
        elif node.parent:
            parent_path = f"{root.name}/{node.parent}"
        else:
            # No parent means it's a root (shouldn't happen for non-first nodes)
            continue

        parent = path_map.get(parent_path)
        if parent is not None:
            parent.children.append(node)

        # Register this node's own path
        if node.parent == ".":
            path_map[f"{root.name}/{node.name}"] = node
        elif node.parent:
            path_map[f"{root.name}/{node.parent}/{node.name}"] = node

    return root


def format_tree(
    node: SceneNode,
    *,
    max_depth: int | None = None,
    _prefix: str = "",
    _is_last: bool = True,
    _depth: int = 0,
) -> list[str]:
    """Format a node tree into lines with box-drawing characters.

    Args:
        node: The node to format.
        max_depth: Maximum depth to display (None for unlimited).
        _prefix: Internal — prefix for indentation.
        _is_last: Internal — whether this node is the last sibling.
        _depth: Internal — current depth level.

    Returns:
        List of formatted strings (one per line).
    """
    lines: list[str] = []

    # Build this node's label
    type_str = f" ({node.type})" if node.type else ""
    script_str = f" [{node.script}]" if node.script else ""
    instance_str = f" <instance>" if node.instance else ""
    label = f"{node.name}{type_str}{script_str}{instance_str}"

    if _depth == 0:
        lines.append(label)
    else:
        connector = "\u2514\u2500\u2500 " if _is_last else "\u251c\u2500\u2500 "
        lines.append(f"{_prefix}{connector}{label}")

    # Stop recursion if we've hit max depth
    if max_depth is not None and _depth >= max_depth:
        return lines

    # Recurse into children
    child_count = len(node.children)
    for i, child in enumerate(node.children):
        is_last_child = i == child_count - 1
        if _depth == 0:
            child_prefix = ""
        else:
            extension = "    " if _is_last else "\u2502   "
            child_prefix = _prefix + extension

        lines.extend(
            format_tree(
                child,
                max_depth=max_depth,
                _prefix=child_prefix,
                _is_last=is_last_child,
                _depth=_depth + 1,
            )
        )

    return lines


def scene_tree(source: str, *, max_depth: int | None = None) -> str:
    """Parse a .tscn source string and return the formatted tree.

    Args:
        source: The text content of a .tscn file.
        max_depth: Maximum depth to display (None for unlimited).

    Returns:
        A string with the formatted tree.

    Raises:
        ValueError: If no nodes are found in the source.
    """
    _, nodes = parse_tscn(source)
    root = build_tree(nodes)
    if root is None:
        raise ValueError("No nodes found in scene file")
    lines = format_tree(root, max_depth=max_depth)
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    """CLI entry point."""
    parser = argparse.ArgumentParser(description="Print Godot .tscn scene tree")
    parser.add_argument("file", help="Path to .tscn file")
    parser.add_argument("--depth", type=int, default=None, help="Maximum tree depth to display")
    args = parser.parse_args(argv)

    path = Path(args.file)
    if not path.exists():
        print(f"Error: file not found: {path}", file=sys.stderr)
        return 1
    if not path.suffix == ".tscn":
        print(f"Error: not a .tscn file: {path}", file=sys.stderr)
        return 1

    try:
        source = path.read_text(encoding="utf-8")
        output = scene_tree(source, max_depth=args.depth)
        print(output)
        return 0
    except (ValueError, OSError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())

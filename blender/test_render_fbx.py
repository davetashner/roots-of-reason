#!/usr/bin/env python3
"""Test render an FBX model from the S isometric camera angle.

Imports the FBX, sets up isometric camera + lighting, renders one frame.
Useful for quickly checking how an external model looks in the pipeline.

Usage:
    blender --background --python blender/test_render_fbx.py -- model.fbx [output.png]
"""
import math
import os
import sys

try:
    import bpy
    import mathutils
except ImportError:
    print("ERROR: Must run inside Blender.", file=sys.stderr)
    sys.exit(1)


ELEVATION_DEG = 35.264
UNIT_CANVAS_2X = (256, 256)
_NEEDS_USE_NODES = bpy.app.version < (5, 0, 0)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def setup_camera(azimuth_deg, ortho_scale=2.8):
    cam_data = bpy.data.cameras.new("IsoCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = ortho_scale

    cam_obj = bpy.data.objects.new("IsoCam", cam_data)
    bpy.context.scene.collection.objects.link(cam_obj)
    bpy.context.scene.camera = cam_obj

    distance = 20.0
    elev_rad = math.radians(ELEVATION_DEG)
    az_rad = math.radians(azimuth_deg)

    x = distance * math.cos(elev_rad) * math.sin(az_rad)
    y = -distance * math.cos(elev_rad) * math.cos(az_rad)
    z = distance * math.sin(elev_rad)

    cam_obj.location = (x, y, z)
    direction = mathutils.Vector((0, 0, 0)) - cam_obj.location
    rot_quat = direction.to_track_quat("-Z", "Y")
    cam_obj.rotation_euler = rot_quat.to_euler()
    return cam_obj


def setup_lighting():
    key_data = bpy.data.lights.new("KeyLight", "SUN")
    key_data.energy = 3.0
    key_obj = bpy.data.objects.new("KeyLight", key_data)
    bpy.context.scene.collection.objects.link(key_obj)
    key_obj.rotation_euler = (math.radians(45), 0, math.radians(-135))

    fill_data = bpy.data.lights.new("FillLight", "SUN")
    fill_data.energy = 1.2
    fill_obj = bpy.data.objects.new("FillLight", fill_data)
    bpy.context.scene.collection.objects.link(fill_obj)
    fill_obj.rotation_euler = (math.radians(60), 0, math.radians(45))

    world = bpy.data.worlds.get("World") or bpy.data.worlds.new("World")
    bpy.context.scene.world = world
    if _NEEDS_USE_NODES:
        world.use_nodes = True
    bg_node = world.node_tree.nodes.get("Background")
    if bg_node:
        bg_node.inputs["Color"].default_value = (0.02, 0.02, 0.02, 1.0)
        bg_node.inputs["Strength"].default_value = 0.3


def setup_render():
    scene = bpy.context.scene
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE"

    scene.render.resolution_x = UNIT_CANVAS_2X[0]
    scene.render.resolution_y = UNIT_CANVAS_2X[1]
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"


def center_model():
    """Center all mesh objects at origin, with feet on ground plane."""
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    if not meshes:
        return

    # Compute overall bounding box
    min_co = mathutils.Vector((float("inf"),) * 3)
    max_co = mathutils.Vector((float("-inf"),) * 3)
    for m in meshes:
        for v in m.data.vertices:
            world_co = m.matrix_world @ v.co
            for i in range(3):
                min_co[i] = min(min_co[i], world_co[i])
                max_co[i] = max(max_co[i], world_co[i])

    center_x = (min_co.x + max_co.x) / 2
    center_y = (min_co.y + max_co.y) / 2
    min_z = min_co.z

    # Shift to center XY and put feet on ground
    offset = mathutils.Vector((-center_x, -center_y, -min_z))
    for m in meshes:
        m.location += offset

    height = max_co.z - min_co.z
    print(f"  Centered model: height={height:.2f}, offset={offset}")


def main():
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    else:
        argv = []

    if not argv:
        print("Usage: blender --background --python test_render_fbx.py -- <model.fbx> [output.png]")
        sys.exit(1)

    fbx_path = os.path.abspath(argv[0])
    output_path = argv[1] if len(argv) > 1 else os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "blender", "renders", "fbx_test.png"
    )

    print(f"=== Test Render FBX ===")
    print(f"  Input:  {fbx_path}")
    print(f"  Output: {output_path}")

    clear_scene()
    setup_lighting()

    # Import FBX
    bpy.ops.import_scene.fbx(filepath=fbx_path)
    print(f"  Imported FBX")

    # Center model
    center_model()

    # Setup camera and render
    cam = setup_camera(azimuth_deg=0, ortho_scale=2.8)
    setup_render()

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    bpy.context.scene.render.filepath = output_path
    bpy.ops.render.render(write_still=True)

    print(f"  Rendered to: {output_path}")
    print(f"=== Done ===")


if __name__ == "__main__":
    main()

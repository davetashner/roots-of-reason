#!/usr/bin/env python3
"""Inspect an FBX file: mesh count, poly count, armature, materials, animations.

Usage (run inside Blender):
    blender --background --python blender/inspect_fbx.py -- path/to/model.fbx
"""
import sys
import os

try:
    import bpy
except ImportError:
    print("ERROR: Must run inside Blender.", file=sys.stderr)
    sys.exit(1)


def main():
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    else:
        argv = []

    if not argv:
        print("Usage: blender --background --python inspect_fbx.py -- <model.fbx>")
        sys.exit(1)

    fbx_path = os.path.abspath(argv[0])
    if not os.path.isfile(fbx_path):
        print(f"Error: file not found: {fbx_path}")
        sys.exit(1)

    # Clear scene
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

    # Import FBX
    print(f"\n=== FBX Inspection: {os.path.basename(fbx_path)} ===")
    print(f"  File size: {os.path.getsize(fbx_path) / 1024 / 1024:.1f} MB")

    bpy.ops.import_scene.fbx(filepath=fbx_path)

    # Analyze
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    armatures = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    empties = [o for o in bpy.data.objects if o.type == "EMPTY"]
    cameras = [o for o in bpy.data.objects if o.type == "CAMERA"]
    lights = [o for o in bpy.data.objects if o.type == "LIGHT"]

    print(f"\n  Objects: {len(bpy.data.objects)} total")
    print(f"    Meshes:    {len(meshes)}")
    print(f"    Armatures: {len(armatures)}")
    print(f"    Empties:   {len(empties)}")
    print(f"    Cameras:   {len(cameras)}")
    print(f"    Lights:    {len(lights)}")

    # Mesh details
    total_verts = 0
    total_faces = 0
    print(f"\n  Mesh details:")
    for m in meshes:
        verts = len(m.data.vertices)
        faces = len(m.data.polygons)
        total_verts += verts
        total_faces += faces
        mats = [s.material.name if s.material else "None" for s in m.material_slots]
        print(f"    {m.name}: {verts} verts, {faces} faces, materials={mats}")

    print(f"\n  Total geometry: {total_verts} vertices, {total_faces} faces")

    # Armature details
    if armatures:
        for arm in armatures:
            bones = arm.data.bones
            print(f"\n  Armature '{arm.name}': {len(bones)} bones")
            for bone in bones[:10]:
                print(f"    - {bone.name}")
            if len(bones) > 10:
                print(f"    ... and {len(bones) - 10} more")

    # Materials
    print(f"\n  Materials: {len(bpy.data.materials)}")
    for mat in bpy.data.materials:
        print(f"    - {mat.name}")

    # Animations
    print(f"\n  Actions (animations): {len(bpy.data.actions)}")
    for action in bpy.data.actions:
        frames = action.frame_range
        print(f"    - {action.name}: frames {int(frames[0])}-{int(frames[1])}")

    # Bounding box
    if meshes:
        import mathutils
        min_co = mathutils.Vector((float("inf"),) * 3)
        max_co = mathutils.Vector((float("-inf"),) * 3)
        for m in meshes:
            for v in m.data.vertices:
                world_co = m.matrix_world @ v.co
                for i in range(3):
                    min_co[i] = min(min_co[i], world_co[i])
                    max_co[i] = max(max_co[i], world_co[i])
        size = max_co - min_co
        print(f"\n  Bounding box: {size.x:.2f} x {size.y:.2f} x {size.z:.2f} (Blender units)")
        print(f"  Height: {size.z:.2f} units")

    print(f"\n=== Inspection Complete ===")


if __name__ == "__main__":
    main()

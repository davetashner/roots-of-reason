"""Common animation actions shared across all unit types.

Provides idle, walk, and death animations with procedural bone keyframes.
"""

import math


def get_bone_pose(armature, bone_name):
    """Get a pose bone by name, or None if not found."""
    return armature.pose.bones.get(bone_name)


def reset_pose(armature):
    """Reset all pose bones to rest position."""
    for pb in armature.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.rotation_euler = (0, 0, 0)
        pb.scale = (1, 1, 1)


def keyframe_all_bones(armature, frame):
    """Insert a keyframe for all pose bones at the given frame."""
    for pb in armature.pose.bones:
        pb.keyframe_insert(data_path="location", frame=frame)
        pb.keyframe_insert(data_path="rotation_euler", frame=frame)
        pb.keyframe_insert(data_path="rotation_quaternion", frame=frame)


def create_idle_action(armature, n_frames=4):
    """Create idle animation: subtle breathing/sway."""
    import bpy

    action = bpy.data.actions.new("idle")
    armature.animation_data_create()
    armature.animation_data.action = action

    for frame_idx in range(n_frames):
        t = frame_idx / n_frames
        frame = frame_idx + 1

        reset_pose(armature)

        # Subtle spine sway
        spine = get_bone_pose(armature, "spine_02")
        if spine:
            sway = math.sin(t * 2 * math.pi) * math.radians(2)
            spine.rotation_euler = (0, sway, 0)

        # Slight head tilt
        head = get_bone_pose(armature, "head")
        if head:
            tilt = math.sin(t * 2 * math.pi + 0.5) * math.radians(1.5)
            head.rotation_euler = (tilt, 0, 0)

        # Breathing — chest expansion
        spine3 = get_bone_pose(armature, "spine_03")
        if spine3:
            breathe = math.sin(t * 2 * math.pi) * 0.003
            spine3.location = (0, breathe, 0)

        keyframe_all_bones(armature, frame)

    return action


def create_walk_action(armature, n_frames=8):
    """Create walk cycle animation."""
    import bpy

    action = bpy.data.actions.new("walk")
    armature.animation_data.action = action

    for frame_idx in range(n_frames):
        t = frame_idx / n_frames
        frame = frame_idx + 1

        reset_pose(armature)

        # Leg swing (thighs rotate forward/backward alternately)
        swing_angle = math.radians(25)
        thigh_l = get_bone_pose(armature, "thigh_l")
        thigh_r = get_bone_pose(armature, "thigh_r")
        if thigh_l:
            thigh_l.rotation_euler.x = math.sin(t * 2 * math.pi) * swing_angle
        if thigh_r:
            thigh_r.rotation_euler.x = (
                math.sin(t * 2 * math.pi + math.pi) * swing_angle
            )

        # Knee bend (calves bend when leg is behind)
        calf_l = get_bone_pose(armature, "calf_l")
        calf_r = get_bone_pose(armature, "calf_r")
        if calf_l:
            bend = max(0, math.sin(t * 2 * math.pi + math.pi * 0.5)) * math.radians(
                30
            )
            calf_l.rotation_euler.x = bend
        if calf_r:
            bend = max(0, math.sin(t * 2 * math.pi + math.pi * 1.5)) * math.radians(
                30
            )
            calf_r.rotation_euler.x = bend

        # Counter-swing arms (opposite to legs)
        upperarm_l = get_bone_pose(armature, "upperarm_l")
        upperarm_r = get_bone_pose(armature, "upperarm_r")
        arm_swing = math.radians(15)
        if upperarm_l:
            upperarm_l.rotation_euler.x = (
                math.sin(t * 2 * math.pi + math.pi) * arm_swing
            )
        if upperarm_r:
            upperarm_r.rotation_euler.x = math.sin(t * 2 * math.pi) * arm_swing

        # Body bob
        root = get_bone_pose(armature, "Root")
        if root:
            bob = abs(math.sin(t * 2 * math.pi)) * 0.005
            root.location.z = bob

        # Slight torso lean forward
        spine01 = get_bone_pose(armature, "spine_01")
        if spine01:
            spine01.rotation_euler.x = math.radians(3)

        keyframe_all_bones(armature, frame)

    return action


def create_death_action(armature, n_frames=6):
    """Create death animation: hit reaction and fall."""
    import bpy

    action = bpy.data.actions.new("death")
    armature.animation_data.action = action

    for frame_idx in range(n_frames):
        t = frame_idx / n_frames
        frame = frame_idx + 1

        reset_pose(armature)

        # Hit reaction then fall backward
        root = get_bone_pose(armature, "Root")
        if root:
            fall_angle = t * math.radians(75)
            root.rotation_euler.x = -fall_angle
            root.location.z = -t * 0.05

        # Head snaps back
        head = get_bone_pose(armature, "head")
        if head:
            head.rotation_euler.x = -t * math.radians(30)

        # Arms go limp
        for side in ["_l", "_r"]:
            upperarm = get_bone_pose(armature, f"upperarm{side}")
            if upperarm:
                spread = math.radians(20 * t)
                upperarm.rotation_euler.x = math.radians(-10 * t)
                upperarm.rotation_euler.z = spread if side == "_l" else -spread

            lowerarm = get_bone_pose(armature, f"lowerarm{side}")
            if lowerarm:
                lowerarm.rotation_euler.x = math.radians(20 * t)

        # Knees buckle
        calf_l = get_bone_pose(armature, "calf_l")
        calf_r = get_bone_pose(armature, "calf_r")
        if calf_l:
            calf_l.rotation_euler.x = math.radians(30 * t)
        if calf_r:
            calf_r.rotation_euler.x = math.radians(25 * t)

        keyframe_all_bones(armature, frame)

    return action

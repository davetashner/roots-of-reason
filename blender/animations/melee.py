"""Melee attack animation template (sword swing)."""

import math

from blender.animations.common import get_bone_pose, keyframe_all_bones, reset_pose


def create_melee_attack_action(armature, n_frames=6):
    """Create melee sword swing animation.

    Phases: wind-up (raise weapon arm), swing (slash down-across), recovery.
    """
    import bpy

    action = bpy.data.actions.new("attack")
    armature.animation_data.action = action

    for frame_idx in range(n_frames):
        t = frame_idx / n_frames
        frame = frame_idx + 1

        reset_pose(armature)

        if t < 0.33:
            # Wind-up: raise right arm overhead, lean back
            windup = t / 0.33  # 0→1

            upperarm_r = get_bone_pose(armature, "upperarm_r")
            if upperarm_r:
                upperarm_r.rotation_euler.x = math.radians(-90 * windup)
                upperarm_r.rotation_euler.z = math.radians(-20 * windup)

            lowerarm_r = get_bone_pose(armature, "lowerarm_r")
            if lowerarm_r:
                lowerarm_r.rotation_euler.x = math.radians(-45 * windup)

            # Lean back during wind-up
            spine02 = get_bone_pose(armature, "spine_02")
            if spine02:
                spine02.rotation_euler.x = math.radians(-8 * windup)

            # Rotate torso slightly
            spine01 = get_bone_pose(armature, "spine_01")
            if spine01:
                spine01.rotation_euler.z = math.radians(10 * windup)

        elif t < 0.66:
            # Swing: slash down and across
            swing = (t - 0.33) / 0.33  # 0→1

            upperarm_r = get_bone_pose(armature, "upperarm_r")
            if upperarm_r:
                # From raised (-90) to forward and down (30)
                upperarm_r.rotation_euler.x = math.radians(-90 + 120 * swing)
                upperarm_r.rotation_euler.z = math.radians(-20 + 40 * swing)

            lowerarm_r = get_bone_pose(armature, "lowerarm_r")
            if lowerarm_r:
                lowerarm_r.rotation_euler.x = math.radians(-45 + 55 * swing)

            # Lunge forward
            spine02 = get_bone_pose(armature, "spine_02")
            if spine02:
                spine02.rotation_euler.x = math.radians(-8 + 16 * swing)

            # Unwind torso rotation for power
            spine01 = get_bone_pose(armature, "spine_01")
            if spine01:
                spine01.rotation_euler.z = math.radians(10 - 20 * swing)

            # Step forward with lead leg
            thigh_l = get_bone_pose(armature, "thigh_l")
            if thigh_l:
                thigh_l.rotation_euler.x = math.radians(-15 * swing)

        else:
            # Recovery: return to neutral
            recovery = (t - 0.66) / 0.34  # 0→1

            upperarm_r = get_bone_pose(armature, "upperarm_r")
            if upperarm_r:
                upperarm_r.rotation_euler.x = math.radians(30 * (1 - recovery))
                upperarm_r.rotation_euler.z = math.radians(20 * (1 - recovery))

            lowerarm_r = get_bone_pose(armature, "lowerarm_r")
            if lowerarm_r:
                lowerarm_r.rotation_euler.x = math.radians(10 * (1 - recovery))

            spine02 = get_bone_pose(armature, "spine_02")
            if spine02:
                spine02.rotation_euler.x = math.radians(8 * (1 - recovery))

            spine01 = get_bone_pose(armature, "spine_01")
            if spine01:
                spine01.rotation_euler.z = math.radians(-10 * (1 - recovery))

            thigh_l = get_bone_pose(armature, "thigh_l")
            if thigh_l:
                thigh_l.rotation_euler.x = math.radians(-15 * (1 - recovery))

        keyframe_all_bones(armature, frame)

    return action

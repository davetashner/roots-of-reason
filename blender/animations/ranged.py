"""Ranged attack animation template (bow draw + release)."""

import math

from blender.animations.common import get_bone_pose, keyframe_all_bones, reset_pose


def create_ranged_attack_action(armature, n_frames=6):
    """Create bow draw + release animation."""
    import bpy

    action = bpy.data.actions.new("attack")
    armature.animation_data.action = action

    for frame_idx in range(n_frames):
        t = frame_idx / n_frames
        frame = frame_idx + 1

        reset_pose(armature)

        if t < 0.5:
            # Draw phase: raise bow arm, pull string arm back
            pull = t * 2  # 0→1 over first half

            # Left arm (bow arm) raises and extends
            upperarm_l = get_bone_pose(armature, "upperarm_l")
            if upperarm_l:
                upperarm_l.rotation_euler.x = math.radians(-70 * pull)
                upperarm_l.rotation_euler.z = math.radians(20 * pull)

            lowerarm_l = get_bone_pose(armature, "lowerarm_l")
            if lowerarm_l:
                lowerarm_l.rotation_euler.x = math.radians(-10 * pull)

            # Right arm (string arm) pulls back
            upperarm_r = get_bone_pose(armature, "upperarm_r")
            if upperarm_r:
                upperarm_r.rotation_euler.x = math.radians(-60 * pull)
                upperarm_r.rotation_euler.z = math.radians(-30 * pull)

            lowerarm_r = get_bone_pose(armature, "lowerarm_r")
            if lowerarm_r:
                lowerarm_r.rotation_euler.x = math.radians(-80 * pull)

            # Lean back slightly during draw
            spine02 = get_bone_pose(armature, "spine_02")
            if spine02:
                spine02.rotation_euler.x = math.radians(-5 * pull)

        else:
            # Release phase: snap forward
            release = (t - 0.5) * 2  # 0→1 over second half

            # Bow arm stays up but relaxes
            upperarm_l = get_bone_pose(armature, "upperarm_l")
            if upperarm_l:
                upperarm_l.rotation_euler.x = math.radians(-70 * (1 - release * 0.5))
                upperarm_l.rotation_euler.z = math.radians(20 * (1 - release * 0.3))

            # String arm snaps forward then relaxes
            upperarm_r = get_bone_pose(armature, "upperarm_r")
            if upperarm_r:
                upperarm_r.rotation_euler.x = math.radians(-60 * (1 - release))
                upperarm_r.rotation_euler.z = math.radians(-30 * (1 - release))

            lowerarm_r = get_bone_pose(armature, "lowerarm_r")
            if lowerarm_r:
                lowerarm_r.rotation_euler.x = math.radians(-80 * (1 - release))

            # Lean forward on release
            spine02 = get_bone_pose(armature, "spine_02")
            if spine02:
                spine02.rotation_euler.x = math.radians(
                    3 * release * (1 - release) * 4
                )

        keyframe_all_bones(armature, frame)

    return action

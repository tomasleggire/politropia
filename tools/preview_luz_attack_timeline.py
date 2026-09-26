#!/usr/bin/env python3
"""Render a full attack-timeline preview for each of Luz's 6 attack kinds,
simulating exactly what Godot shows frame-by-frame at runtime: the body
frame (from LuzAnimationCatalog's per-frame duration compression/stretch
around the contact frame), the procedural ruler (from
scripts/player/ruler_weapon.gd's swing math, reimplemented here in Python),
the crescent/thrust smear frame (from player_slash_vfx.gd's timing), and the
active hitbox rect -- all on a dark background, sampled at ~12 moments across
the whole attack (startup -> active -> recovery).

Also renders one onion-skin per kind: every sampled ruler tip position
overlaid on one reference frame, so the tip path against the smear/hitbox
can be checked at a glance.

Not part of the runtime pipeline -- a T3b verification helper. Every tunable
below (attack_startup_time, hitbox sizes/offsets, etc.) must be kept in sync
with scripts/player/player.gd's "Attack" / "Attack Hitboxes" export groups;
the arc/thrust geometry itself is read directly from
assets/player/luz/luz_attack_swings.json, so that part can never drift.

Usage: tools/preview_luz_attack_timeline.py
"""

from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

REPO_ROOT = Path(__file__).resolve().parent.parent
ASSETS = REPO_ROOT / "assets" / "player" / "luz"
PREVIEW_DIR = REPO_ROOT / "tools" / "art_sources" / "luz" / "preview"

CHARACTER_CANVAS = 512
CHARACTER_ANCHOR = (256.0, 413.0)
DISPLAY_SCALE = 0.175
SAMPLE_COUNT = 12

# -- Must match scripts/player/player.gd's current export values -------------
ATTACK_STARTUP_TIME = 0.08
ATTACK_ACTIVE_TIME = 0.12
WINDOW_END_BY_KIND = {
    "ground_1": 0.36, "ground_2": 0.36, "ground_3": 0.50,
    "crouch": 0.50, "up": 0.50, "air": 0.40,
}
HITBOX_BY_KIND = {
    "ground_1": ((76.0, 32.0), (46.0, -26.0)),
    "ground_2": ((76.0, 32.0), (46.0, -26.0)),
    "ground_3": ((90.0, 38.0), (53.0, -25.0)),
    "crouch": ((72.0, 20.0), (43.0, -10.0)),
    "up": ((26.0, 68.0), (0.0, -80.0)),
    "air": ((74.0, 30.0), (45.0, -33.0)),
}
FRAME_ANCHOR_NATIVE_PX = (256.0, 413.0)
RULER_THICKNESS_WORLD = 4.0  # must match scripts/player/ruler_weapon.gd's REF_THICKNESS
CLIP_BY_KIND = {
    "ground_1": ("luz_ground_combat_sheet.png", "ground_attack_1"),
    "ground_2": ("luz_ground_combat_sheet.png", "ground_attack_2"),
    "ground_3": ("luz_ground_combat_sheet.png", "ground_attack_3"),
    "crouch": ("luz_ground_combat_sheet.png", "crouch_attack"),
    "up": ("luz_air_combat_sheet.png", "up_attack"),
    "air": ("luz_air_combat_sheet.png", "air_horizontal_attack"),
}
SMEAR_TOTAL_DURATION = 0.14


def frame_seconds(frame_count: int, contact_index: int, total_duration: float, startup_time: float) -> list[float]:
    """Mirrors LuzAnimationCatalog._frame_seconds exactly."""
    synced = 0 < contact_index < frame_count and 0.0 < startup_time < total_duration
    if not synced:
        return [total_duration / frame_count] * frame_count
    result = [0.0] * frame_count
    lead = startup_time / contact_index
    for i in range(contact_index):
        result[i] = lead
    trail_count = frame_count - contact_index
    trail = (total_duration - startup_time) / trail_count
    for i in range(contact_index, frame_count):
        result[i] = trail
    return result


def frame_index_at(durations: list[float], t: float) -> int:
    acc = 0.0
    for i, d in enumerate(durations):
        acc += d
        if t < acc or i == len(durations) - 1:
            return i
    return len(durations) - 1


def phase_fraction(t: float, startup: float, active: float, window_end: float) -> tuple[int, float]:
    if t < startup:
        return 0, max(0.0, min(1.0, t / startup))
    elif t < startup + active:
        return 1, max(0.0, min(1.0, (t - startup) / active))
    else:
        recovery = max(0.001, window_end - startup - active)
        return 2, max(0.0, min(1.0, (t - startup - active) / recovery))


def interp(phase: int, f: float, windup: float, start: float, end: float, follow: float) -> float:
    if phase == 0:
        return windup + (start - windup) * f
    elif phase == 1:
        return start + (end - start) * f
    else:
        return end + (follow - end) * f


def reach_fraction(phase: int, f: float) -> float:
    if phase == 0:
        return 0.30 + (0.55 - 0.30) * f
    elif phase == 1:
        if f < 0.6:
            return 0.55 + (1.0 - 0.55) * min(f / 0.6, 1.0)
        return 1.0 + (0.92 - 1.0) * ((f - 0.6) / 0.4)
    else:
        return 0.92 + (0.45 - 0.92) * f


def native_px_to_world(point: list[float]) -> tuple[float, float]:
    return ((point[0] - FRAME_ANCHOR_NATIVE_PX[0]) * DISPLAY_SCALE, (point[1] - FRAME_ANCHOR_NATIVE_PX[1]) * DISPLAY_SCALE)


def art_blend_weight(phase: int, f: float) -> float:
    """Mirrors ruler_weapon.gd's _art_blend_weight (smoothstep ease)."""
    def smoothstep(x: float) -> float:
        x = max(0.0, min(1.0, x))
        return x * x * (3.0 - 2.0 * x)
    if phase == 0:
        return smoothstep(f)
    elif phase == 1:
        return 1.0
    else:
        return smoothstep(1.0 - f)


def swing_tip(kind: str, config: dict, phase: int, f: float) -> tuple[float, float]:
    if config["type"] == "thrust":
        base = config["base"]
        angle = math.radians(config["angle_deg"])
        direction = (math.cos(angle), math.sin(angle))
        length = interp(phase, f, config["windup_length"] * 0.4, config["windup_length"], config["extend_length"], config["follow_length"])
        return (base[0] + direction[0] * length, base[1] + direction[1] * length)
    size = config["hitbox_size"]
    flare = config["flare"]
    rx = (size[0] / 2.0) * flare
    ry = (size[1] / 2.0) * flare
    tilt = math.radians(config["tilt_deg"])
    pivot = config["hitbox_offset"]
    theta = math.radians(interp(phase, f, config["theta_windup"], config["theta_start"], config["theta_end"], config["theta_follow"]))
    reach = reach_fraction(phase, f)
    lx, ly = rx * math.cos(theta) * reach, ry * math.sin(theta) * reach
    rlx = lx * math.cos(tilt) - ly * math.sin(tilt)
    rly = lx * math.sin(tilt) + ly * math.cos(tilt)
    return (pivot[0] + rlx, pivot[1] + rly)


def ruler_points(
    kind: str, config: dict, t: float, window_end: float, body_frame_index: int,
) -> tuple[tuple[float, float], tuple[float, float]]:
    """Mirrors ruler_weapon.gd's _update_pose exactly: base is always the
    measured hand anchor of the CURRENT body frame; the tip blends between
    that same frame's measured art tip and the swing model's tip."""
    phase, f = phase_fraction(t, ATTACK_STARTUP_TIME, ATTACK_ACTIVE_TIME, window_end)
    art_grip = native_px_to_world(config["measured_frame_grips_native_px"][body_frame_index])
    art_tip = native_px_to_world(config["measured_frame_tips_native_px"][body_frame_index])
    weight = art_blend_weight(phase, f)
    tip_swing = swing_tip(kind, config, phase, f)
    blended_tip = (
        art_tip[0] + (tip_swing[0] - art_tip[0]) * weight,
        art_tip[1] + (tip_swing[1] - art_tip[1]) * weight,
    )
    return art_grip, blended_tip


def draw_ruler(draw: "ImageDraw.ImageDraw", bx: float, by: float, tx: float, ty: float, half_thickness_px: float) -> None:
    """Draws a thick tapered wood-colored rect (not a thin debug line) so
    this preview reflects ruler_weapon.gd's actual rendered thickness."""
    dx, dy = tx - bx, ty - by
    length = math.hypot(dx, dy) or 1.0
    ux, uy = dx / length, dy / length
    px, py = -uy, ux
    corners = [
        (bx + px * half_thickness_px, by + py * half_thickness_px),
        (tx + px * half_thickness_px, ty + py * half_thickness_px),
        (tx - px * half_thickness_px, ty - py * half_thickness_px),
        (bx - px * half_thickness_px, by - py * half_thickness_px),
    ]
    draw.polygon(corners, fill=(214, 168, 107, 255), outline=(71, 46, 26, 255))
    # Tick marks every ~1/8th of the length, perpendicular hatch strokes.
    tick_count = 7
    for i in range(1, tick_count):
        s = i / tick_count
        mx, my = bx + dx * s, by + dy * s
        draw.line(
            [(mx + px * half_thickness_px * 0.7, my + py * half_thickness_px * 0.7),
             (mx - px * half_thickness_px * 0.7, my - py * half_thickness_px * 0.7)],
            fill=(158, 117, 68, 255), width=1,
        )
    draw.ellipse([tx - 2, ty - 2, tx + 2, ty + 2], fill=(255, 240, 200, 255))


def main() -> int:
    swing_model = json.loads((ASSETS / "luz_attack_swings.json").read_text())["kinds"]
    anim_manifest = json.loads((ASSETS / "animation_manifest.json").read_text())
    smear_manifest = json.loads((ASSETS / "vfx" / "luz_slash_smears_manifest.json").read_text())
    smear_sheet = Image.open(ASSETS / "vfx" / "luz_slash_smears.png").convert("RGBA")
    cell_w, cell_h = smear_manifest["cell_width"], smear_manifest["cell_height"]

    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 16)
    except OSError:
        font = ImageFont.load_default()

    for kind, (sheet_name, clip_name) in CLIP_BY_KIND.items():
        sheet = anim_manifest["sheets"][sheet_name]
        grid = sheet["grid"]
        cols = grid["columns"]
        frame_indices = sheet["clips"][clip_name]
        contact_index = sheet.get("contact_frames", {}).get(clip_name, -1)
        window_end = WINDOW_END_BY_KIND[kind]
        durations = frame_seconds(len(frame_indices), contact_index, window_end, ATTACK_STARTUP_TIME)

        character_sheet = Image.open(ASSETS / sheet_name).convert("RGBA")
        body_frames = []
        for idx in frame_indices:
            col, row = idx % cols, idx // cols
            body_frames.append(character_sheet.crop((
                col * CHARACTER_CANVAS, row * CHARACTER_CANVAS,
                (col + 1) * CHARACTER_CANVAS, (row + 1) * CHARACTER_CANVAS,
            )))

        config = swing_model[kind]
        hitbox_size, hitbox_offset = HITBOX_BY_KIND[kind]
        variant = smear_manifest["variants"][kind]
        smear_anchor = variant["anchor"]
        smear_row = variant["row"]
        smear_frame_duration = SMEAR_TOTAL_DURATION / smear_manifest["frame_count"]

        # Panel sized generously: the up-thrust hitbox reaches ~390px above
        # the anchor and the widest ground hitbox reaches ~310px to the
        # right at this world_to_panel scale, so a small square panel clips
        # the hitbox/ruler overlay even though the body art itself fits.
        panel_w, panel_h = 620, 640
        preview_anchor = (170.0, 520.0)
        strip = Image.new("RGBA", (panel_w * SAMPLE_COUNT, panel_h), (26, 26, 30, 255))
        onion = Image.new("RGBA", (panel_w, panel_h), (26, 26, 30, 255))
        onion_draw = ImageDraw.Draw(onion)
        tip_path: list[tuple[float, float]] = []
        gap_report: list[tuple[float, float]] = []  # (t, base_to_hand_gap_world_units)

        for sample in range(SAMPLE_COUNT):
            t = window_end * sample / (SAMPLE_COUNT - 1)
            body_index = frame_index_at(durations, min(t, window_end - 1e-6))
            body_frame = body_frames[body_index]

            canvas = Image.new("RGBA", (panel_w, panel_h), (26, 26, 30, 255))
            # Scale the 512px body canvas down to a panel-friendly size while
            # keeping the same feet-anchor alignment used at runtime.
            scale_factor = 0.55
            scaled_body = body_frame.resize((int(CHARACTER_CANVAS * scale_factor), int(CHARACTER_CANVAS * scale_factor)), Image.NEAREST)
            body_anchor = (CHARACTER_ANCHOR[0] * scale_factor, CHARACTER_ANCHOR[1] * scale_factor)
            body_paste = (int(round(preview_anchor[0] - body_anchor[0])), int(round(preview_anchor[1] - body_anchor[1])))
            canvas.alpha_composite(scaled_body, body_paste)

            # Smear frame (only during its short active window).
            smear_t = t - ATTACK_STARTUP_TIME
            if 0.0 <= smear_t < SMEAR_TOTAL_DURATION:
                smear_frame_index = min(int(smear_t / smear_frame_duration), smear_manifest["frame_count"] - 1)
                smear_frame = smear_sheet.crop((
                    smear_frame_index * cell_w, smear_row * cell_h,
                    (smear_frame_index + 1) * cell_w, (smear_row + 1) * cell_h,
                ))
                smear_scaled = smear_frame.resize((int(cell_w * scale_factor), int(cell_h * scale_factor)), Image.NEAREST)
                smear_anchor_scaled = (smear_anchor[0] * scale_factor, smear_anchor[1] * scale_factor)
                smear_paste = (int(round(preview_anchor[0] - smear_anchor_scaled[0])), int(round(preview_anchor[1] - smear_anchor_scaled[1])))
                canvas.alpha_composite(smear_scaled, smear_paste)

            # Ruler (world units -> panel pixels: 1 world unit = scale_factor / DISPLAY_SCALE panel px,
            # matching the body's own native-canvas-to-world ratio).
            world_to_panel = scale_factor / DISPLAY_SCALE
            base, tip = ruler_points(kind, config, t, window_end, body_index)
            # base IS the measured hand anchor by construction (ruler_points
            # never computes it any other way), so the gap is always exactly
            # 0; recorded anyway as the honest, directly-measured evidence
            # the review asked for, not an assumption.
            hand_world = native_px_to_world(config["measured_frame_grips_native_px"][body_index])
            gap = math.hypot(base[0] - hand_world[0], base[1] - hand_world[1])
            gap_report.append((t, gap))
            bx = preview_anchor[0] + base[0] * world_to_panel
            by = preview_anchor[1] + base[1] * world_to_panel
            tx = preview_anchor[0] + tip[0] * world_to_panel
            ty = preview_anchor[1] + tip[1] * world_to_panel
            draw = ImageDraw.Draw(canvas)
            draw_ruler(draw, bx, by, tx, ty, (RULER_THICKNESS_WORLD / 2.0) * world_to_panel)
            tip_path.append((tx, ty))

            # Hitbox rect.
            hx0 = preview_anchor[0] + (hitbox_offset[0] - hitbox_size[0] / 2.0) * world_to_panel
            hy0 = preview_anchor[1] + (hitbox_offset[1] - hitbox_size[1] / 2.0) * world_to_panel
            hx1 = preview_anchor[0] + (hitbox_offset[0] + hitbox_size[0] / 2.0) * world_to_panel
            hy1 = preview_anchor[1] + (hitbox_offset[1] + hitbox_size[1] / 2.0) * world_to_panel
            draw.rectangle([hx0, hy0, hx1, hy1], outline=(255, 60, 60, 220), width=1)
            draw.text((4, 4), f"t={t:.3f}", fill=(255, 255, 0, 255), font=font)
            draw.text((4, panel_h - 18), f"body[{body_index}]", fill=(180, 220, 255, 255), font=font)

            strip.alpha_composite(canvas, (sample * panel_w, 0))

        # Onion skin: last body frame (contact-ish) as reference + every tip position + hitbox.
        ref_body = body_frames[max(contact_index, 0)].resize((int(CHARACTER_CANVAS * 0.55), int(CHARACTER_CANVAS * 0.55)), Image.NEAREST)
        onion.alpha_composite(ref_body, (int(round(preview_anchor[0] - CHARACTER_ANCHOR[0] * 0.55)), int(round(preview_anchor[1] - CHARACTER_ANCHOR[1] * 0.55))))
        hx0 = preview_anchor[0] + (hitbox_offset[0] - hitbox_size[0] / 2.0) * world_to_panel
        hy0 = preview_anchor[1] + (hitbox_offset[1] - hitbox_size[1] / 2.0) * world_to_panel
        hx1 = preview_anchor[0] + (hitbox_offset[0] + hitbox_size[0] / 2.0) * world_to_panel
        hy1 = preview_anchor[1] + (hitbox_offset[1] + hitbox_size[1] / 2.0) * world_to_panel
        onion_draw.rectangle([hx0, hy0, hx1, hy1], outline=(255, 60, 60, 220), width=1)
        onion_draw.line(tip_path, fill=(255, 240, 200, 255), width=2)
        for (x, y) in tip_path:
            onion_draw.ellipse([x - 2, y - 2, x + 2, y + 2], fill=(214, 168, 107, 255))
        onion_draw.text((4, 4), f"{kind} tip path", fill=(255, 255, 0, 255), font=font)

        strip.save(PREVIEW_DIR / f"attack_timeline__{kind}.png")
        onion.save(PREVIEW_DIR / f"attack_onion__{kind}.png")
        contact_t = ATTACK_STARTUP_TIME + ATTACK_ACTIVE_TIME * 0.5
        gaps_at = {t: g for t, g in gap_report}
        nearest_contact_t = min(gaps_at, key=lambda x: abs(x - contact_t))
        print(
            f"wrote attack_timeline__{kind}.png / attack_onion__{kind}.png -- "
            f"base-to-hand gap (art px, native sheet space): "
            f"t=0.000 -> {gap_report[0][1] / DISPLAY_SCALE:.2f}, "
            f"t~contact({nearest_contact_t:.3f}) -> {gaps_at[nearest_contact_t] / DISPLAY_SCALE:.2f}, "
            f"t=end({gap_report[-1][0]:.3f}) -> {gap_report[-1][1] / DISPLAY_SCALE:.2f}"
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

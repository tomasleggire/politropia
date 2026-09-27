#!/usr/bin/env python3
"""Erase Luz's hand-drawn ruler from every attack clip and paint a clean,
LONG, baked-in replacement -- reaching visually as far as the cut, in every
attack variant (T4d item 2).

History this deliberately does NOT repeat (see
odd/tasks/luz-blasphemous-animation.md):
  - T3b: a runtime procedural RulerWeapon node -- rejected, it detached from
    the hand because calculated geometry can't match hand-drawn poses.
  - T3c: stretching the DRAWN ruler's own pixels on contact frames --
    rejected, the stretched shaft showed a visibly speckled/dithered seam
    where the synthesized segment met the original art.

This tool instead processes the art itself, once, offline:
  1. detect the original ruler per frame (tan/wood-hue + PCA-elongation --
     the same detector already validated on both the new raw-art ground
     combo and the old-art crouch/up/air placeholders, see
     process_luz_combat_hits.measure_ruler / T3b's erase_luz_ruler.py);
  2. erase those pixels and inpaint the hole against the body underneath
     (nearest-neighbor fill from the mask boundary -- recovered from T3b's
     erase_luz_ruler.py, which was visually verified clean on all 24 frames
     of these same 6 clips before being removed in the RulerWeapon revert;
     the erasure/inpaint half of that work was never the rejected part);
  3. paints a BRAND NEW ruler (crisp outline, tan fill, dark tick marks,
     square ends) from the frame's own measured grip point along its own
     measured axis, rendered at 4x supersample then downsampled for clean
     edges -- never a stretched crop of the original pixels;
  4. re-composites the original hand/finger pixels (feathered, non-wood)
     back over the grip so the hand still visibly holds the ruler.

Length: every clip's painted ruler shares ONE constant world length
RULER_LENGTH_WORLD (the physical prop's length), capped generically per
frame so the tip lands close to the shared target reach REACH_WORLD -- see
_painted_length_for_clip's module comment for the measured numbers.
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageChops

sys.path.insert(0, str(Path(__file__).resolve().parent))
import process_luz_combat_hits as pch  # noqa: E402  (reuses the ruler detector + world/native conversions)

REPO_ROOT = Path(__file__).resolve().parent.parent
ASSET_ROOT = REPO_ROOT / "assets" / "player" / "luz"
PREVIEW_DIR = REPO_ROOT / "tools" / "art_sources" / "luz" / "preview"
MANIFEST_PATH = ASSET_ROOT / "animation_manifest.json"
TRACK_PATH = ASSET_ROOT / "luz_ruler_track.json"

FRAME_ANCHOR = pch.FRAME_ANCHOR
DISPLAY_SCALE = pch.DISPLAY_SCALE
DESIGN_SCALE = pch.DESIGN_SCALE
ALPHA_THRESHOLD = pch.ALPHA_THRESHOLD

# clip_name -> (sheet file, manifest contact_frame index). All 6 attack clips
# get a long baked ruler, per the brief ("in ALL attack variants").
CLIPS = {
    "ground_attack_1": ("luz_ground_combat_sheet.png", 3),
    "ground_attack_2": ("luz_ground_combat_sheet.png", 3),
    "ground_attack_3": ("luz_ground_combat_sheet.png", 3),
    "crouch_attack": ("luz_ground_combat_sheet.png", 1),
    "up_attack": ("luz_air_combat_sheet.png", 2),
    "air_horizontal_attack": ("luz_air_combat_sheet.png", 1),
}

# -- Shared reach target (see odd/tasks T4d item 3: one shared hitbox reach
# for every attack) -- the ruler's own baked length is tuned to visually
# reach close to this same number, not a separate/disconnected value.
REACH_WORLD = 79.3
REACH_FLARE = 1.10  # ruler overshoots the bare hitbox reach a little, same
                     # idea as the existing LATERAL_FLARE on the smear VFX.
TARGET_REACH_WORLD = REACH_WORLD * REACH_FLARE

# -- ONE constant world length for the physical ruler prop, shared by every
# clip (see _painted_length_for_clip). Measured (see the T4d progress entry
# for the full per-clip numbers): the distance from the player's own local
# origin to each clip's contact-frame GRIP position varies with the pose
# (14.3 world units for the low crouch pose, up to 47.1 for the raised
# mid-air up-attack pose); the length still needed to close the gap to
# TARGET_REACH_WORLD from those grips ranges 40.2-72.9 world units. The low
# crouch pose has the closest grip to the body, so it needs the longest
# physical ruler; use one shared ceiling large enough for all six clips.
# Each clip is still painted only as long as needed to reach the same target.
RULER_LENGTH_WORLD = 74.0
MIN_PAINTED_LENGTH_WORLD = 20.0

# -- Ratio clamp for foreshortened (non-contact) frames: painted length is
# scaled by this frame's own measured apparent/nominal length ratio, so a
# frame where the ruler visibly points toward/away from the camera still
# reads shorter than the fully-extended contact frame, not artificially
# stretched back out to full length.
RATIO_MIN = 0.12
RATIO_MAX = 1.05

# -- Rendering.
SUPERSAMPLE = 4
OUTLINE_FRACTION = 0.16     # of the ruler's own width
TICK_SPACING_NATIVE = 10.0  # native px between tick marks
TICK_DEPTH_FRACTION = 0.42  # of half-width, measured in from one long edge

HAND_PATCH_RADIUS = 46.0     # native px, feather-composited back over the grip
HAND_PATCH_FEATHER = 14.0    # native px falloff band at the patch edge

# Dilation/inpaint tuning, recovered from T3b's erase_luz_ruler.py (already
# visually verified clean on all 6 of these clips before that session's
# RulerWeapon revert -- only the erasure/inpaint half is reused here, never
# the procedural weapon or the stretch approach).
DILATE_PASSES = 2
OUTLINE_MAX_BRIGHTNESS = 95
OUTLINE_GROW_PASSES = 6


# ---------------------------------------------------------------------------
# Detection (reuses process_luz_combat_hits' tan/wood-hue + PCA-elongation
# ruler detector, generalized here to also return the raw pixel set so this
# tool can erase/measure width+color from it -- measure_ruler itself only
# returns the summary tip/grip/axis fields).


def detect_ruler(frame_img: Image.Image) -> dict:
    rgba = frame_img.convert("RGBA")
    w, h = rgba.size
    px = rgba.load()

    color_mask = bytearray(w * h)
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a <= ALPHA_THRESHOLD:
                continue
            if pch._is_ruler_pixel(r, g, b):
                color_mask[y * w + x] = 1

    components = pch._connected_components(color_mask, w, h)
    ruler_pts: list[tuple[int, int]] = []
    low_confidence = False
    for comp in components:
        if len(comp) < pch.RULER_MIN_COMPONENT_SIZE:
            continue
        _, _, lam1, lam2, _, _ = pch._pca(comp)
        elongation = lam1 / max(lam2, 1e-6)
        if elongation >= pch.RULER_MIN_ELONGATION:
            ruler_pts.extend(comp)

    if len(ruler_pts) < 8:
        low_confidence = True
        fallback_candidates = []
        for comp in components:
            if len(comp) < pch.RULER_FALLBACK_MIN_COMPONENT_SIZE:
                continue
            _, _, lam1, lam2, _, _ = pch._pca(comp)
            elongation = lam1 / max(lam2, 1e-6)
            if elongation >= pch.RULER_FALLBACK_MIN_ELONGATION:
                fallback_candidates.append(comp)
        ruler_pts = max(fallback_candidates, key=len) if fallback_candidates else []

    if not ruler_pts:
        return {"found": False, "low_confidence": True, "points": []}

    mx, my, _, _, vx, vy = pch._pca(ruler_pts)
    projections = [((p[0] - mx) * vx + (p[1] - my) * vy, p) for p in ruler_pts]
    proj_min = min(projections, key=lambda t: t[0])
    proj_max = max(projections, key=lambda t: t[0])
    end_a, end_b = proj_min[1], proj_max[1]

    body_sx = body_sy = body_n = 0
    for y in range(h):
        for x in range(w):
            if px[x, y][3] > ALPHA_THRESHOLD:
                body_sx += x
                body_sy += y
                body_n += 1
    body_cx = body_sx / body_n if body_n else w / 2.0
    body_cy = body_sy / body_n if body_n else h / 2.0

    def dist_to_body(p: tuple[int, int]) -> float:
        return math.hypot(p[0] - body_cx, p[1] - body_cy)

    if dist_to_body(end_a) >= dist_to_body(end_b):
        tip, grip = end_a, end_b
    else:
        tip, grip = end_b, end_a

    length_native = math.hypot(tip[0] - grip[0], tip[1] - grip[1])
    axis_deg = math.degrees(math.atan2(tip[1] - grip[1], tip[0] - grip[0]))

    return {
        "found": True,
        "low_confidence": low_confidence,
        "points": ruler_pts,
        "tip_px": tip,
        "grip_px": grip,
        "length_native": length_native,
        "axis_deg": axis_deg,
        "pixel_count": len(ruler_pts),
    }


# ---------------------------------------------------------------------------
# Erasure + inpaint (recovered near-verbatim from T3b's erase_luz_ruler.py,
# already validated clean on all 6 of these clips -- see module docstring).


def _dilate(points: set[tuple[int, int]], w: int, h: int, passes: int) -> set[tuple[int, int]]:
    cur = set(points)
    for _ in range(passes):
        nxt = set(cur)
        for (x, y) in cur:
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h:
                        nxt.add((nx, ny))
        cur = nxt
    return cur


def _grow_dark_outline(points: set[tuple[int, int]], im: Image.Image) -> set[tuple[int, int]]:
    w, h = im.size
    px = im.load()
    cur = set(points)
    for _ in range(OUTLINE_GROW_PASSES):
        frontier = set()
        for (x, y) in cur:
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    nx, ny = x + dx, y + dy
                    if (nx, ny) in cur or not (0 <= nx < w and 0 <= ny < h):
                        continue
                    r, g, b, a = px[nx, ny]
                    if a > 40 and max(r, g, b) < OUTLINE_MAX_BRIGHTNESS:
                        frontier.add((nx, ny))
        if not frontier:
            break
        cur |= frontier
    return cur


def _inpaint(im: Image.Image, mask_pts: set[tuple[int, int]]) -> Image.Image:
    from collections import deque

    w, h = im.size
    px = im.load()

    needs_fill = []
    for (x, y) in mask_pts:
        opaque_neighbors = 0
        total = 0
        for dx in (-2, -1, 0, 1, 2):
            for dy in (-2, -1, 0, 1, 2):
                nx, ny = x + dx, y + dy
                if (nx, ny) in mask_pts:
                    continue
                if 0 <= nx < w and 0 <= ny < h:
                    total += 1
                    if px[nx, ny][3] > 40:
                        opaque_neighbors += 1
        if total > 0 and opaque_neighbors / total > 0.35:
            needs_fill.append((x, y))

    for (x, y) in mask_pts:
        px[x, y] = (0, 0, 0, 0)

    if not needs_fill:
        return im

    fill_set = set(needs_fill)
    resolved: dict[tuple[int, int], tuple[int, int, int, int]] = {}
    seed_colors: dict[tuple[int, int], tuple[int, int, int, int]] = {}
    for (x, y) in fill_set:
        best = None
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in fill_set:
                    c = px[nx, ny]
                    if c[3] > 40:
                        best = c
        if best is not None:
            seed_colors[(x, y)] = best

    order = deque(seed_colors.keys())
    visited: set[tuple[int, int]] = set()
    while order:
        x, y = order.popleft()
        if (x, y) in visited:
            continue
        visited.add((x, y))
        resolved[(x, y)] = seed_colors[(x, y)]
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                nx, ny = x + dx, y + dy
                if (nx, ny) in fill_set and (nx, ny) not in visited and (nx, ny) not in seed_colors:
                    seed_colors[(nx, ny)] = resolved[(x, y)]
                    order.append((nx, ny))

    for (x, y) in fill_set:
        px[x, y] = resolved.get((x, y), (0, 0, 0, 0))

    return im


def erase_and_inpaint(frame_img: Image.Image, ruler_points: list[tuple[int, int]]) -> Image.Image:
    im = frame_img.convert("RGBA").copy()
    dilated = _dilate(set(ruler_points), im.width, im.height, DILATE_PASSES)
    grown = _grow_dark_outline(dilated, im)
    return _inpaint(im, grown)


# ---------------------------------------------------------------------------
# Color/width sampling (from the ORIGINAL drawn ruler at the contact frame).

FILL_RANGE = ((195, 250), (125, 195), (75, 145))
OUTLINE_RANGE = ((70, 165), (45, 105), (20, 75))


def sample_colors(frame_img: Image.Image, points: list[tuple[int, int]]) -> dict:
    rgba = frame_img.convert("RGBA")
    px = rgba.load()
    fill_pixels = []
    outline_pixels = []
    for (x, y) in points:
        r, g, b, a = px[x, y]
        if FILL_RANGE[0][0] <= r <= FILL_RANGE[0][1] and FILL_RANGE[1][0] <= g <= FILL_RANGE[1][1] and FILL_RANGE[2][0] <= b <= FILL_RANGE[2][1]:
            fill_pixels.append((r, g, b))
        elif OUTLINE_RANGE[0][0] <= r <= OUTLINE_RANGE[0][1] and OUTLINE_RANGE[1][0] <= g <= OUTLINE_RANGE[1][1] and OUTLINE_RANGE[2][0] <= b <= OUTLINE_RANGE[2][1]:
            outline_pixels.append((r, g, b))

    def _avg(pixels: list[tuple[int, int, int]], default: tuple[int, int, int]) -> tuple[int, int, int]:
        if not pixels:
            return default
        n = len(pixels)
        return (
            round(sum(p[0] for p in pixels) / n),
            round(sum(p[1] for p in pixels) / n),
            round(sum(p[2] for p in pixels) / n),
        )

    fill = _avg(fill_pixels, (222, 168, 112))
    outline = _avg(outline_pixels, (95, 60, 38))
    # Tick marks: a shade between fill and outline, closer to outline.
    tick = tuple(round(o * 0.7 + f * 0.3) for o, f in zip(outline, fill))
    return {"fill": fill, "outline": outline, "tick": tick}


# ---------------------------------------------------------------------------
# Painting the new ruler.


def render_ruler_segment(
    base_px: tuple[float, float], tip_px: tuple[float, float], width_px: float,
    fill_color: tuple[int, int, int], outline_color: tuple[int, int, int], tick_color: tuple[int, int, int],
) -> tuple[Image.Image | None, tuple[int, int]]:
    dx = tip_px[0] - base_px[0]
    dy = tip_px[1] - base_px[1]
    length = math.hypot(dx, dy)
    if length < 1.0:
        return None, (0, 0)
    ux, uy = dx / length, dy / length
    perp_x, perp_y = -uy, ux

    margin = width_px * 0.5 + 4.0
    corners = [
        (base_px[0] + perp_x * margin, base_px[1] + perp_y * margin),
        (base_px[0] - perp_x * margin, base_px[1] - perp_y * margin),
        (tip_px[0] + perp_x * margin, tip_px[1] + perp_y * margin),
        (tip_px[0] - perp_x * margin, tip_px[1] - perp_y * margin),
    ]
    min_x = math.floor(min(c[0] for c in corners)) - 1
    max_x = math.ceil(max(c[0] for c in corners)) + 1
    min_y = math.floor(min(c[1] for c in corners)) - 1
    max_y = math.ceil(max(c[1] for c in corners)) + 1
    w = max_x - min_x
    h = max_y - min_y
    if w <= 0 or h <= 0 or w > 2000 or h > 2000:
        return None, (0, 0)

    ss = SUPERSAMPLE
    hi = Image.new("RGBA", (w * ss, h * ss), (0, 0, 0, 0))
    hi_px = hi.load()
    half_w = width_px * 0.5
    outline_w = max(1.0, width_px * OUTLINE_FRACTION)
    tick_len = half_w * TICK_DEPTH_FRACTION

    for j in range(h * ss):
        Y = min_y + (j + 0.5) / ss
        for i in range(w * ss):
            X = min_x + (i + 0.5) / ss
            rx = X - base_px[0]
            ry = Y - base_px[1]
            along = rx * ux + ry * uy
            perp = rx * perp_x + ry * perp_y
            if not (-0.5 <= along <= length + 0.5):
                continue
            if abs(perp) > half_w + 0.5:
                continue
            near_perp_edge = abs(abs(perp) - half_w) <= outline_w
            near_along_edge = along <= outline_w or along >= length - outline_w
            if near_perp_edge or near_along_edge:
                color = outline_color
            elif (along % TICK_SPACING_NATIVE) < (TICK_SPACING_NATIVE * 0.16) and perp > half_w - tick_len:
                color = tick_color
            else:
                color = fill_color
            hi_px[i, j] = color + (255,)

    lowres = hi.resize((w, h), Image.LANCZOS)
    return lowres, (min_x, min_y)


def composite_hand_patch(base_frame: Image.Image, original_frame: Image.Image, grip_px: tuple[float, float]) -> Image.Image:
    """Re-composites the ORIGINAL hand/finger pixels (non-wood-colored) near
    the grip back over the newly-painted ruler, feathered at the edge, so
    the gripping hand stays visually on top of the ruler in every frame."""
    out = base_frame.convert("RGBA").copy()
    orig = original_frame.convert("RGBA")
    ow, oh = orig.size
    orig_px = orig.load()
    out_px = out.load()
    gx, gy = grip_px
    r_in = HAND_PATCH_RADIUS - HAND_PATCH_FEATHER
    r_out = HAND_PATCH_RADIUS
    x0 = max(0, int(gx - r_out - 1))
    x1 = min(ow, int(gx + r_out + 2))
    y0 = max(0, int(gy - r_out - 1))
    y1 = min(oh, int(gy + r_out + 2))
    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b, a = orig_px[x, y]
            if a <= ALPHA_THRESHOLD:
                continue
            if pch._is_ruler_pixel(r, g, b):
                continue
            dist = math.hypot(x - gx, y - gy)
            if dist > r_out:
                continue
            feather = 1.0 if dist <= r_in else max(0.0, (r_out - dist) / max(1.0, HAND_PATCH_FEATHER))
            src_a = (a / 255.0) * feather
            if src_a <= 0.0:
                continue
            dr, dg, db, da = out_px[x, y]
            inv = 1.0 - src_a
            nr = round(r * src_a + dr * inv)
            ng = round(g * src_a + dg * inv)
            nb = round(b * src_a + db * inv)
            na = round(255 * src_a + da * inv)
            out_px[x, y] = (nr, ng, nb, min(255, na))
    return out


# ---------------------------------------------------------------------------
# Per-clip orchestration.


def to_world(p: tuple[float, float]) -> dict:
    return {"x": round((p[0] - FRAME_ANCHOR[0]) * DISPLAY_SCALE, 2), "y": round((p[1] - FRAME_ANCHOR[1]) * DISPLAY_SCALE, 2)}


def process_clip(clip_name: str, sheet_img: Image.Image, grid: dict, indices: list[int], contact_index: int, report: list[str]) -> dict:
    cw, ch, cols = grid["cell_width"], grid["cell_height"], grid["columns"]

    original_frames = []
    for idx in indices:
        col, row = idx % cols, idx // cols
        original_frames.append(sheet_img.crop((col * cw, row * ch, (col + 1) * cw, (row + 1) * ch)))

    detections = [detect_ruler(f) for f in original_frames]
    contact = detections[contact_index]
    if not contact["found"] or contact["low_confidence"]:
        raise SystemExit(f"{clip_name}: contact frame {contact_index} ruler detection unreliable -- cannot bake ruler length from it")

    grip_world = to_world(contact["grip_px"])
    grip_origin_dist = math.hypot(grip_world["x"], grip_world["y"])
    needed_length = TARGET_REACH_WORLD - grip_origin_dist
    painted_length_world = max(MIN_PAINTED_LENGTH_WORLD, min(RULER_LENGTH_WORLD, needed_length))
    achieved_reach = grip_origin_dist + painted_length_world
    report.append(
        f"  {clip_name}: contact grip_world=({grip_world['x']:.2f},{grip_world['y']:.2f}) "
        f"grip_origin_dist={grip_origin_dist:.2f} needed_length={needed_length:.2f} "
        f"painted_length={painted_length_world:.2f}{'  [CAPPED by RULER_LENGTH_WORLD]' if needed_length > RULER_LENGTH_WORLD else ''} "
        f"achieved_reach={achieved_reach:.2f} (target={TARGET_REACH_WORLD:.2f}, bare_reach={REACH_WORLD:.2f})"
    )

    colors = sample_colors(original_frames[contact_index], contact["points"])
    contact_width_native = contact["pixel_count"] / max(1.0, contact["length_native"])
    contact_length_native = contact["length_native"]
    report.append(f"    width_native={contact_width_native:.2f}px colors={colors}")

    # Fill in axis/ratio for low-confidence frames by interpolating from the
    # nearest reliable neighbors (by frame index; simple nearest-hold at the
    # sequence ends, linear interpolation in between).
    n = len(detections)
    reliable = [i for i, d in enumerate(detections) if d["found"] and not d["low_confidence"]]
    if not reliable:
        raise SystemExit(f"{clip_name}: no reliable ruler measurement in any frame")

    def _nearest_reliable(i: int, direction: int) -> int | None:
        j = i + direction
        while 0 <= j < n:
            if j in reliable:
                return j
            j += direction
        return None

    frame_axis = [0.0] * n
    frame_ratio = [1.0] * n
    frame_grip = [(0.0, 0.0)] * n
    for i, d in enumerate(detections):
        if d["found"] and not d["low_confidence"]:
            frame_axis[i] = d["axis_deg"]
            frame_ratio[i] = max(RATIO_MIN, min(RATIO_MAX, d["length_native"] / contact_length_native))
            frame_grip[i] = d["grip_px"]
            continue

        # Low-confidence (or entirely undetected) frame: the AXIS is the part
        # that's unreliable at a genuinely foreshortened pose (the ruler
        # points toward/away from the camera, so its 2D projection can spin
        # through a near-arbitrary short-lived angle) -- interpolate that
        # from the nearest reliable neighbors on either side. The apparent
        # LENGTH, in contrast, is exactly what foreshortening is supposed to
        # shrink: if this frame's own (still-found, just under the strict
        # elongation threshold) fallback measurement says short, that IS the
        # foreshortening signal and must not be replaced by a neighbor
        # interpolation that would silently paint a long ruler through a
        # pose that's actually foreshortened. Same for the grip point: the
        # hand's own position in THIS frame is usually still findable even
        # when the ruler's far end is ambiguous, so use it directly to keep
        # the base attached to the hand exactly as drawn in every frame.
        lo = _nearest_reliable(i, -1)
        hi = _nearest_reliable(i, 1)
        if lo is None and hi is None:
            raise SystemExit(f"{clip_name}: frame {i} has no reliable neighbor to interpolate from")
        if lo is None:
            lo = hi
        if hi is None:
            hi = lo
        t = 0.0 if lo == hi else (i - lo) / float(hi - lo)
        lo_axis, hi_axis = detections[lo]["axis_deg"], detections[hi]["axis_deg"]
        # shortest-path angle interpolation
        delta = ((hi_axis - lo_axis) + 180.0) % 360.0 - 180.0
        frame_axis[i] = lo_axis + delta * t

        if d["found"]:
            frame_ratio[i] = max(RATIO_MIN, min(RATIO_MAX, d["length_native"] / contact_length_native))
            frame_grip[i] = d["grip_px"]
            source = "own (foreshortened) length + interpolated axis"
        else:
            lo_ratio = max(RATIO_MIN, min(RATIO_MAX, detections[lo]["length_native"] / contact_length_native))
            hi_ratio = max(RATIO_MIN, min(RATIO_MAX, detections[hi]["length_native"] / contact_length_native))
            frame_ratio[i] = lo_ratio + (hi_ratio - lo_ratio) * t
            lo_grip, hi_grip = detections[lo]["grip_px"], detections[hi]["grip_px"]
            frame_grip[i] = (lo_grip[0] + (hi_grip[0] - lo_grip[0]) * t, lo_grip[1] + (hi_grip[1] - lo_grip[1]) * t)
            source = "fully interpolated (no detection at all)"
        report.append(
            f"    frame {i}: low-confidence, axis={frame_axis[i]:.2f}deg "
            f"ratio={frame_ratio[i]:.3f} ({source}, axis from frames {lo}/{hi})"
        )

    painted_length_native = painted_length_world * DESIGN_SCALE

    new_frames = []
    track_frames = []
    for i, orig in enumerate(original_frames):
        d = detections[i]
        erase_points = d["points"] if d["found"] else []
        cleaned = erase_and_inpaint(orig, erase_points) if erase_points else orig.convert("RGBA").copy()

        grip_px = frame_grip[i]
        axis_rad = math.radians(frame_axis[i])
        length_native = painted_length_native * frame_ratio[i]
        tip_px = (grip_px[0] + math.cos(axis_rad) * length_native, grip_px[1] + math.sin(axis_rad) * length_native)

        segment, origin = render_ruler_segment(grip_px, tip_px, contact_width_native, colors["fill"], colors["outline"], colors["tick"])
        if segment is not None:
            cleaned.alpha_composite(segment, origin)
        final_frame = composite_hand_patch(cleaned, orig, grip_px)
        new_frames.append(final_frame)

        track_frames.append({
            "frame": i,
            "grip_px": {"x": round(grip_px[0], 1), "y": round(grip_px[1], 1)},
            "tip_px": {"x": round(tip_px[0], 1), "y": round(tip_px[1], 1)},
            "grip": to_world(grip_px),
            "tip": to_world(tip_px),
            "axis_angle_deg": round(frame_axis[i], 2),
            "painted": True,
            "interpolated": not (d["found"] and not d["low_confidence"]),
        })

    return {
        "frames": new_frames,
        "track": {"contact_frame": contact_index, "frames": track_frames},
        "contact_reach_world": achieved_reach,
    }


def main() -> int:
    report: list[str] = []
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    manifest = json.loads(MANIFEST_PATH.read_text())
    track = json.loads(TRACK_PATH.read_text()) if TRACK_PATH.exists() else {}
    track.setdefault("display_scale", DISPLAY_SCALE)
    track.setdefault("frame_anchor", {"x": FRAME_ANCHOR[0], "y": FRAME_ANCHOR[1]})
    track.setdefault("clips", {})

    sheets: dict[str, Image.Image] = {}
    for sheet_name in {v[0] for v in CLIPS.values()}:
        sheets[sheet_name] = Image.open(ASSET_ROOT / sheet_name).convert("RGBA")

    print(f"REACH_WORLD={REACH_WORLD} TARGET_REACH_WORLD={TARGET_REACH_WORLD:.2f} RULER_LENGTH_WORLD={RULER_LENGTH_WORLD}")

    results = {}
    for clip_name, (sheet_name, contact_index) in CLIPS.items():
        grid = manifest["sheets"][sheet_name]["grid"]
        indices = manifest["sheets"][sheet_name]["clips"][clip_name]
        result = process_clip(clip_name, sheets[sheet_name], grid, indices, contact_index, report)
        results[clip_name] = result
        track["clips"][clip_name] = result["track"]

        cw, ch, cols = grid["cell_width"], grid["cell_height"], grid["columns"]
        for local_i, idx in enumerate(indices):
            col, row = idx % cols, idx // cols
            sheets[sheet_name].paste(result["frames"][local_i], (col * cw, row * ch))

    for sheet_name, img in sheets.items():
        out_path = ASSET_ROOT / sheet_name
        img.save(out_path)
        print(f"Wrote {out_path}")

    TRACK_PATH.write_text(json.dumps(track, indent=2) + "\n")
    print(f"Updated {TRACK_PATH}")

    print("\n".join(report))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

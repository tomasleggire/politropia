#!/usr/bin/env python3
"""Generate Luz's Blasphemous-style crescent slash smear and thrust VFX sheet.

- 6 variants x 5 frames:
  - ground_1/2/3/crouch/air: FLAT LATERAL crescents (Blasphemous main-attack
    style: a long, flat, mostly-horizontal band at the contact frame's own
    ruler height, sweeping forward from near the body), all 5 driven by
    their own clip's measured ruler track (T4d item 3 extended this from
    ground_1/2/3 only to crouch/air too) -- NOT the earlier per-clip
    angular-sweep-across-every-frame derivation (see git history), which
    read as a round/vertical arc instead of the requested lateral cut.
  - up: vertical thrust streak (narrow spindle along the measured axis of
    the true upward contact pose, aligned to the vertical hitbox).
- Pale mint 4-tone palette with checker dithering (PX=3 chunky pixel art).
- Cell size 720x640: generously sized so up-thrust and tall arcs have zero clipping.
- T4d item 3: ONE shared hitbox size/reach for every horizontal attack
  (ground_1/2/3/crouch/air), only vertical placement differs. Those five
  boxes are derived from the ruler track and shared reach constants. T5b
  restores the previously accepted up-hitbox geometry; that separate value
  is checked against UP_HITBOX rather than derived from horizontal reach.
- Assert bounds on all variants to guarantee no cell clipping.

Outputs:
- assets/player/luz/vfx/luz_slash_smears.png
- assets/player/luz/vfx/luz_slash_smears_manifest.json
- tools/art_sources/luz/preview/luz_slash_smears__contact_sheet.png
"""

from __future__ import annotations

import json
import math
import re
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

REPO_ROOT = Path(__file__).resolve().parent.parent
PLAYER_GD = REPO_ROOT / "scripts" / "player" / "player.gd"
OUTPUT_DIR = REPO_ROOT / "assets" / "player" / "luz" / "vfx"
PREVIEW_DIR = REPO_ROOT / "tools" / "art_sources" / "luz" / "preview"
TRACK_PATH = REPO_ROOT / "assets" / "player" / "luz" / "luz_ruler_track.json"

PX = 3
CELL_WIDTH = 720
CELL_HEIGHT = 640
FRAME_COUNT = 5
DESIGN_SCALE = 1.0 / 0.175

# T4d item 3: ONE shared hitbox for every horizontal attack (ground combo
# hits 1-3, crouch, air) -- same size (length x thickness) and same reach
# from the player's own local origin; only the vertical placement (offset.y)
# differs per attack. The up attack uses the same size rotated 90 degrees,
# reaching the same distance upward. This replaces the previous per-attack
# "hitbox = forward part of ITS OWN smear, each independently sized" scheme
# (T4's ground_1/2 vs ground_3-finisher split), which is exactly what T4d's
# user feedback (a) rejected ("in the 3rd hit Luz gets bigger and so does
# the attack hitbox; that must not happen").
#
# REACH_WORLD must match tools/paint_luz_ruler.py's own REACH_WORLD -- that
# tool bakes the long ruler art to reach this same distance (see its module
# docstring for the measurement), so the hitbox and the visible ruler agree
# by construction rather than by a separate reach-multiplier fudge factor
# (removed here -- T4's GROUND_REACH_MULTIPLIER/FINISHER_REACH_MULTIPLIER
# existed only to project a SHORT drawn ruler into a virtual longer reach;
# now that the ruler itself is long, that multiplier would double-count).
REACH_WORLD = 79.3
# BODY_FRONT_X is the standing CollisionShape2D's own half-width
# (scenes/player/player.tscn, RectangleShape2D_body size=(38,58), half=19).
BODY_FRONT_X = 19.0
FEET_LINE_Y = 0.0
HITBOX_TOLERANCE = 0.05  # world units; player.gd values must match within this

SHARED_LENGTH = REACH_WORLD - BODY_FRONT_X
# One shared hit-band thickness for every horizontal attack (previously
# 24/24/20/30 world units for ground/finisher/crouch/air respectively).
SHARED_THICKNESS = 24.0
SHARED_OFFSET_X = (REACH_WORLD + BODY_FRONT_X) / 2.0
# T5b restores the previously accepted upward attack geometry; it remains
# deliberately independent from the shared horizontal reach derivation.
UP_HITBOX = ((26.0, 68.0), (0.0, -80.0))

# Flat lateral crescent geometry for ground_1/2/3/crouch/air (Blasphemous
# main-attack style: a long, flat, horizontal cut reaching far beyond the
# weapon), derived ONLY from each clip's CONTACT frame measured ruler tip
# (luz_ruler_track.json) -- every other frame may be a low-confidence/
# foreshortened reading (the ruler pointing toward/away from the camera
# mid-swing) and must not drive geometry; the contact frame is always fully
# horizontal by the art's own spec, so it alone is reliable.
# far_edge = SMEAR_FLARE * contact_tip.x (tip.x is already measured from the
# player's own local origin, i.e. roughly "how far the ruler tip reaches
# beyond the body") -- the ruler is now baked long enough on its own (see
# REACH_WORLD above), so the smear only needs a small visual overshoot past
# it, not a reach-inflating multiplier.
SMEAR_FLARE = 1.08
# Ellipse vertical half-height (ry, world units, before the a_from/a_to
# forward-region sampling below trims it) -- a fixed "blade thickness" (the
# finisher is a touch thicker per the Blasphemous reference) independent of
# the hitbox's own SHARED_THICKNESS, since this only shapes the visual
# crescent, never the hitbox (which is now set directly from REACH_WORLD/
# SHARED_THICKNESS above, not derived from the smear).
LATERAL_RY_GROUND = 17.5
LATERAL_RY_FINISHER = 20.5
# Same flat-crescent angle sweep as the approved crouch smear (a_from/a_to
# below atan2 convention, y-down): covers the ellipse's forward arc without
# reaching fully behind (a_from) or fully in front (a_to), matching the
# "thick leading edge, thin tail" read crouch already has.
LATERAL_A_FROM = 205.0
LATERAL_A_TO = 345.0
# The up-attack thrust angle is measured from the final art's contact-frame
# ruler axis so the visual slash and vertical hitbox share one direction.

PALETTE = [
    (240, 252, 244),
    (205, 240, 226),
    (150, 205, 192),
    (92, 146, 146),
]

FRAME_LEAD = [0.55, 1.0, 1.0, 1.0, 1.0]
FRAME_TAIL = [0.0, 0.0, 0.30, 0.55, 0.80]
FRAME_FADE = [1.0, 1.0, 0.85, 0.60, 0.35]


def parse_player_hitboxes() -> dict[str, tuple[tuple[float, float], tuple[float, float]]]:
    """Extract hitbox sizes and offsets from player.gd exports (T4d item 3's
    unified scheme: one shared hitbox_attack_size/hitbox_attack_reach_x for
    every horizontal attack, one offset.y per attack category, plus the
    separately-rotated hitbox_up_size/hitbox_up_offset)."""
    content = PLAYER_GD.read_text()

    def get_vec2(var_name: str) -> tuple[float, float]:
        m = re.search(rf"@export var {var_name}\s*:=\s*Vector2\(([-0-9.]+),\s*([-0-9.]+)\)", content)
        if not m:
            raise ValueError(f"Could not parse {var_name} from {PLAYER_GD}")
        return (float(m.group(1)), float(m.group(2)))

    def get_float(var_name: str) -> float:
        m = re.search(rf"@export var {var_name}\s*:=\s*(-?[0-9.]+)", content)
        if not m:
            raise ValueError(f"Could not parse {var_name} from {PLAYER_GD}")
        return float(m.group(1))

    size = get_vec2("hitbox_attack_size")
    reach_x = get_float("hitbox_attack_reach_x")
    ground_y = get_float("hitbox_ground_offset_y")
    crouch_y = get_float("hitbox_crouch_offset_y")
    air_y = get_float("hitbox_air_offset_y")

    return {
        "ground_1": (size, (reach_x, ground_y)),
        "ground_2": (size, (reach_x, ground_y)),
        "ground_3": (size, (reach_x, ground_y)),
        "crouch":   (size, (reach_x, crouch_y)),
        "air":      (size, (reach_x, air_y)),
        "up":       (get_vec2("hitbox_up_size"), get_vec2("hitbox_up_offset")),
    }


def render_crescent_frame(
    frame: int, cx: float, cy: float, rx: float, ry: float,
    a_from: float, a_to: float, peak: float, rotation_deg: float = 0.0,
) -> Image.Image:
    lead_p = FRAME_LEAD[frame]
    tail_p = FRAME_TAIL[frame]
    fade = FRAME_FADE[frame]
    span = a_to - a_from

    low_w, low_h = CELL_WIDTH // PX, CELL_HEIGHT // PX
    img = Image.new("RGBA", (low_w, low_h), (0, 0, 0, 0))
    px = img.load()
    rotation = math.radians(rotation_deg)
    cos_rotation, sin_rotation = math.cos(rotation), math.sin(rotation)

    for ly in range(low_h):
        for lx in range(low_w):
            x, y = lx * PX, ly * PX
            dx, dy = x - cx, y - cy
            local_x = dx * cos_rotation + dy * sin_rotation
            local_y = -dx * sin_rotation + dy * cos_rotation
            u = local_x / rx
            v = local_y / ry
            rho = math.hypot(u, v)
            if rho > 1.05:
                continue
            raw = math.degrees(math.atan2(v, u)) % 360.0
            ang = a_from + (raw - a_from) % 360.0
            s = (ang - a_from) / span
            if not (tail_p <= s <= lead_p):
                continue
            local = (s - tail_p) / max(1e-3, lead_p - tail_p)
            thickness = peak * math.sin(math.pi * min(1.0, local) ** 0.8) * fade
            if thickness <= 0.01 or not (1.0 - thickness <= rho <= 1.0):
                continue
            k = (rho - (1.0 - thickness)) / thickness
            dither = (lx + ly) % 2
            if k > 0.7:
                color = PALETTE[0]
            elif k > 0.4:
                color = PALETTE[1]
            elif k > 0.15:
                color = PALETTE[2]
            else:
                if dither:
                    continue
                color = PALETTE[3]
            if local < 0.18 and dither:
                continue
            if fade < 0.7 and (lx * 7 + ly * 3) % 3 == 0:
                continue
            px[lx, ly] = color + (255,)

    return img.resize((CELL_WIDTH, CELL_HEIGHT), Image.NEAREST)


def render_thrust_frame(
    frame: int, cx: float, cy: float, angle_deg: float, length_px: float, half_width_px: float,
) -> Image.Image:
    """Narrow spindle streak along the thrust direction."""
    lead_p = FRAME_LEAD[frame]
    tail_p = FRAME_TAIL[frame]
    fade = FRAME_FADE[frame]

    angle = math.radians(angle_deg)
    dirx, diry = math.cos(angle), math.sin(angle)
    perpx, perpy = -diry, dirx

    low_w, low_h = CELL_WIDTH // PX, CELL_HEIGHT // PX
    img = Image.new("RGBA", (low_w, low_h), (0, 0, 0, 0))
    px = img.load()

    # Offset cx, cy to base of thrust
    base_x = cx - dirx * (length_px * 0.5)
    base_y = cy - diry * (length_px * 0.5)

    for ly in range(low_h):
        for lx in range(low_w):
            x, y = lx * PX, ly * PX
            dx, dy = x - base_x, y - base_y
            along = (dx * dirx + dy * diry) / length_px
            perp = dx * perpx + dy * perpy
            if not (0.0 <= along <= 1.05):
                continue
            s = along
            if not (tail_p <= s <= lead_p):
                continue
            local = (s - tail_p) / max(1e-3, lead_p - tail_p)
            width_here = half_width_px * math.sin(math.pi * min(1.0, s)) ** 0.7 * fade
            if width_here <= 0.5:
                continue
            rho = abs(perp) / width_here
            if rho > 1.0:
                continue
            k = 1.0 - rho
            dither = (lx + ly) % 2
            if k > 0.55:
                color = PALETTE[0]
            elif k > 0.30:
                color = PALETTE[1]
            elif k > 0.12:
                color = PALETTE[2]
            else:
                if dither:
                    continue
                color = PALETTE[3]
            if local < 0.18 and dither:
                continue
            if fade < 0.7 and (lx * 7 + ly * 3) % 3 == 0:
                continue
            px[lx, ly] = color + (255,)

    return img.resize((CELL_WIDTH, CELL_HEIGHT), Image.NEAREST)


def load_ruler_track() -> dict:
    if not TRACK_PATH.exists():
        return {}
    return json.loads(TRACK_PATH.read_text())


def lateral_band_mid_sin(a_from: float, a_to: float, steps: int = 720) -> float:
    """Midpoint of sin(theta) over the sweep [a_from, a_to] (degrees): the
    vertical center of the drawn arc, in units of ry, relative to the
    ellipse center (y-down)."""
    sines = [math.sin(math.radians(a_from + (a_to - a_from) * i / (steps - 1))) for i in range(steps)]
    return (min(sines) + max(sines)) / 2.0


def lateral_swing_geometry(
    clip_track: dict, ry_world: float, a_from: float, a_to: float, rotation_deg: float = 0.0,
    minimum_reach_world: float = 0.0,
) -> dict:
    """Derives a FLAT LATERAL ellipse (cx, cy, rx, ry, a_from, a_to) for a
    ground_1/2/3/crouch/air variant from ONLY the clip's CONTACT frame
    measured ruler tip/grip (assets/player/luz/luz_ruler_track.json, now
    baked long by tools/paint_luz_ruler.py -- see T4d item 2) -- unlike the
    earlier per-clip angular-sweep-across-every-frame derivation (see git
    history), this needs no windup/follow-through measurements (some of
    which are legitimately low-confidence: the ruler foreshortens when it
    points toward/away from the camera mid-swing) since the contact frame
    alone is reliable (always fully horizontal, by the art's own spec) and
    is the only frame whose height/reach we actually want to key the cut to.

    - center_y: the ruler's own height at contact (average of tip/grip y).
    - far_x: SMEAR_FLARE * contact tip.x (tip.x is already measured from the
      player's own local origin) -- a small visual overshoot past the now-
      long baked ruler tip, not a reach-inflating multiplier (removed, see
      module docstring).
    - near_x: BODY_FRONT_X -- the cut starts at the body's own front edge,
      matching "you hit what you see"'s existing near-edge convention.
    - The ellipse is centered between near_x/far_x, half-width rx = half
      that span; ry is the fixed "blade thickness" (LATERAL_RY_GROUND/
      LATERAL_RY_FINISHER) -- "large rx, small ry", same flattened style as
      the approved crouch smear.
    """
    contact_index = clip_track["contact_frame"]
    contact = clip_track["frames"][contact_index]
    if contact.get("low_confidence") or contact.get("tip") is None:
        raise SystemExit(
            f"lateral_swing_geometry: contact frame {contact_index} has no reliable ruler "
            "measurement (low_confidence); cannot derive lateral swing geometry from it."
        )
    tip, grip = contact["tip"], contact["grip"]
    ruler_y = (tip["y"] + grip["y"]) / 2.0
    # The sweep only draws part of the ellipse, so its visible band is not
    # centered on the ellipse center; shift the center so that band's middle
    # sits on the ruler line (the cut must trail the blade, not float above it).
    center_y = ruler_y - lateral_band_mid_sin(a_from, a_to) * ry_world
    near_x = BODY_FRONT_X
    # Keep the visible cut at least as far as the shared hitbox even when a
    # backhand's across-body grip places the painted ruler tip closer in x;
    # the crescent remains a visual effect and does not alter combat reach.
    far_x = max(SMEAR_FLARE * tip["x"], minimum_reach_world)
    cx = (near_x + far_x) / 2.0
    rx = (far_x - near_x) / 2.0
    ry = ry_world
    return {
        "cx": cx, "cy": center_y, "rx": rx, "ry": ry,
        "a_from": a_from, "a_to": a_to, "rotation_deg": rotation_deg,
        "contact_tip_x": tip["x"], "far_x_target": far_x,
    }


def build_variant_geometry(
    name: str, config: dict, size: tuple[float, float], offset: tuple[float, float], track: dict
) -> dict:
    design_w = size[0] * DESIGN_SCALE
    design_h = size[1] * DESIGN_SCALE
    cx = CELL_WIDTH / 2.0
    cy = CELL_HEIGHT / 2.0

    lateral = config.get("lateral_from_track")
    track_clip = config.get("track_clip")
    if lateral and track_clip and track.get("clips", {}).get(track_clip):
        geo = lateral_swing_geometry(
            track["clips"][track_clip], lateral["ry_world"],
            lateral.get("a_from", LATERAL_A_FROM), lateral.get("a_to", LATERAL_A_TO),
            lateral.get("rotation_deg", 0.0), lateral.get("minimum_reach_world", 0.0),
        )
        config["a_from"], config["a_to"] = geo["a_from"], geo["a_to"]
        config["rotation_deg"] = geo["rotation_deg"]
        rx, ry = geo["rx"] * DESIGN_SCALE, geo["ry"] * DESIGN_SCALE
        anchor_x = cx - geo["cx"] * DESIGN_SCALE
        anchor_y = cy - geo["cy"] * DESIGN_SCALE
        print(
            f"  {name}: lateral contact_tip_x={geo['contact_tip_x']:.2f} far_x_target={geo['far_x_target']:.2f} "
            f"center=({geo['cx']:.2f},{geo['cy']:.2f}) rx_world={geo['rx']:.2f} ry_world={geo['ry']:.2f}"
        )
    else:
        flare = config.get("flare", 1.30)
        rx = (design_w / 2.0) * flare
        ry = (design_h / 2.0) * flare
        anchor_x = cx - offset[0] * DESIGN_SCALE
        anchor_y = cy - offset[1] * DESIGN_SCALE

    # Assert no cell clipping
    if config["type"] == "arc":
        assert cx - rx >= 0 and cx + rx <= CELL_WIDTH, f"{name} clips horizontally: rx={rx}, cx={cx}"
        assert cy - ry >= 0 and cy + ry <= CELL_HEIGHT, f"{name} clips vertically: ry={ry}, cy={cy}"
    elif config["type"] == "thrust":
        assert cy - design_h * 0.6 >= 0 and cy + design_h * 0.6 <= CELL_HEIGHT, f"{name} clips vertically in thrust"

    return {
        "cx": cx,
        "cy": cy,
        "rx": rx,
        "ry": ry,
        "length_px": design_h,
        "anchor": (anchor_x, anchor_y),
    }


def _clip_mid_y(track: dict, clip_name: str) -> float:
    """Contact-frame (tip.y + grip.y) / 2 for one clip -- "the ruler's own
    height at contact", used as that attack's vertical hitbox placement."""
    clip = track["clips"][clip_name]
    frame = clip["frames"][clip["contact_frame"]]
    return (frame["tip"]["y"] + frame["grip"]["y"]) / 2.0


def derive_shared_hitboxes(track: dict) -> dict[str, tuple[tuple[float, float], tuple[float, float]]]:
    """T4d item 3: the single source of truth for player.gd's unified
    hitbox scheme. One shared size/reach (SHARED_LENGTH x SHARED_THICKNESS,
    reaching REACH_WORLD from the player's own origin) for every horizontal
    attack; only the vertical placement differs, taken directly from each
    attack's own measured ruler height at contact (the ground combo's three
    hits share ONE "chest" placement, averaged across all three, per the
    brief's "chest for combo" -- not three slightly different placements).
    The up attack keeps its previously accepted geometry as an explicit
    value, independent from the horizontal boxes."""
    combo_y = sum(_clip_mid_y(track, c) for c in ("ground_attack_1", "ground_attack_2", "ground_attack_3")) / 3.0
    crouch_y = _clip_mid_y(track, "crouch_attack")
    air_y = _clip_mid_y(track, "air_horizontal_attack")
    size = (SHARED_LENGTH, SHARED_THICKNESS)
    return {
        "ground_1": (size, (SHARED_OFFSET_X, combo_y)),
        "ground_2": (size, (SHARED_OFFSET_X, combo_y)),
        "ground_3": (size, (SHARED_OFFSET_X, combo_y)),
        "crouch": (size, (SHARED_OFFSET_X, crouch_y)),
        "air": (size, (SHARED_OFFSET_X, air_y)),
        "up": UP_HITBOX,
    }


def validate_hitboxes(ruler_track: dict, hitbox_configs: dict) -> None:
    """Fails the build if scripts/player/player.gd's unified hitbox exports
    have drifted from derive_shared_hitboxes's analytical derivation (from
    REACH_WORLD/SHARED_LENGTH/SHARED_THICKNESS + the measured ruler track's
    per-clip contact height) -- the up box is validated separately against
    UP_HITBOX. player.gd is where gameplay reads these values from, and the
    two must never silently disagree."""
    if not ruler_track.get("clips"):
        print("  (no ruler track data; skipping hitbox validation)")
        return

    derived = derive_shared_hitboxes(ruler_track)
    failures: list[str] = []
    for label in ("ground_1", "ground_2", "ground_3", "crouch", "air", "up"):
        derived_size, derived_offset = derived[label]
        actual_size, actual_offset = hitbox_configs[label]
        print(
            f"  {label}: derived size=({derived_size[0]:.2f},{derived_size[1]:.2f}) "
            f"offset=({derived_offset[0]:.2f},{derived_offset[1]:.2f})  |  "
            f"player.gd size={actual_size} offset={actual_offset}"
        )
        checks = (
            (actual_size[0], derived_size[0], f"{label}_size.x"),
            (actual_size[1], derived_size[1], f"{label}_size.y"),
            (actual_offset[0], derived_offset[0], f"{label}_offset.x"),
            (actual_offset[1], derived_offset[1], f"{label}_offset.y"),
        )
        for got, want, axis in checks:
            if abs(got - want) > HITBOX_TOLERANCE:
                failures.append(f"{axis}: player.gd has {got}, derived is {want:.2f}")

    if failures:
        raise SystemExit(
            "scripts/player/player.gd's hitbox @export values have drifted from the "
            "unified derivation (single source of truth: luz_ruler_track.json + "
            "this script's REACH_WORLD/SHARED_LENGTH/SHARED_THICKNESS):\n  "
            + "\n  ".join(failures)
            + "\nUpdate the @export values in player.gd to match the derived numbers printed above, then rerun."
        )


def main() -> int:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)

    hitbox_configs = parse_player_hitboxes()
    ruler_track = load_ruler_track()

    print("Validating player.gd hitboxes against smear-derived geometry:")
    validate_hitboxes(ruler_track, hitbox_configs)

    variant_specs = {
        "ground_1": {
            "row": 0, "type": "arc",
            # a_from/a_to/rx/ry/anchor are all overwritten from the contact
            # frame's measured ruler tip (luz_ruler_track.json) in
            # build_variant_geometry -- flat lateral crescent, same style as
            # "crouch" below, at the contact frame's own ruler height.
            "peak": 0.55,
            "track_clip": "ground_attack_1",
            "lateral_from_track": {"ry_world": LATERAL_RY_GROUND, "a_from": 205.0, "a_to": 345.0, "minimum_reach_world": REACH_WORLD},
            "description": "flat lateral cut at chest height, hit 1 (measured from ground_attack_1 art)",
        },
        "ground_2": {
            "row": 1, "type": "arc",
            "peak": 0.55,
            "track_clip": "ground_attack_2",
            "lateral_from_track": {"ry_world": LATERAL_RY_GROUND, "a_from": 15.0, "a_to": 155.0, "minimum_reach_world": REACH_WORLD},
            # T5b uses the tucked across-body source pose for a backhand
            # contact; the lower-arc silhouette distinguishes this cut from
            # the forehand without changing hitbox size or reach.
            "description": "opposite-curvature lateral backhand cut, hit 2",
        },
        "ground_3": {
            "row": 2, "type": "arc",
            "peak": 0.62,
            "track_clip": "ground_attack_3",
            "lateral_from_track": {"ry_world": LATERAL_RY_FINISHER, "a_from": 205.0, "a_to": 345.0, "rotation_deg": 18.0, "minimum_reach_world": REACH_WORLD},
            "description": "flat lateral finisher cut at chest height, wider/thicker/farther reach (measured from ground_attack_3 art)",
        },
        "crouch": {
            "row": 3, "type": "arc",
            "peak": 0.50,
            "track_clip": "crouch_attack",
            "lateral_from_track": {"ry_world": LATERAL_RY_GROUND},
            "description": "low flat horizontal sweep near the ground (measured from crouch_attack art)",
        },
        "up": {
            "row": 4, "type": "thrust",
            "half_width_px": 28.0,
            "description": "vertical upward streak aligned to the measured ruler axis",
        },
        "air": {
            "row": 5, "type": "arc",
            "peak": 0.55,
            "track_clip": "air_horizontal_attack",
            "lateral_from_track": {"ry_world": LATERAL_RY_GROUND},
            "description": "lateral horizontal air sweep forward (measured from air_horizontal_attack art)",
        },
    }

    up_track = ruler_track["clips"]["up_attack"]
    up_contact = up_track["frames"][up_track["contact_frame"]]
    if up_contact.get("low_confidence") or up_contact.get("axis_angle_deg") is None:
        raise SystemExit("up_attack: contact frame has no reliable measured ruler axis")
    variant_specs["up"]["angle_deg"] = up_contact["axis_angle_deg"]
    print(f"up: thrust angle follows measured contact ruler axis {up_contact['axis_angle_deg']:.2f}deg")

    row_count = len(variant_specs)
    sheet = Image.new("RGBA", (CELL_WIDTH * FRAME_COUNT, CELL_HEIGHT * row_count), (0, 0, 0, 0))
    manifest_variants = {}

    for name, spec in variant_specs.items():
        size, offset = hitbox_configs[name]
        geometry = build_variant_geometry(name, spec, size, offset, ruler_track)
        row = spec["row"]
        print(f"{name}: row={row} rx={geometry['rx']:.1f} ry={geometry['ry']:.1f} anchor={geometry['anchor']}")

        for frame in range(FRAME_COUNT):
            if spec["type"] == "arc":
                frame_img = render_crescent_frame(
                    frame, geometry["cx"], geometry["cy"], geometry["rx"], geometry["ry"],
                    spec["a_from"], spec["a_to"], spec["peak"], spec.get("rotation_deg", 0.0),
                )
            else:
                frame_img = render_thrust_frame(
                    frame, geometry["cx"], geometry["cy"], spec["angle_deg"],
                    geometry["length_px"], spec["half_width_px"],
                )
            sheet.alpha_composite(frame_img, (frame * CELL_WIDTH, row * CELL_HEIGHT))

        manifest_variants[name] = {
            "row": row,
            "reference_hitbox_size": list(size),
            "reference_hitbox_offset": list(offset),
            "anchor": [geometry["anchor"][0], geometry["anchor"][1]],
            "description": spec["description"],
            "cut_geometry": {
                "a_from": spec.get("a_from"), "a_to": spec.get("a_to"),
                "rotation_deg": spec.get("rotation_deg", 0.0),
                "ry_world": spec.get("lateral_from_track", {}).get("ry_world"),
            },
        }

    out_path = OUTPUT_DIR / "luz_slash_smears.png"
    sheet.save(out_path)
    print(f"Wrote {out_path} ({sheet.size[0]}x{sheet.size[1]})")

    manifest = {
        "cell_width": CELL_WIDTH,
        "cell_height": CELL_HEIGHT,
        "frame_count": FRAME_COUNT,
        "display_scale": 0.175,
        "variants": manifest_variants,
    }
    manifest_path = OUTPUT_DIR / "luz_slash_smears_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Wrote {manifest_path}")

    # Contact sheet preview
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 20)
    except OSError:
        font = ImageFont.load_default()
    contact = Image.new("RGBA", sheet.size, (30, 30, 34, 255))
    contact.alpha_composite(sheet)
    draw = ImageDraw.Draw(contact)
    for name, spec in variant_specs.items():
        row = spec["row"]
        draw.rectangle([0, row * CELL_HEIGHT, sheet.size[0] - 1, (row + 1) * CELL_HEIGHT - 1], outline=(255, 0, 255, 255), width=1)
        draw.text((8, row * CELL_HEIGHT + 8), name, fill=(255, 255, 0, 255), font=font)
        for frame in range(FRAME_COUNT):
            draw.line([(frame * CELL_WIDTH, row * CELL_HEIGHT), (frame * CELL_WIDTH, (row + 1) * CELL_HEIGHT)], fill=(255, 0, 255, 120))
    contact_path = PREVIEW_DIR / "luz_slash_smears__contact_sheet.png"
    contact.save(contact_path)
    print(f"Wrote {contact_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

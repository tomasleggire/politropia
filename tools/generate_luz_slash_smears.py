#!/usr/bin/env python3
"""Generate Luz's Blasphemous-style crescent slash smear and thrust VFX sheet.

- 6 variants x 5 frames:
  - ground_1/2/3: FLAT LATERAL crescents (Blasphemous main-attack style: a
    long, flat, mostly-horizontal band at the contact frame's own ruler
    height, sweeping forward from near the body), same elongated-ellipse
    technique as crouch (large rx, small ry) -- NOT the earlier per-clip
    angular-sweep-across-every-frame derivation (see git history), which
    read as a round/vertical arc instead of the requested lateral cut.
  - crouch: low flat horizontal sweep forward (unchanged, this is the style
    ground_1/2/3 now reuse).
  - up: vertical thrust streak (narrow spindle along ruler axis, no clipping)
    (unchanged).
  - air: lateral horizontal air sweep forward (unchanged).
- Pale mint 4-tone palette with checker dithering (PX=3 chunky pixel art).
- Cell size 720x640: generously sized so up-thrust and tall arcs have zero clipping.
- Hitbox size and offset parsed directly from scripts/player/player.gd as the single source of truth.
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

# "You hit what you see": ground_1/2/3's hitboxes are derived from the
# rendered smear crescent (see lateral_swing_geometry/forward_extent below),
# not from the ruler bar alone. Only the part of that crescent actually in
# front of the body and at/above the feet counts -- the rest wraps behind
# her or into the ground and is never the forward "you hit what you see"
# region a melee swing should represent.
# BODY_FRONT_X is the standing CollisionShape2D's own half-width
# (scenes/player/player.tscn, RectangleShape2D_body size=(38,58), half=19).
BODY_FRONT_X = 19.0
FEET_LINE_Y = 0.0
HITBOX_TOLERANCE = 0.05  # world units; player.gd values must match within this

# Flat lateral crescent geometry for ground_1/2/3 (Blasphemous main-attack
# style: a long, flat, horizontal cut at chest/waist height reaching far
# beyond the weapon), derived ONLY from each clip's CONTACT frame measured
# ruler tip (luz_ruler_track.json) -- every other frame may be a
# low-confidence/foreshortened reading (the ruler pointing toward/away from
# the camera mid-swing) and must not drive geometry; the contact frame is
# always fully horizontal by the art's own spec, so it alone is reliable.
# far_edge = REACH_MULTIPLIER * contact_tip.x (tip.x is already measured
# from the player's own local origin, i.e. roughly "how far the ruler tip
# reaches beyond the body"). Multipliers tuned to land near the pre-T4
# reach values (84 for the shared ground hitbox, 98 for the finisher) -- see
# odd/tasks/luz-blasphemous-animation.md for the exact achieved numbers.
GROUND_REACH_MULTIPLIER = 2.0
FINISHER_REACH_MULTIPLIER = 2.3
# Ellipse vertical half-height (ry, world units, before the a_from/a_to
# forward-region sampling below trims it) -- a fixed "blade thickness"
# shared by ground_1/ground_2 (they share one hitbox) rather than a ratio of
# rx, so the two differently-reaching cuts still read as the same weapon
# width; the finisher is a touch thicker per the Blasphemous reference. At
# the shared LATERAL_A_FROM/LATERAL_A_TO sweep below, the forward-region
# vertical span comes out to (1 - sin(345deg)) * ry = 1.2588 * ry (the sweep
# includes the ellipse's top point but not its bottom one) -- tuned so the
# derived hitbox lands in the same ballpark as this game's other flat
# attacks (hitbox_crouch_size.y=20, hitbox_air_size.y=30), not the near-zero
# sliver a small rx-relative ratio would give the shorter-reaching cuts.
LATERAL_RY_GROUND = 17.5
LATERAL_RY_FINISHER = 20.5
# Slight outer overshoot past the raw near/far span, same idea as the old
# OUTER_RADIUS_FLARE: the rendered crescent (and the hitbox derived from it)
# reads a little past the bare numeric reach for visual follow-through.
LATERAL_FLARE = 1.08
# Same flat-crescent angle sweep as the approved crouch smear (a_from/a_to
# below atan2 convention, y-down): covers the ellipse's forward arc without
# reaching fully behind (a_from) or fully in front (a_to), matching the
# "thick leading edge, thin tail" read crouch already has.
LATERAL_A_FROM = 205.0
LATERAL_A_TO = 345.0

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
    """Extract hitbox sizes and offsets from player.gd exports."""
    content = PLAYER_GD.read_text()
    def get_vec2(var_name: str) -> tuple[float, float]:
        m = re.search(rf"@export var {var_name}\s*:=\s*Vector2\(([-0-9.]+),\s*([-0-9.]+)\)", content)
        if not m:
            raise ValueError(f"Could not parse {var_name} from {PLAYER_GD}")
        return (float(m.group(1)), float(m.group(2)))

    return {
        "ground_1": (get_vec2("hitbox_ground_size"), get_vec2("hitbox_ground_offset")),
        "ground_2": (get_vec2("hitbox_ground_size"), get_vec2("hitbox_ground_offset")),
        "ground_3": (get_vec2("hitbox_finisher_size"), get_vec2("hitbox_finisher_offset")),
        "crouch":   (get_vec2("hitbox_crouch_size"), get_vec2("hitbox_crouch_offset")),
        "up":       (get_vec2("hitbox_up_size"), get_vec2("hitbox_up_offset")),
        "air":      (get_vec2("hitbox_air_size"), get_vec2("hitbox_air_offset")),
    }


def render_crescent_frame(
    frame: int, cx: float, cy: float, rx: float, ry: float,
    a_from: float, a_to: float, peak: float,
) -> Image.Image:
    lead_p = FRAME_LEAD[frame]
    tail_p = FRAME_TAIL[frame]
    fade = FRAME_FADE[frame]
    span = a_to - a_from

    low_w, low_h = CELL_WIDTH // PX, CELL_HEIGHT // PX
    img = Image.new("RGBA", (low_w, low_h), (0, 0, 0, 0))
    px = img.load()

    for ly in range(low_h):
        for lx in range(low_w):
            x, y = lx * PX, ly * PX
            u = (x - cx) / rx
            v = (y - cy) / ry
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


def lateral_swing_geometry(clip_track: dict, reach_multiplier: float, ry_world: float) -> dict:
    """Derives a FLAT LATERAL ellipse (cx, cy, rx, ry, a_from, a_to) for a
    ground_1/2/3 variant from ONLY the clip's CONTACT frame measured ruler
    tip/grip (assets/player/luz/luz_ruler_track.json) -- unlike the earlier
    per-clip angular-sweep-across-every-frame derivation (see git history),
    this needs no windup/follow-through measurements (some of which are
    legitimately low-confidence: the ruler foreshortens when it points
    toward/away from the camera mid-swing) since the contact frame alone is
    reliable (always fully horizontal, by the art's own spec) and is the
    only frame whose height/reach we actually want to key the cut to.

    - center_y: the ruler's own height at contact (average of tip/grip y)
      -- chest for ground_1/ground_3, waist for ground_2, per whatever the
      approved art actually drew.
    - far_x: reach_multiplier * contact tip.x (tip.x is already measured
      from the player's own local origin), i.e. how far *beyond the body*
      the cut should read, Blasphemous-style (fit to the pre-T4 reach
      values, see module docstring for the tuned multipliers).
    - near_x: BODY_FRONT_X -- the cut starts at the body's own front edge,
      matching "you hit what you see"'s existing near-edge convention.
    - The ellipse is centered between near_x/far_x, half-width rx = half
      that span (before LATERAL_FLARE); ry is the fixed "blade thickness"
      (LATERAL_RY_GROUND/LATERAL_RY_FINISHER) -- "large rx, small ry", same
      flattened style as the approved crouch smear.
    """
    contact_index = clip_track["contact_frame"]
    contact = clip_track["frames"][contact_index]
    if contact.get("low_confidence") or contact.get("tip") is None:
        raise SystemExit(
            f"lateral_swing_geometry: contact frame {contact_index} has no reliable ruler "
            "measurement (low_confidence); cannot derive lateral swing geometry from it."
        )
    tip, grip = contact["tip"], contact["grip"]
    center_y = (tip["y"] + grip["y"]) / 2.0
    near_x = BODY_FRONT_X
    far_x = reach_multiplier * tip["x"]
    cx = (near_x + far_x) / 2.0
    rx = (far_x - near_x) / 2.0 * LATERAL_FLARE
    ry = ry_world
    return {
        "cx": cx, "cy": center_y, "rx": rx, "ry": ry,
        "a_from": LATERAL_A_FROM, "a_to": LATERAL_A_TO,
        "contact_tip_x": tip["x"], "far_x_target": far_x,
    }


def forward_extent(
    cx: float, cy: float, rx: float, ry: float, a_from: float, a_to: float, steps: int = 2000
) -> tuple[float, float, float] | None:
    """Samples the ellipse (center cx,cy, radii rx,ry) from a_from to a_to
    and returns (far_x, y_min, y_max) restricted to the forward,
    at-or-above-feet region (x >= BODY_FRONT_X, y <= FEET_LINE_Y) -- "the
    part in front of the body" a melee hitbox should cover, per the "you hit
    what you see" rule. Returns None if no sampled point qualifies."""
    xs, ys = [], []
    for i in range(steps):
        theta = math.radians(a_from + (a_to - a_from) * i / (steps - 1))
        x = cx + rx * math.cos(theta)
        y = cy + ry * math.sin(theta)
        if x >= BODY_FRONT_X and y <= FEET_LINE_Y:
            xs.append(x)
            ys.append(y)
    if not xs:
        return None
    return max(xs), min(ys), max(ys)


def derive_hitbox(extent: tuple[float, float, float]) -> tuple[tuple[float, float], tuple[float, float]]:
    """(far_x, y_min, y_max) -> (size, offset), near edge fixed at BODY_FRONT_X."""
    far_x, y_min, y_max = extent
    size = (far_x - BODY_FRONT_X, y_max - y_min)
    offset = ((far_x + BODY_FRONT_X) / 2.0, (y_max + y_min) / 2.0)
    return size, offset


def combine_extents(extents: list[tuple[float, float, float]]) -> tuple[float, float, float]:
    """Union of several (far_x, y_min, y_max) forward extents -- for a
    hitbox shared by more than one attack (ground_1/ground_2), it must cover
    each attack's own visible crescent, not just one of them."""
    return max(e[0] for e in extents), min(e[1] for e in extents), max(e[2] for e in extents)


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
        geo = lateral_swing_geometry(track["clips"][track_clip], lateral["reach_multiplier"], lateral["ry_world"])
        config["a_from"], config["a_to"] = geo["a_from"], geo["a_to"]
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


def validate_hitboxes(ruler_track: dict, hitbox_configs: dict) -> None:
    """Fails the build if scripts/player/player.gd's hitbox_ground_*/
    hitbox_finisher_* have drifted from the geometry derived here (from the
    measured ruler track + the same outer smear radius the crescent is
    rendered with) -- this script/the track JSON are the single source of
    truth for WHAT the values should be; player.gd is where gameplay reads
    them from, and the two must never silently disagree."""
    if not ruler_track.get("clips"):
        print("  (no ruler track data; skipping hitbox validation)")
        return

    groups = [
        (
            "hitbox_ground",
            [("ground_attack_1", GROUND_REACH_MULTIPLIER, LATERAL_RY_GROUND), ("ground_attack_2", GROUND_REACH_MULTIPLIER, LATERAL_RY_GROUND)],
            hitbox_configs["ground_1"],
        ),
        (
            "hitbox_finisher",
            [("ground_attack_3", FINISHER_REACH_MULTIPLIER, LATERAL_RY_FINISHER)],
            hitbox_configs["ground_3"],
        ),
    ]
    failures: list[str] = []
    for label, clips, (actual_size, actual_offset) in groups:
        extents = []
        for clip, reach_multiplier, ry_world in clips:
            clip_track = ruler_track["clips"].get(clip)
            if not clip_track:
                print(f"  (no track data for {clip} yet; skipping {label} validation)")
                extents = None
                break
            geo = lateral_swing_geometry(clip_track, reach_multiplier, ry_world)
            ext = forward_extent(geo["cx"], geo["cy"], geo["rx"], geo["ry"], geo["a_from"], geo["a_to"])
            if ext is None:
                raise RuntimeError(
                    f"{label}: {clip}'s forward-region smear extent is empty "
                    "(no sampled point had x >= BODY_FRONT_X and y <= FEET_LINE_Y)"
                )
            extents.append(ext)
        if not extents:
            continue

        combined = combine_extents(extents)
        derived_size, derived_offset = derive_hitbox(combined)
        print(
            f"  {label}: derived size=({derived_size[0]:.2f},{derived_size[1]:.2f}) "
            f"offset=({derived_offset[0]:.2f},{derived_offset[1]:.2f}) far_edge={combined[0]:.2f}  |  "
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
                failures.append(f"{axis}: player.gd has {got}, smear-derived is {want:.2f}")

    if failures:
        raise SystemExit(
            "scripts/player/player.gd's hitbox @export values have drifted from the "
            "smear-derived geometry (single source of truth: luz_ruler_track.json + "
            "this script's LATERAL_FLARE/BODY_FRONT_X):\n  "
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
            "lateral_from_track": {"reach_multiplier": GROUND_REACH_MULTIPLIER, "ry_world": LATERAL_RY_GROUND},
            "description": "flat lateral cut at chest height, hit 1 (measured from ground_attack_1 art)",
        },
        "ground_2": {
            "row": 1, "type": "arc",
            "peak": 0.55,
            "track_clip": "ground_attack_2",
            "lateral_from_track": {"reach_multiplier": GROUND_REACH_MULTIPLIER, "ry_world": LATERAL_RY_GROUND},
            "description": "flat lateral backhand cut at waist height, hit 2 (measured from ground_attack_2 art)",
        },
        "ground_3": {
            "row": 2, "type": "arc",
            "peak": 0.62,
            "track_clip": "ground_attack_3",
            "lateral_from_track": {"reach_multiplier": FINISHER_REACH_MULTIPLIER, "ry_world": LATERAL_RY_FINISHER},
            "description": "flat lateral finisher cut at chest height, wider/thicker/farther reach (measured from ground_attack_3 art)",
        },
        "crouch": {
            "row": 3, "type": "arc",
            "a_from": 205.0, "a_to": 345.0,
            "flare": 1.25, "peak": 0.50,
            "description": "low flat horizontal sweep near the ground",
        },
        "up": {
            "row": 4, "type": "thrust",
            "angle_deg": -75.0,
            "half_width_px": 28.0,
            "description": "vertical thrust streak along ruler axis above raised hand",
        },
        "air": {
            "row": 5, "type": "arc",
            "a_from": 190.0, "a_to": 350.0,
            "flare": 1.30, "peak": 0.55,
            "description": "lateral horizontal air sweep forward",
        },
    }

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
                    spec["a_from"], spec["a_to"], spec["peak"],
                )
            else:
                frame_img = render_thrust_frame(
                    frame, geometry["cx"], geometry["cy"], spec["angle_deg"],
                    geometry["length_px"], spec["half_width_px"],
                )
            sheet.paste(frame_img, (frame * CELL_WIDTH, row * CELL_HEIGHT), frame_img)

        manifest_variants[name] = {
            "row": row,
            "reference_hitbox_size": list(size),
            "reference_hitbox_offset": list(offset),
            "anchor": [geometry["anchor"][0], geometry["anchor"][1]],
            "description": spec["description"],
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

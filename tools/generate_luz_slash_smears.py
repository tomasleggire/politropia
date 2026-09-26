#!/usr/bin/env python3
"""Generate Luz's Blasphemous-style crescent slash smear and thrust VFX sheet.

- 6 variants x 5 frames:
  - ground_1: diagonal cut sweeping down-forward
  - ground_2: reverse backhand hook sweeping FORWARD in the facing direction
  - ground_3: wider, thicker finisher sweep forward
  - crouch: low flat horizontal sweep forward
  - up: vertical thrust streak (narrow spindle along ruler axis, no clipping)
  - air: lateral horizontal sweep forward
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


def track_driven_arc(clip_track: dict, cx: float, cy: float) -> tuple[float, float, float, tuple[float, float]]:
    """Derives (a_from, a_to, radius, pivot_world) for an arc variant from the
    measured per-frame ruler tip/grip path
    (assets/player/luz/luz_ruler_track.json) instead of hand-picked constants.

    Pivot: the hand-authored variants center their ellipse on the *hitbox*
    center, sized from the hitbox's own half-extents -- that made sense when
    the hitbox was deliberately enlarged past the (placeholder) art's real
    reach. T4's hitbox_ground is now tightly re-derived to hug the actual
    drawn ruler (grip to tip + a small tolerance, see player.gd), so it sits
    very close to the tip itself; centering the ellipse there any more makes
    it a barely-visible sliver (measured: radius ~34px vs the ~280px a bold
    Blasphemous-style crescent needs). Pivoting at the character's own local
    origin (feet) instead put the whole arc up past her shoulder, off to one
    side -- also wrong (the tip's angle *around the feet* isn't where the
    swing actually happens). The grip position (the hand, i.e. roughly the
    swing's actual mechanical pivot) is stable and centrally located across
    the whole windup/contact/follow-through path, so its per-frame average
    is used as the ellipse's pivot; the radius is then fit so the boundary
    passes exactly through the contact frame's measured tip (as required).
    """
    frames = clip_track["frames"]
    contact_index = clip_track["contact_frame"]
    # Exclude the ready-stance bookend frames (0 and the last), which loop
    # the combo back to its own start and are not part of the swing arc.
    swing_indices = list(range(1, len(frames) - 1))

    pivot_x = sum(frames[i]["grip"]["x"] for i in swing_indices) / len(swing_indices)
    pivot_y = sum(frames[i]["grip"]["y"] for i in swing_indices) / len(swing_indices)

    def to_px(world: dict) -> tuple[float, float]:
        return cx + (world["x"] - pivot_x) * DESIGN_SCALE, cy + (world["y"] - pivot_y) * DESIGN_SCALE

    def angle_for(frame_index: int) -> float:
        px, py = to_px(frames[frame_index]["tip"])
        return math.degrees(math.atan2(py - cy, px - cx)) % 360.0

    raw_angles = [angle_for(i) for i in swing_indices]
    unwrapped = [raw_angles[0]]
    for ang in raw_angles[1:]:
        prev = unwrapped[-1]
        delta = ((ang - prev) + 180.0) % 360.0 - 180.0
        unwrapped.append(prev + delta)
    a_from, a_to = unwrapped[0], unwrapped[-1]
    if a_to < a_from:
        a_from, a_to = a_to, a_from

    # A per-step shortest-path unwrap can still accumulate a total span past
    # a full circle when one recovery frame swings back sharply (measured on
    # ground_3: 370.8deg, which visibly rendered as a near-complete ring
    # instead of a crescent -- render_crescent_frame's modular angle math
    # assumes span <= 360). Cap it, keeping a_to (the later, more visually
    # prominent follow-through direction) fixed and pulling a_from in --
    # this only trims how far back into the windup the crescent reaches.
    MAX_SPAN_DEG = 280.0
    if a_to - a_from > MAX_SPAN_DEG:
        a_from = a_to - MAX_SPAN_DEG

    contact_px, contact_py = to_px(frames[contact_index]["tip"])
    radius = math.hypot(contact_px - cx, contact_py - cy)
    return a_from, a_to, radius, (pivot_x, pivot_y)


def build_variant_geometry(
    name: str, config: dict, size: tuple[float, float], offset: tuple[float, float], track: dict
) -> dict:
    design_w = size[0] * DESIGN_SCALE
    design_h = size[1] * DESIGN_SCALE
    cx = CELL_WIDTH / 2.0
    cy = CELL_HEIGHT / 2.0

    track_clip = config.get("track_clip")
    if track_clip and track.get("clips", {}).get(track_clip):
        a_from, a_to, radius, pivot = track_driven_arc(track["clips"][track_clip], cx, cy)
        config["a_from"], config["a_to"] = a_from, a_to
        rx = ry = radius
        anchor_x = cx - pivot[0] * DESIGN_SCALE
        anchor_y = cy - pivot[1] * DESIGN_SCALE
        print(f"  {name}: track-driven a_from={a_from:.1f} a_to={a_to:.1f} radius={radius:.1f} pivot={pivot}")
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


def main() -> int:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)

    hitbox_configs = parse_player_hitboxes()
    ruler_track = load_ruler_track()

    variant_specs = {
        "ground_1": {
            "row": 0, "type": "arc",
            # a_from/a_to/flare are overwritten from the measured ruler tip
            # path (assets/player/luz/luz_ruler_track.json) in
            # build_variant_geometry when track_clip data is available; these
            # are only the fallback if the track is ever missing.
            "a_from": 220.0, "a_to": 380.0,
            "flare": 1.30, "peak": 0.55,
            "track_clip": "ground_attack_1",
            "description": "forward diagonal cut, behind-high to front-low (measured from ground_attack_1 art)",
        },
        "ground_2": {
            "row": 1, "type": "arc",
            # a_from/a_to/radius overwritten from measured tip path (fallback only).
            "a_from": 250.0, "a_to": 400.0,
            "flare": 1.30, "peak": 0.55,
            "track_clip": "ground_attack_2",
            "description": "backhand hook sweeping low-to-horizontal-to-up (measured from ground_attack_2 art)",
        },
        "ground_3": {
            "row": 2, "type": "arc",
            # a_from/a_to/radius overwritten from measured tip path (fallback only).
            "a_from": 190.0, "a_to": 380.0,
            "flare": 1.35, "peak": 0.62,
            "track_clip": "ground_attack_3",
            "description": "finisher, low windup lunging to a rising follow-through (measured from ground_attack_3 art)",
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

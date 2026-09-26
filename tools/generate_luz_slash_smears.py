#!/usr/bin/env python3
"""Generate Luz's Blasphemous-style crescent slash smear VFX sheet.

Technique (see the approved prototype this was developed from): a band of a
flattened ellipse between rho=1-thickness and rho=1, swept over an angle
range; thickness follows a sine profile along the sweep so the crescent is
thick near its leading edge and tapers to a thin tail; a 4-tone pale
mint/white palette with checker dithering on the inner rim and tail keeps it
readable as chunky pixel art. Five frames per variant: sweep-in, full,
thinning, dissolve, residue. `up` is the exception (T3b): it is a narrow
thrust *streak*, not a crescent -- see render_thrust_frame.

Geometry (arc pivot/radii/tilt or thrust base/angle/length) is read from
assets/player/luz/luz_attack_swings.json, the single source of truth shared
with scripts/player/ruler_weapon.gd, so the smear always matches the
procedural ruler's swing exactly. Presentation-only parameters that have no
gameplay meaning (palette, thickness peak, dither) stay local to this script.

Output: assets/player/luz/vfx/luz_slash_smears.png (one row per variant, 5
uniform cells per row) plus assets/player/luz/vfx/luz_slash_smears_manifest.json
recording cell size and each variant's reference hitbox size + local pixel
anchor (the point that maps to the player's feet origin at runtime), so
player_slash_vfx.gd can scale/position a frame from the *current* hitbox
tunables instead of a hardcoded transform.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image

REPO_ROOT = Path(__file__).resolve().parent.parent
ASSET_ROOT = REPO_ROOT / "assets" / "player" / "luz"
OUTPUT_DIR = ASSET_ROOT / "vfx"
PREVIEW_DIR = REPO_ROOT / "tools" / "art_sources" / "luz" / "preview"
SWING_MODEL_PATH = ASSET_ROOT / "luz_attack_swings.json"

PX = 3  # art-pixel block size, matches the character art's apparent pixel
        # size at the same 0.175 in-game display scale.
CELL_WIDTH = 720
# Tall enough that the "up" thrust (a full extend_length reach from a
# near-bottom base, not a radius from center like the arc variants) fits
# without clipping: extend_length(88 world units) * design_scale(~5.71) is
# ~503px; a near-bottom origin plus this height leaves headroom above it.
CELL_HEIGHT = 640
FRAME_COUNT = 5

PALETTE = [
    (240, 252, 244),
    (205, 240, 226),
    (150, 205, 192),
    (92, 146, 146),
]

# Per-frame sweep progress: lead_p/tail_p bound the visible slice of the
# sweep (0..1 fraction, angle-fraction for an arc / length-fraction for the
# up thrust), fade scales overall alpha. Shared across every variant so the
# whole VFX sheet animates on one consistent timing.
FRAME_LEAD = [0.55, 1.0, 1.0, 1.0, 1.0]
FRAME_TAIL = [0.0, 0.0, 0.30, 0.55, 0.80]
FRAME_FADE = [1.0, 1.0, 0.85, 0.60, 0.35]

# Smear-only presentation tuning per variant (thickness peak for the crescent
# band, or half-width for the up thrust streak); geometry itself comes from
# luz_attack_swings.json.
PEAK_BY_KIND = {
    "ground_1": 0.55,
    "ground_2": 0.50,
    "ground_3": 0.62,
    "crouch": 0.50,
    "air": 0.55,
}
ROW_BY_KIND = {
    "ground_1": 0,
    "ground_2": 1,
    "ground_3": 2,
    "crouch": 3,
    "up": 4,
    "air": 5,
}
UP_HALF_WIDTH_FRACTION = 0.16  # fraction of extend_length, at the streak's widest point


def render_ellipse_frame(
    frame: int, cx: float, cy: float, rx: float, ry: float,
    tilt_deg: float, a_from: float, a_to: float, peak: float,
) -> Image.Image:
    lead_p = FRAME_LEAD[frame]
    tail_p = FRAME_TAIL[frame]
    fade = FRAME_FADE[frame]
    span = a_to - a_from
    tilt = math.radians(tilt_deg)
    cos_t, sin_t = math.cos(-tilt), math.sin(-tilt)

    low_w, low_h = CELL_WIDTH // PX, CELL_HEIGHT // PX
    img = Image.new("RGBA", (low_w, low_h), (0, 0, 0, 0))
    px = img.load()

    for ly in range(low_h):
        for lx in range(low_w):
            x, y = lx * PX, ly * PX
            dx, dy = x - cx, y - cy
            # Rotate into the ellipse's own (untilted) local frame.
            rdx = dx * cos_t - dy * sin_t
            rdy = dx * sin_t + dy * cos_t
            u = rdx / rx
            v = rdy / ry
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
    """Narrow lens/spindle-shaped streak along the thrust direction: zero
    width at the base and at the tip, widest at the middle -- reads as a
    vertical energy spike rather than a crescent."""
    lead_p = FRAME_LEAD[frame]
    tail_p = FRAME_TAIL[frame]
    fade = FRAME_FADE[frame]

    angle = math.radians(angle_deg)
    dirx, diry = math.cos(angle), math.sin(angle)
    perpx, perpy = -diry, dirx

    low_w, low_h = CELL_WIDTH // PX, CELL_HEIGHT // PX
    img = Image.new("RGBA", (low_w, low_h), (0, 0, 0, 0))
    px = img.load()

    for ly in range(low_h):
        for lx in range(low_w):
            x, y = lx * PX, ly * PX
            dx, dy = x - cx, y - cy
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
            if local < 0.15 and dither:
                continue
            if fade < 0.7 and (lx * 7 + ly * 3) % 3 == 0:
                continue
            px[lx, ly] = color + (255,)

    return img.resize((CELL_WIDTH, CELL_HEIGHT), Image.NEAREST)


def build_variant_geometry(kind: str, config: dict, design_scale: float) -> dict:
    cx = CELL_WIDTH / 2.0
    if config["type"] == "thrust":
        # Origin near the bottom of the cell (not centered) so the full
        # upward extend_length reach fits without clipping the tip.
        origin_y = CELL_HEIGHT - 60.0
        base = config["base"]
        anchor_x = cx - base[0] * design_scale
        anchor_y = origin_y - base[1] * design_scale
        length_px = config["extend_length"] * design_scale
        half_width_px = length_px * UP_HALF_WIDTH_FRACTION
        return {
            "cx": cx, "cy": origin_y, "anchor": (anchor_x, anchor_y),
            "length_px": length_px, "half_width_px": half_width_px,
            "angle_deg": config["angle_deg"],
        }
    cy = CELL_HEIGHT / 2.0
    size = config["hitbox_size"]
    offset = config["hitbox_offset"]
    flare = config["flare"]
    rx = (size[0] * design_scale / 2.0) * flare
    ry = (size[1] * design_scale / 2.0) * flare
    anchor_x = cx - offset[0] * design_scale
    anchor_y = cy - offset[1] * design_scale
    return {
        "cx": cx, "cy": cy, "rx": rx, "ry": ry, "anchor": (anchor_x, anchor_y),
        "tilt_deg": config["tilt_deg"], "a_from": config["theta_start"], "a_to": config["theta_end"],
    }


def main() -> int:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)

    swing_model = json.loads(SWING_MODEL_PATH.read_text())
    design_scale = swing_model["design_scale"]
    kinds = swing_model["kinds"]

    row_count = len(ROW_BY_KIND)
    sheet = Image.new("RGBA", (CELL_WIDTH * FRAME_COUNT, CELL_HEIGHT * row_count), (0, 0, 0, 0))

    manifest_variants = {}
    descriptions = {
        "ground_1": "forward diagonal cut, behind-high to front-low",
        "ground_2": "horizontal forward cut, short punchy raise-and-snap",
        "ground_3": "finisher, widest and thickest horizontal sweep",
        "crouch": "low flat sweep near the ground",
        "up": "narrow vertical thrust streak straight above the head",
        "air": "lateral air sweep",
    }

    for name, row in ROW_BY_KIND.items():
        config = kinds[name]
        geometry = build_variant_geometry(name, config, design_scale)
        print(f"{name}: row={row} geometry={ {k: v for k, v in geometry.items() if k not in ('cx','cy')} }")
        for frame in range(FRAME_COUNT):
            if config["type"] == "thrust":
                frame_img = render_thrust_frame(
                    frame, geometry["cx"], geometry["cy"],
                    geometry["angle_deg"], geometry["length_px"], geometry["half_width_px"],
                )
            else:
                frame_img = render_ellipse_frame(
                    frame, geometry["cx"], geometry["cy"], geometry["rx"], geometry["ry"],
                    geometry["tilt_deg"], geometry["a_from"], geometry["a_to"], PEAK_BY_KIND[name],
                )
            sheet.paste(frame_img, (frame * CELL_WIDTH, row * CELL_HEIGHT), frame_img)
        manifest_variants[name] = {
            "row": row,
            "reference_hitbox_size": list(config["hitbox_size"]),
            "reference_hitbox_offset": list(config["hitbox_offset"]) if config["type"] != "thrust" else [0.0, 0.0],
            "anchor": [geometry["anchor"][0], geometry["anchor"][1]],
            "description": descriptions[name],
        }

    out_path = OUTPUT_DIR / "luz_slash_smears.png"
    sheet.save(out_path)
    print(f"wrote {out_path} ({sheet.size[0]}x{sheet.size[1]})")

    manifest = {
        "cell_width": CELL_WIDTH,
        "cell_height": CELL_HEIGHT,
        "frame_count": FRAME_COUNT,
        "display_scale": 0.175,
        "variants": manifest_variants,
    }
    manifest_path = OUTPUT_DIR / "luz_slash_smears_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"wrote {manifest_path}")

    # Contact sheet preview: outline every cell + label.
    from PIL import ImageDraw, ImageFont
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 18)
    except OSError:
        font = ImageFont.load_default()
    contact = Image.new("RGBA", sheet.size, (30, 30, 34, 255))
    contact.alpha_composite(sheet)
    draw = ImageDraw.Draw(contact)
    for name, row in ROW_BY_KIND.items():
        draw.rectangle([0, row * CELL_HEIGHT, sheet.size[0] - 1, (row + 1) * CELL_HEIGHT - 1], outline=(255, 0, 255, 255), width=1)
        draw.text((6, row * CELL_HEIGHT + 6), name, fill=(255, 255, 0, 255), font=font)
        for frame in range(FRAME_COUNT):
            draw.line([(frame * CELL_WIDTH, row * CELL_HEIGHT), (frame * CELL_WIDTH, (row + 1) * CELL_HEIGHT)], fill=(255, 0, 255, 120))
    contact_path = PREVIEW_DIR / "luz_slash_smears__contact_sheet.png"
    contact.save(contact_path)
    print(f"wrote {contact_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

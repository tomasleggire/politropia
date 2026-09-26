#!/usr/bin/env python3
"""Generate Luz's Blasphemous-style crescent slash smear VFX sheet.

Technique (see the approved prototype this was developed from): a band of a
flattened ellipse between rho=1-thickness and rho=1, swept over an angle
range; thickness follows a sine profile along the sweep so the crescent is
thick at its leading edge and tapers to a thin tail; a 4-tone pale mint/white
palette with checker dithering on the inner rim and tail keeps it readable as
chunky pixel art. Five frames per variant: sweep-in, full, thinning,
dissolve, residue.

Each variant is authored against the CURRENT (already-enlarged) hitbox
size/offset for its attack (see player.gd's "Attack Hitboxes" export group)
so a frame's crescent naturally covers that attack's active hitbox rect.
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
OUTPUT_DIR = REPO_ROOT / "assets" / "player" / "luz" / "vfx"
PREVIEW_DIR = REPO_ROOT / "tools" / "art_sources" / "luz" / "preview"

PX = 3  # art-pixel block size, matches the character art's apparent pixel
        # size at the same 0.175 in-game display scale.
CELL_WIDTH = 720
CELL_HEIGHT = 460
FRAME_COUNT = 5

# 1 world/hitbox unit -> this many design pixels, so a variant authored
# against its hitbox_*_size in world units lands at the right pixel size for
# the shared 0.175 display scale (matching the character sprite).
DESIGN_SCALE = 1.0 / 0.175

PALETTE = [
    (240, 252, 244),
    (205, 240, 226),
    (150, 205, 192),
    (92, 146, 146),
]

# Per-frame sweep progress: lead_p/tail_p bound the visible angular slice
# (as a 0..1 fraction of the full sweep span), fade scales overall alpha.
FRAME_LEAD = [0.55, 1.0, 1.0, 1.0, 1.0]
FRAME_TAIL = [0.0, 0.0, 0.30, 0.55, 0.80]
FRAME_FADE = [1.0, 1.0, 0.85, 0.60, 0.35]

# Each variant's hitbox_size/offset must match player.gd's current exported
# Vector2 values for that attack -- keep these two in sync.
VARIANTS = {
    "ground_1": {
        "row": 0,
        "hitbox_size": (76.0, 32.0),
        "hitbox_offset": (46.0, -35.0),
        "a_from": 220.0, "a_to": 380.0,
        "flare": 1.30, "peak": 0.55,
        "description": "forward diagonal cut, behind-high to front-low",
    },
    "ground_2": {
        "row": 1,
        "hitbox_size": (76.0, 32.0),
        "hitbox_offset": (46.0, -35.0),
        "a_from": 70.0, "a_to": 260.0,
        "flare": 1.30, "peak": 0.55,
        "description": "reverse backhand, low arc sweeping up-and-back",
    },
    "ground_3": {
        "row": 2,
        "hitbox_size": (90.0, 38.0),
        "hitbox_offset": (53.0, -34.0),
        "a_from": 190.0, "a_to": 380.0,
        "flare": 1.35, "peak": 0.62,
        "description": "finisher, widest and thickest horizontal sweep",
    },
    "crouch": {
        "row": 3,
        "hitbox_size": (72.0, 20.0),
        "hitbox_offset": (43.0, -13.0),
        "a_from": 205.0, "a_to": 345.0,
        "flare": 1.25, "peak": 0.50,
        "description": "low flat sweep near the ground",
    },
    "up": {
        "row": 4,
        "hitbox_size": (26.0, 68.0),
        "hitbox_offset": (0.0, -89.0),
        "a_from": 200.0, "a_to": 340.0,
        "flare": 1.30, "peak": 0.55,
        "description": "vertical crescent over the head, arcing front-to-back over the top",
    },
    "air": {
        "row": 5,
        "hitbox_size": (74.0, 30.0),
        "hitbox_offset": (45.0, -40.0),
        "a_from": 190.0, "a_to": 350.0,
        "flare": 1.30, "peak": 0.55,
        "description": "lateral air sweep",
    },
}


def render_frame(
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


def build_variant_geometry(config: dict) -> dict:
    design_w = config["hitbox_size"][0] * DESIGN_SCALE
    design_h = config["hitbox_size"][1] * DESIGN_SCALE
    flare = config["flare"]
    cx = CELL_WIDTH / 2.0
    cy = CELL_HEIGHT / 2.0
    rx = (design_w / 2.0) * flare
    ry = (design_h / 2.0) * flare
    anchor_x = cx - config["hitbox_offset"][0] * DESIGN_SCALE
    anchor_y = cy - config["hitbox_offset"][1] * DESIGN_SCALE
    return {"cx": cx, "cy": cy, "rx": rx, "ry": ry, "anchor": (anchor_x, anchor_y)}


def main() -> int:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    row_count = len(VARIANTS)
    sheet = Image.new("RGBA", (CELL_WIDTH * FRAME_COUNT, CELL_HEIGHT * row_count), (0, 0, 0, 0))

    manifest_variants = {}
    for name, config in VARIANTS.items():
        geometry = build_variant_geometry(config)
        row = config["row"]
        print(f"{name}: row={row} rx={geometry['rx']:.1f} ry={geometry['ry']:.1f} anchor={geometry['anchor']}")
        for frame in range(FRAME_COUNT):
            frame_img = render_frame(
                frame, geometry["cx"], geometry["cy"], geometry["rx"], geometry["ry"],
                config["a_from"], config["a_to"], config["peak"],
            )
            sheet.paste(frame_img, (frame * CELL_WIDTH, row * CELL_HEIGHT), frame_img)
        manifest_variants[name] = {
            "row": row,
            "reference_hitbox_size": list(config["hitbox_size"]),
            "reference_hitbox_offset": list(config["hitbox_offset"]),
            "anchor": [geometry["anchor"][0], geometry["anchor"][1]],
            "description": config["description"],
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
    for name, config in VARIANTS.items():
        row = config["row"]
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

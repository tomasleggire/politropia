#!/usr/bin/env python3
"""Composite each Luz slash smear variant over its attack's contact frame,
with the current hitbox rect outlined, for visual sanity-checking.

Not part of the runtime pipeline -- a verification helper for
tools/process_luz_sheet.py (character sheets) and
tools/generate_luz_slash_smears.py (smear sheet). Output goes to the same
gitignored preview directory as those tools.

Both the character sheets and the smear sheet are authored at the same
0.175 world-units-per-pixel ratio (the character's AnimatedSprite2D.scale
and the smear generator's DESIGN_SCALE = 1/0.175), and both share a fixed
world-origin anchor per sheet (character: canvas (256, 413), from
AnimatedSprite2D centered=true + offset=(0,-157) on a 512 canvas; smear:
each variant's own "anchor" in its manifest) -- so they can be composited by
directly aligning those anchor points, exactly as player_slash_vfx.gd does
at runtime via Sprite2D.offset.
"""

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps

REPO_ROOT = Path(__file__).resolve().parent.parent
ASSETS = REPO_ROOT / "assets" / "player" / "luz"
PREVIEW_DIR = REPO_ROOT / "tools" / "art_sources" / "luz" / "preview"

DISPLAY_SCALE = 0.175
CHARACTER_CANVAS = 512
PREVIEW_CANVAS = (1000, 1000)
CHARACTER_ANCHOR = (256.0, 413.0)  # AnimatedSprite2D centered=true, offset=(0,-157)
PREVIEW_ANCHOR = (400.0, 850.0)  # where CHARACTER_ANCHOR/world-origin lands on the bigger preview canvas
SMEAR_FRAME_TO_SHOW = 1  # "full" frame, per FRAME_LEAD/FRAME_TAIL in generate_luz_slash_smears.py

# (sheet, absolute contact-cell index, hitbox_size, hitbox_offset, smear variant)
# Hitbox values must match player.gd's current "Attack Hitboxes" export group.
CASES = [
    ("luz_ground_combat_sheet.png", 3, (60.3, 24.0), (49.15, -27.2), "ground_1"),
    ("luz_ground_combat_sheet.png", 11, (60.3, 24.0), (49.15, -27.2), "ground_2"),
    ("luz_ground_combat_sheet.png", 19, (60.3, 24.0), (49.15, -27.2), "ground_3"),
    ("luz_ground_combat_sheet.png", 27, (60.3, 24.0), (49.15, -17.02), "crouch"),
    ("luz_air_combat_sheet.png", 3, (24.0, 60.3), (0.0, -49.15), "up"),
    ("luz_air_combat_sheet.png", 11, (60.3, 24.0), (49.15, -30.66), "air"),
]


def main() -> int:
    smear_manifest = json.loads((ASSETS / "vfx" / "luz_slash_smears_manifest.json").read_text())
    smear_sheet = Image.open(ASSETS / "vfx" / "luz_slash_smears.png").convert("RGBA")
    cell_w = smear_manifest["cell_width"]
    cell_h = smear_manifest["cell_height"]

    for sheet_name, cell_index, hitbox_size, hitbox_offset, variant_name in CASES:
        character_sheet = Image.open(ASSETS / sheet_name).convert("RGBA")
        col, row = cell_index % 4, cell_index // 4
        char_frame = character_sheet.crop((
            col * CHARACTER_CANVAS, row * CHARACTER_CANVAS,
            (col + 1) * CHARACTER_CANVAS, (row + 1) * CHARACTER_CANVAS,
        ))

        variant = smear_manifest["variants"][variant_name]
        anchor = variant["anchor"]
        smear_row = variant["row"]
        smear_frame = smear_sheet.crop((
            SMEAR_FRAME_TO_SHOW * cell_w, smear_row * cell_h,
            (SMEAR_FRAME_TO_SHOW + 1) * cell_w, (smear_row + 1) * cell_h,
        ))
        # Runtime scale (see player_slash_vfx.gd.play_slash): identity here
        # since CASES uses the same hitbox values the smear was authored
        # against, so no extra resize is needed for this check.

        char_paste = (int(round(PREVIEW_ANCHOR[0] - CHARACTER_ANCHOR[0])), int(round(PREVIEW_ANCHOR[1] - CHARACTER_ANCHOR[1])))
        for facing in ("right", "left"):
            facing_char = char_frame if facing == "right" else ImageOps.mirror(char_frame)
            facing_smear = smear_frame if facing == "right" else ImageOps.mirror(smear_frame)
            smear_anchor_x = anchor[0] if facing == "right" else cell_w - anchor[0]
            smear_paste = (
                int(round(PREVIEW_ANCHOR[0] - smear_anchor_x)),
                int(round(PREVIEW_ANCHOR[1] - anchor[1])),
            )
            canvas = Image.new("RGBA", PREVIEW_CANVAS, (30, 30, 34, 255))
            canvas.alpha_composite(facing_char, char_paste)
            canvas.alpha_composite(facing_smear, smear_paste)

            direction = 1.0 if facing == "right" else -1.0
            center_x = PREVIEW_ANCHOR[0] + direction * hitbox_offset[0] / DISPLAY_SCALE
            hx0 = center_x - hitbox_size[0] / (2.0 * DISPLAY_SCALE)
            hx1 = center_x + hitbox_size[0] / (2.0 * DISPLAY_SCALE)
            hy0 = PREVIEW_ANCHOR[1] + (hitbox_offset[1] - hitbox_size[1] / 2.0) / DISPLAY_SCALE
            hy1 = PREVIEW_ANCHOR[1] + (hitbox_offset[1] + hitbox_size[1] / 2.0) / DISPLAY_SCALE
            draw = ImageDraw.Draw(canvas)
            draw.rectangle([hx0, hy0, hx1, hy1], outline=(255, 60, 60, 255), width=2)
            draw.ellipse([PREVIEW_ANCHOR[0] - 3, PREVIEW_ANCHOR[1] - 3, PREVIEW_ANCHOR[0] + 3, PREVIEW_ANCHOR[1] + 3], fill=(255, 255, 0, 255))

            out_path = PREVIEW_DIR / f"slash_composite__{variant_name}__{facing}.png"
            canvas.save(out_path)
            print(f"wrote {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

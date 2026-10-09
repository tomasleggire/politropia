"""Measures the ruler grip and tip of every attack frame of Luz and writes
assets/player/luz/luz_ruler_tips.json, read by PlayerSlashVfx.

Positions are in the player's local pixels (x right, y down, origin at the
feet) for a right-facing Luz: the sprite node is centred on the cell, scaled by
SPRITE_SCALE and offset up by FEET_OFFSET texels, so
    local = ((px - cell_w / 2) * scale, (py - cell_h / 2 - FEET_OFFSET) * scale).

Run with a python that has pillow and numpy:
    python tools/luz_ruler_tip_track.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import luz_ruler_length as lrl  # noqa: E402

LUZ = ROOT / "assets" / "player" / "luz"
SPRITE_SCALE = 0.1448
FEET_OFFSET = 157.0


def main() -> int:
    manifest = json.loads((LUZ / "animation_manifest.json").read_text())
    out: dict[str, list] = {}
    for sheet_name in ("luz_ground_combat_sheet.png", "luz_air_combat_sheet.png"):
        sheet = manifest["sheets"][sheet_name]
        grid = sheet["grid"]
        cw, ch, cols = grid["cell_width"], grid["cell_height"], grid["columns"]
        image = Image.open(LUZ / sheet_name).convert("RGBA")
        for clip, indices in sheet["clips"].items():
            if "attack" not in clip:
                continue
            rows = []
            for index in indices:
                x0, y0 = (index % cols) * cw, (index // cols) * ch
                cell = np.array(image.crop((x0, y0, x0 + cw, y0 + ch)))
                ruler = lrl.find_ruler(cell)
                if ruler is None:
                    rows.append(None)
                    continue
                grip = ruler.origin + ruler.d * ruler.t_grip
                tip = ruler.origin + ruler.d * ruler.t_tip
                rows.append([
                    round(float((p[0] - cw / 2) * SPRITE_SCALE), 1) if k == 0
                    else round(float((p[1] - ch / 2 - FEET_OFFSET) * SPRITE_SCALE), 1)
                    for p in (grip, tip) for k in (0, 1)
                ])
            out[clip] = rows
    (LUZ / "luz_ruler_tips.json").write_text(json.dumps(out, indent=None, separators=(",", ":")))
    for clip, rows in out.items():
        print(clip)
        for i, r in enumerate(rows):
            print("  ", i, r)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Process the P11 Luz focus and Stillness Desk raws into aligned sprite sheets.

Inputs are 3x3 512px cells in tools/art_sources/luz/raw. Output frames use the
catalog's 512x512 frame geometry (feet row 413), retaining the desk's
150-texel seat lift and frame beats while measuring the focus ruler to 215 texels.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import luz_ruler_length as ruler  # noqa: E402
import process_luz_combat_hits as pch  # noqa: E402

RAW = ROOT / "tools/art_sources/luz/raw"
ASSETS = ROOT / "assets/player/luz"
MANIFEST = ASSETS / "animation_manifest.json"
CELL_W, CELL_H, FEET_ROW = 512, 512, 413
ANCHOR_X = 256
SEAT_LIFT = 150


def key_magenta(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    pixels = np.asarray(rgba).copy()
    r, g, b = (pixels[..., i].astype(np.int16) for i in range(3))
    magenta = (np.minimum(r, b) - g) > 100
    pixels[magenta, 3] = 0
    return Image.fromarray(pixels)


def frames(path: str, count: int) -> list[Image.Image]:
    image = key_magenta(Image.open(RAW / path))
    if image.size != (1536, 1536):
        raise ValueError(f"{path}: expected 1536x1536, got {image.size}")
    result: list[Image.Image] = []
    for index in range(count):
        x, y = (index % 3) * 512, (index // 3) * 512
        result.append(image.crop((x, y, x + 512, y + 512)))
    return result


def content_box(source: Image.Image) -> tuple[int, int, int, int]:
    alpha = np.asarray(source.getchannel("A")) > 8
    ys, xs = np.nonzero(alpha)
    if len(xs) < 100:
        raise ValueError("frame has no character pixels")
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def place(source: Image.Image, scale: float, lift: int, label: str, normalize_ruler: bool = True) -> Image.Image:
    x0, y0, x1, y1 = content_box(source)
    crop = source.crop((x0, y0, x1, y1))
    width, height = max(1, round(crop.width * scale)), max(1, round(crop.height * scale))
    resized = crop.resize((width, height), Image.Resampling.LANCZOS)
    left = round(ANCHOR_X - (210 - x0) * scale)
    top = FEET_ROW - lift - (height - 1)
    if left < 0 or left + width > CELL_W or top < 0:
        raise ValueError(f"{label}: placed image out of bounds ({left},{top},{width},{height})")
    output = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    output.alpha_composite(resized, (left, top))
    if not normalize_ruler:
        return output
    # Focus poses can begin with a short ruler. Permit the utility to swing it
    # clear of the cell edge, then remeasure/rebuild until the 215-texel target
    # converges (the first pass can be constrained).
    ruler.MAX_TILT = 70.0
    # Focus art intentionally plants the ruler tip at the sole row; the standard
    # locomotion clearance would swing this upright prop far away from the floor.
    ruler.FLOOR_CLEARANCE = -10.0
    info = {}
    measured = output
    for _ in range(3):
        measured, info = ruler.normalize_ruler(measured, label=label)
    if not info.get("found") or info.get("after") is None:
        print(f"WARN {label}: ruler measurement unavailable; retaining keyed frame")
        return output
    if info.get("found") and info.get("after") is not None:
        if abs(float(info["after"]) - 215.0) > 8.0:
            print(f"WARN {label}: ruler length {info['after']:.1f} texels after normalization")
        output = measured
    return output


def assemble(sheet_name: str, clips: dict[str, list[tuple[Image.Image, int, str, float, bool]]]) -> dict:
    total = sum(len(items) for items in clips.values())
    columns = 4
    rows = (total + columns - 1) // columns
    atlas = Image.new("RGBA", (columns * CELL_W, rows * CELL_H), (0, 0, 0, 0))
    layout: dict[str, list[int]] = {}
    cursor = 0
    for name, items in clips.items():
        layout[name] = []
        for source, lift, label, scale, normalize in items:
            frame = place(source, scale, lift, label, normalize)
            atlas.alpha_composite(frame, ((cursor % columns) * CELL_W, (cursor // columns) * CELL_H))
            layout[name].append(cursor)
            cursor += 1
    atlas.save(ASSETS / sheet_name)
    return {"grid": {"columns": columns, "rows": rows, "cell_width": CELL_W, "cell_height": CELL_H}, "clips": layout}


def main() -> int:
    heal = frames("luz_heal_raw.png", 9)
    mount = frames("luz_rest_mount_v2_raw.png", 8)
    sit = frames("luz_rest_sit_v2_raw.png", 6)
    dismount = frames("luz_rest_dismount_v2_raw.png", 8)
    standing_height = 331.5
    heal_scale = standing_height / float(np.median([content_box(frame)[3] - content_box(frame)[1] for frame in heal]))
    mount_scale = standing_height / float(content_box(mount[0])[3] - content_box(mount[0])[1])
    dismount_scale = standing_height / float(content_box(dismount[-1])[3] - content_box(dismount[-1])[1])
    rest_scale = (mount_scale + dismount_scale) * 0.5
    mount_lifts = (0, 0, 0, 0, 20, 34, SEAT_LIFT, SEAT_LIFT)
    dismount_lifts = (SEAT_LIFT, 48, 60, 0, 0, 0, 0, 0)
    seated_frames = [mount[6], mount[7], *(sit[i] for i in (0, 1, 3, 4)), dismount[0]]
    max_seated_height = max(content_box(frame)[3] - content_box(frame)[1] for frame in seated_frames)
    seat_scale = min(rest_scale, (FEET_ROW - SEAT_LIFT - 2) / max_seated_height)
    heal_sheet = assemble("luz_heal_sheet.png", {
        "heal_start": [(frame, 0, f"heal_start[{i}]", heal_scale, True) for i, frame in enumerate(heal[:3])],
        "heal_loop": [(frame, 0, f"heal_loop[{i}]", heal_scale, True) for i, frame in enumerate(heal[3:7])],
        "heal_end": [(frame, 0, f"heal_end[{i}]", heal_scale, True) for i, frame in enumerate(heal[7:])],
    })
    rest_sheet = assemble("luz_rest_sheet.png", {
        "rest_mount": [
            (frame, lift, f"rest_mount[{i}]", seat_scale if i >= 6 else mount_scale, False)
            for i, (frame, lift) in enumerate(zip(mount, mount_lifts))
        ],
        # Four stable poses make an even, seamless breathing cycle; omit the
        # two transitional extremes in the six-frame raw.
        "rest_sit": [(sit[i], SEAT_LIFT, f"rest_sit[{i}]", seat_scale, False) for i in (0, 1, 3, 4)],
        "rest_dismount": [
            (frame, lift, f"rest_dismount[{i}]", seat_scale if i == 0 else dismount_scale, False)
            for i, (frame, lift) in enumerate(zip(dismount, dismount_lifts))
        ],
    })
    manifest = json.loads(MANIFEST.read_text())
    manifest["sheets"].pop("luz_rest_sheet.png", None)
    manifest["sheets"]["luz_heal_sheet.png"] = heal_sheet
    manifest["sheets"]["luz_rest_sheet.png"] = {
        **rest_sheet,
        "rest_ritual": {
            "seat_height_px": SEAT_LIFT,
            "note": "Seated clips use the shared 150-texel lift from the feet row (413).",
            "lift_px": {
                "rest_mount": list(mount_lifts),
                "rest_sit": [SEAT_LIFT] * 4,
                "rest_dismount": list(dismount_lifts),
            },
        },
    }
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Wrote heal sheet {heal_sheet['grid']} and rest sheet {rest_sheet['grid']}")
    print("Heal frames: start=3, loop=4, end=2; rest: mount=8, sit=4, dismount=8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

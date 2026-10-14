#!/usr/bin/env python3
"""Build Artemis's demo sprite sheets from the raw Codex sheets.

Raw sheets live in tools/art_sources/artemis/raw/ (magenta background, regular
grids, see tools/art_sources/artemis/prompts/minimal_set.md). For each sheet this
script keys the magenta, splits the frames (connected components assigned to the
grid cell they mostly fall in), rescales every frame with ONE scale for the whole
set, puts the lowest sole on the shared feet row, anchors the feet band on the cell
centre and writes assets/enemies/artemis/artemis_<sheet>_sheet.png plus
animation_manifest.json (grid, clips, events).

Scale: Luz is drawn so 331.5 source px become `body_height` 48 px (sprite scale
0.1448). Artemis is 56 px tall (collision box), so her standing figure (hair/circlet
top to sole) is scaled to STAND_HEIGHT output px and the sprite node is scaled by
SPRITE_SCALE = 0.1448 * (512 / OUT_CELL), i.e. the same on-screen pixel size as Luz.

Usage: python tools/process_artemis_sheets.py [--preview DIR]
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = ROOT / "tools" / "art_sources" / "artemis" / "raw"
OUT_DIR = ROOT / "assets" / "enemies" / "artemis"

OUT_CELL = 256
FEET_ROW = 224
COLUMNS = 4
LUZ_SPRITE_SCALE = 0.1448
SPRITE_SCALE = LUZ_SPRITE_SCALE * 512.0 / OUT_CELL
BODY_HEIGHT = 56.0
STAND_HEIGHT = BODY_HEIGHT / SPRITE_SCALE  # output px from hair top to sole
MIN_COMPONENT_PX = 40

# sheet -> raw file, raw grid (cols, rows), reference frame (only used to log the
# resulting height) and clips (names from the contract).
SHEETS = {
    "locomotion": {
        "raw": "artemis_loco_raw.png",
        "grid": (4, 3),
        "ref": 0,
        "clips": {"idle": list(range(0, 6)), "walk_fwd": list(range(6, 12))},
    },
    "shot": {
        "raw": "artemis_shot_raw.png",
        "grid": (4, 3),
        "ref": 11,
        "clips": {
            "shot_draw": [0, 1, 2, 3, 4],
            "shot_hold": [5, 5],
            "shot_release": [6, 7],
            "shot_recover": [8, 9, 10, 11],
        },
        "events": {"shot_release": 0},
    },
    "move": {
        "raw": "artemis_move_raw.png",
        "grid": (4, 3),
        "ref": 9,
        "clips": {
            "backstep": [0, 1, 2, 3, 4],
            "interrupt_flinch": [5, 6, 7, 8, 9],
            "dodge": [10, 11],
        },
    },
    "stagger": {
        "raw": "artemis_down_raw.png",
        "grid": (4, 2),
        "ref": 0,
        "scale_mult": 0.89,
        "clips": {"stagger_in": [6, 7], "stagger_loop": [0, 1, 2, 3, 4, 5]},
    },
    "vault": {
        "raw": "artemis_vault_raw.png",
        "grid": (4, 2),
        "ref": 7,
        "scale_mult": 0.89,
        "clips": {
            "vault_crouch": [0, 1],
            "vault_air": [2, 3, 4, 5],
            "vault_land": [6, 7],
        },
    },
    "rainfan": {
        "raw": "artemis_rainfan_raw.png",
        "grid": (4, 4),
        "ref": 13,
        "clips": {
            "rain_draw": [0, 1, 2, 3, 4],
            "rain_release": [5, 6],
            "rain_recover": [7, 8, 9],
            "fan_draw": [10, 11, 12],
            "fan_hold": [13, 13],
            "fan_release": [14, 15],
        },
        "events": {"rain_release": 0, "fan_release": 0},
    },
    "dagger": {
        "raw": "artemis_dagger_raw.png",
        "grid": (4, 3),
        "ref": 5,
        "clips": {
            "dagger_windup": [0, 1, 2],
            "dagger_slash": [3, 4, 5],
            "dagger_flip": [6, 7, 8, 9, 10, 11],
            "dagger_recover": [11, 11],
        },
    },
    "dive": {
        "raw": "artemis_dive_raw.png",
        "grid": (4, 3),
        "ref": 7,
        "scale_mult": 0.89,
        "clips": {
            "dive_leap": [0, 1, 2],
            "dive_fall": [3, 4],
            "dive_stuck": [5, 6, 7, 8, 9, 10, 11],
        },
    },
    "defeat": {
        "raw": "artemis_defeat_raw.png",
        "grid": (4, 3),
        "ref": 1,
        "clips": {"defeat": list(range(0, 12))},
    },
}


def key_magenta(raw: Image.Image) -> np.ndarray:
    """Return float RGBA (0..1 alpha) with the magenta background keyed out."""
    arr = np.asarray(raw.convert("RGB")).astype(np.int32)
    r, g, b = arr[..., 0], arr[..., 1], arr[..., 2]
    m = np.minimum(r, b) - g
    alpha = np.clip((100 - m) / 70.0, 0.0, 1.0)
    alpha[m <= 30] = 1.0
    alpha[m > 100] = 0.0
    # remove the magenta tint from the partially transparent fringe
    fringe = (m > 30) & (m <= 100)
    out = arr.copy()
    out[..., 0] = np.where(fringe, np.maximum(0, r - m), r)
    out[..., 2] = np.where(fringe, np.maximum(0, b - m), b)
    rgba = np.dstack([out, alpha * 255.0]).astype(np.float32)
    return rgba


def split_frames(rgba: np.ndarray, cols: int, rows: int, name: str) -> list[np.ndarray]:
    height, width = rgba.shape[:2]
    cell_w, cell_h = width / cols, height / rows
    mask = rgba[..., 3] > 20
    labels, count = ndimage.label(mask, structure=np.ones((3, 3)))
    owner: dict[int, int] = {}
    sizes = ndimage.sum(mask, labels, range(1, count + 1))
    centers = ndimage.center_of_mass(mask, labels, range(1, count + 1))
    for index in range(count):
        if sizes[index] < MIN_COMPONENT_PX:
            continue
        cy, cx = centers[index]
        owner[index + 1] = int(min(cy // cell_h, rows - 1)) * cols + int(min(cx // cell_w, cols - 1))
    frames = []
    for cell in range(cols * rows):
        keep = [label for label, c in owner.items() if c == cell]
        if not keep:
            raise ValueError(f"{name}: cell {cell} has no art")
        sel = np.isin(labels, keep)
        ys, xs = np.where(sel)
        crop = rgba[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1].copy()
        crop[..., 3] = np.where(sel[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1], crop[..., 3], 0)
        frames.append(crop)
    return frames


def standing_height(frame: np.ndarray) -> float:
    return float(frame.shape[0])


def sole_bottom(frame: np.ndarray) -> int:
    """Lowest row holding a solid run of art (ignores stray fringe pixels)."""
    solid = (frame[..., 3] > 128).sum(axis=1)
    rows = np.where(solid >= 6)[0]
    return int(rows.max()) if len(rows) else frame.shape[0] - 1


def feet_center_x(frame: np.ndarray, bottom: int) -> float:
    band = max(6, int(frame.shape[0] * 0.12))
    sub = frame[max(0, bottom - band) : bottom + 1, :, 3] > 128
    xs = np.where(sub.any(axis=0))[0]
    weights = sub.sum(axis=0).astype(np.float64)
    return float((np.arange(len(weights)) * weights).sum() / max(weights.sum(), 1.0)) if len(xs) else frame.shape[1] / 2


def to_cell(frame: np.ndarray, scale: float, label: str) -> Image.Image:
    premult = frame.copy()
    premult[..., :3] *= premult[..., 3:4] / 255.0
    img = Image.fromarray(premult.astype(np.uint8), "RGBA")
    w, h = max(1, round(img.width * scale)), max(1, round(img.height * scale))
    img = img.resize((w, h), Image.LANCZOS)
    arr = np.asarray(img).astype(np.float32)
    a = arr[..., 3:4]
    arr[..., :3] = np.where(a > 0, np.minimum(arr[..., :3] * 255.0 / np.maximum(a, 1.0), 255.0), 0)
    arr = arr.astype(np.uint8)
    bottom = sole_bottom(arr.astype(np.float32))
    cx = feet_center_x(arr.astype(np.float32), bottom)
    left = round(OUT_CELL / 2 - cx)
    top = FEET_ROW - bottom
    cell = Image.new("RGBA", (OUT_CELL, OUT_CELL), (0, 0, 0, 0))
    if left < 0 or top < 0 or left + w > OUT_CELL:
        # nudge to keep inside the cell rather than crop
        left = min(max(left, 0), OUT_CELL - w)
        top = max(top, 0)
        print(f"  note: {label} nudged to fit the cell ({w}x{h})")
    cell.alpha_composite(Image.fromarray(arr, "RGBA"), (left, top))
    return cell


ARROW_RAW = "artemis_arrow_raw.png"
ARROW_GAME_LENGTH = 31.0  # px on screen, tip at +14 / tail at -17 of the projectile origin


def build_arrows() -> None:
    """Key the two arrows (normal, moon) of the raw prop sheet and write them
    at SPRITE_SCALE so the Sprite2D uses the same scale as Artemis."""
    raw = key_magenta(Image.open(RAW_DIR / ARROW_RAW))
    height, width = raw.shape[:2]
    names = {0: "artemis_arrow.png", 1: "artemis_arrow_moon.png"}
    target_w = round(ARROW_GAME_LENGTH / SPRITE_SCALE)
    for col, file_name in names.items():
        sub = raw[: height // 2, col * width // 2 : (col + 1) * width // 2]
        ys, xs = np.where(sub[..., 3] > 20)
        crop = sub[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1].copy()
        scale = target_w / crop.shape[1]
        premult = crop.copy()
        premult[..., :3] *= premult[..., 3:4] / 255.0
        img = Image.fromarray(premult.astype(np.uint8), "RGBA")
        img = img.resize((target_w, max(1, round(crop.shape[0] * scale))), Image.LANCZOS)
        arr = np.asarray(img).astype(np.float32)
        a = arr[..., 3:4]
        arr[..., :3] = np.where(a > 0, np.minimum(arr[..., :3] * 255.0 / np.maximum(a, 1.0), 255.0), 0)
        out = Image.fromarray(arr.astype(np.uint8), "RGBA")
        # even height keeps the shaft on the projectile's axis
        if out.height % 2:
            padded = Image.new("RGBA", (out.width, out.height + 1), (0, 0, 0, 0))
            padded.alpha_composite(out, (0, 0))
            out = padded
        out.save(OUT_DIR / file_name, optimize=True)
        print(f"  {file_name}: {out.size}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--preview", type=Path, default=None)
    args = parser.parse_args()
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    prepared: dict[str, list[np.ndarray]] = {}
    for name, spec in SHEETS.items():
        cols, rows = spec["grid"]
        rgba = key_magenta(Image.open(RAW_DIR / spec["raw"]))
        prepared[name] = split_frames(rgba, cols, rows, name)

    # One scale for the whole set, from the locomotion idle frame.
    ref = prepared["locomotion"][SHEETS["locomotion"]["ref"]]
    base_scale = STAND_HEIGHT / standing_height(ref)
    print(f"base scale {base_scale:.4f} (idle ref height {standing_height(ref):.0f})")
    scales = {}
    for name, spec in SHEETS.items():
        h = standing_height(prepared[name][spec["ref"]])
        scales[name] = base_scale * spec.get("scale_mult", 1.0)
        print(f"  {name}: ref frame {spec['ref']} height {h:.0f} -> {h * base_scale:.0f} px")

    manifest: dict = {
        "cell": OUT_CELL,
        "feet_row": FEET_ROW,
        "sprite_scale": round(SPRITE_SCALE, 4),
        "sheets": {},
    }
    for name, spec in SHEETS.items():
        frames = prepared[name]
        used = sorted({i for clip in spec["clips"].values() for i in clip})
        remap = {src: dst for dst, src in enumerate(used)}
        cells = [to_cell(frames[src], scales[name], f"{name}[{src}]") for src in used]
        rows = (len(cells) + COLUMNS - 1) // COLUMNS
        sheet = Image.new("RGBA", (COLUMNS * OUT_CELL, rows * OUT_CELL), (0, 0, 0, 0))
        for index, cell in enumerate(cells):
            sheet.alpha_composite(cell, ((index % COLUMNS) * OUT_CELL, (index // COLUMNS) * OUT_CELL))
        file_name = f"artemis_{name}_sheet.png"
        sheet.save(OUT_DIR / file_name, optimize=True)
        manifest["sheets"][file_name] = {
            "grid": {"columns": COLUMNS, "rows": rows, "cell_width": OUT_CELL, "cell_height": OUT_CELL},
            "clips": {clip: [remap[i] for i in idx] for clip, idx in spec["clips"].items()},
            "events": spec.get("events", {}),
        }
        if args.preview:
            args.preview.mkdir(parents=True, exist_ok=True)
            bg = Image.new("RGBA", sheet.size, (24, 32, 56, 255))
            bg.alpha_composite(sheet)
            bg.save(args.preview / file_name)
    build_arrows()
    (OUT_DIR / "animation_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("wrote", OUT_DIR)


if __name__ == "__main__":
    main()

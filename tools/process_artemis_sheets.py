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

import boss_sheet_pipeline as pipeline
from boss_sheet_pipeline import (
    MIN_COMPONENT_PX,
    body_mask_bottom,
    feet_center_x,
    key_magenta,
    place_fixed,
    scale_rgba,
    sole_bottom,
    split_cells,
    split_frames,
    standing_height,
)

ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = ROOT / "tools" / "art_sources" / "artemis" / "raw"
OUT_DIR = ROOT / "assets" / "enemies" / "artemis"

OUT_CELL = 256
FEET_ROW = 224
COLUMNS = 4
LUZ_SPRITE_SCALE = pipeline.LUZ_SPRITE_SCALE
SPRITE_SCALE = LUZ_SPRITE_SCALE * 512.0 / OUT_CELL
BODY_HEIGHT = 56.0
STAND_HEIGHT = BODY_HEIGHT / SPRITE_SCALE  # output px from hair top to sole

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
    # Batch 2. `body_feet` aligns the soles on the largest component only, so the
    # sparkles and shards drawn around her never move the feet row.
    "feint": {
        "raw": "artemis_feint_raw.png",
        "grid": (4, 3),
        "ref": 11,
        "body_feet": True,
        "clips": {
            "feint_dash": [0, 1, 2, 3, 4, 5],
            "feint_stop": [6, 7],
            "feint_retreat": [8, 9, 10, 11],
        },
    },
    # Batch 3.
    "walkback": {
        "raw": "artemis_walkback_raw.png",
        "grid": (4, 2),
        "ref": 0,
        "scale_mult": 0.86,
        "clips": {"walk_back": list(range(0, 8))},
    },
    "intro": {
        "raw": "artemis_intro_raw.png",
        "grid": (4, 2),
        "ref": 7,
        "scale_mult": 0.79,
        "body_feet": True,
        "clips": {"intro": list(range(0, 8))},
    },
    "stagcast": {
        "raw": "artemis_stagcast_raw.png",
        "grid": (4, 4),
        "ref": 14,
        "scale_mult": 1.13,
        "body_feet": True,
        "clips": {
            "stag_cast": list(range(0, 8)),
            "stag_summon": [8, 9],
            "stag_recover": list(range(10, 16)),
        },
        "events": {"stag_summon": 0},
    },
    "trans": {
        "raw": "artemis_trans_raw.png",
        "grid": (4, 4),
        "ref": 15,
        "scale_mult": 1.18,
        "body_feet": True,
        "clips": {
            "phase_transition": list(range(0, 12)),
            "fan_recover": [12, 13, 14, 15],
        },
        "events": {"phase_transition": 6},
    },
}


def to_cell(frame: np.ndarray, scale: float, label: str, body_feet: bool = False, out_cell: int = OUT_CELL, feet_row: int = FEET_ROW) -> Image.Image:
    # clamp_cell keeps the historical 256 px nudge for the 384 px stag sheet (byte-identical output).
    return pipeline.to_cell(frame, scale, label, out_cell, feet_row, body_feet, clamp_cell=OUT_CELL)



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


def stag_body_anchor(arr: np.ndarray) -> tuple[float, float]:
    bottom, cx = body_mask_bottom(arr.astype(np.float32))
    return cx, float(bottom)


# Spectral stag: its own sheet and sprite scale (the sprite node uses STAG_SPRITE_SCALE).
STAG_RAW = "artemis_stag_raw.png"
STAG_CELL = 384
STAG_FEET_ROW = 340
STAG_SPRITE_SCALE = 0.245  # sprite node scale in artemis.tscn (commit 0aa2d61); the sheet is NOT rescaled by it
STAG_RENDER_SCALE = 0.2  # sizing basis of the sheet pixels (STAG_BODY_WIDTH is relative to this)
STAG_VANISH_RAW = "artemis_stagvanish_raw.png"
STAG_VANISH_GRID = (4, 2)
# The vanish sheet was drawn about 25% larger than stag_run; this matches the gallop widths.
STAG_VANISH_SCALE_MULT = 0.8
STAG_BODY_WIDTH = 46.0  # on-screen px of the compact gallop pose; stretched poses reach about 80 (hitbox 60 wide)
STAG_GRID = (4, 4)
STAG_CLIPS = {
    "stag_appear": [0, 1, 2],
    "stag_run": list(range(3, 11)),
}
STAG_REF = 6


def build_stag() -> dict:
    cols, rows = STAG_GRID
    needed = {i for clip in STAG_CLIPS.values() for i in clip}
    frames = split_frames(key_magenta(Image.open(RAW_DIR / STAG_RAW)), cols, rows, "stag", needed)
    ref = frames[STAG_REF]
    scale = (STAG_BODY_WIDTH / STAG_RENDER_SCALE) / ref.shape[1]
    used = sorted(needed)
    remap = {src: dst for dst, src in enumerate(used)}
    cells = [to_cell(frames[src], scale, f"stag[{src}]", True, STAG_CELL, STAG_FEET_ROW) for src in used]
    rows_out = (len(cells) + COLUMNS - 1) // COLUMNS
    clips = {clip: [remap[i] for i in idx] for clip, idx in STAG_CLIPS.items()}
    if (RAW_DIR / STAG_VANISH_RAW).exists():
        # Same scale and feet anchor as stag_run: frame 0 (intact gallop) lands where
        # a run frame would, the rest keep their position relative to it.
        vcols, vrows = STAG_VANISH_GRID
        full = split_cells(key_magenta(Image.open(RAW_DIR / STAG_VANISH_RAW)), vcols, vrows, "stag_vanish", 12)
        placed = place_fixed(full, scale * STAG_VANISH_SCALE_MULT, STAG_CELL, stag_body_anchor, (STAG_CELL / 2, STAG_FEET_ROW), "stag_vanish")
        clips["stag_vanish"] = list(range(len(cells), len(cells) + len(placed)))
        cells.extend(placed)
    rows_out = (len(cells) + COLUMNS - 1) // COLUMNS
    sheet = Image.new("RGBA", (COLUMNS * STAG_CELL, rows_out * STAG_CELL), (0, 0, 0, 0))
    for index, cell in enumerate(cells):
        sheet.alpha_composite(cell, ((index % COLUMNS) * STAG_CELL, (index // COLUMNS) * STAG_CELL))
    sheet.save(OUT_DIR / "spectral_stag_sheet.png", optimize=True)
    return {
        "sheet": "spectral_stag_sheet.png",
        "sprite_scale": STAG_SPRITE_SCALE,
        "feet_row": STAG_FEET_ROW,
        "grid": {"columns": COLUMNS, "rows": rows_out, "cell_width": STAG_CELL, "cell_height": STAG_CELL},
        "clips": clips,
    }


# Combat VFX (dagger slash arc, moon dive shaft and shockwave): one sheet, one sprite
# scale. Each group is sized on screen from its reference frame ("w" = bbox width,
# "h" = bbox height, in game px) and anchored on the cell bottom ("floor") or centre.
VFX_RAW = "artemis_vfx_raw.png"
VFX_CELL = 512
VFX_FLOOR_ROW = 496
VFX_SPRITE_SCALE = 0.25
VFX_GRID = (4, 3)
VFX_GROUPS = {
    "slash": {"cells": [0, 1, 2], "ref": 1, "axis": "w", "size": 56.0, "anchor": "center"},
    "dive_shaft": {"cells": [4, 5], "ref": 5, "axis": "h", "size": 96.0, "anchor": "floor"},
    "dive_shockwave": {"cells": [8, 9, 10], "ref": 9, "axis": "w", "size": 120.0, "anchor": "floor"},
}


def vfx_cell(frame: np.ndarray, scale: float, anchor: str) -> Image.Image:
    premult = frame.copy()
    premult[..., :3] *= premult[..., 3:4] / 255.0
    img = Image.fromarray(premult.astype(np.uint8), "RGBA")
    img = img.resize((max(1, round(img.width * scale)), max(1, round(img.height * scale))), Image.LANCZOS)
    arr = np.asarray(img).astype(np.float32)
    a = arr[..., 3:4]
    arr[..., :3] = np.where(a > 0, np.minimum(arr[..., :3] * 255.0 / np.maximum(a, 1.0), 255.0), 0)
    out = Image.fromarray(arr.astype(np.uint8), "RGBA")
    cell = Image.new("RGBA", (VFX_CELL, VFX_CELL), (0, 0, 0, 0))
    left = (VFX_CELL - out.width) // 2
    top = (VFX_CELL - out.height) // 2 if anchor == "center" else VFX_FLOOR_ROW - out.height
    cell.alpha_composite(out, (left, max(top, 0)))
    return cell


def build_vfx() -> dict:
    cols, rows = VFX_GRID
    needed = {i for group in VFX_GROUPS.values() for i in group["cells"]}
    frames = split_frames(key_magenta(Image.open(RAW_DIR / VFX_RAW)), cols, rows, "vfx", needed)
    cells: list[Image.Image] = []
    clips: dict[str, list[int]] = {}
    for name, group in VFX_GROUPS.items():
        ref = frames[group["ref"]]
        measure = ref.shape[1] if group["axis"] == "w" else ref.shape[0]
        scale = (group["size"] / VFX_SPRITE_SCALE) / measure
        clips[name] = []
        for src in group["cells"]:
            clips[name].append(len(cells))
            cells.append(vfx_cell(frames[src], scale, group["anchor"]))
    rows_out = (len(cells) + COLUMNS - 1) // COLUMNS
    sheet = Image.new("RGBA", (COLUMNS * VFX_CELL, rows_out * VFX_CELL), (0, 0, 0, 0))
    for index, cell in enumerate(cells):
        sheet.alpha_composite(cell, ((index % COLUMNS) * VFX_CELL, (index // COLUMNS) * VFX_CELL))
    sheet.save(OUT_DIR / "artemis_vfx_sheet.png", optimize=True)
    return {
        "sheet": "artemis_vfx_sheet.png",
        "sprite_scale": VFX_SPRITE_SCALE,
        "floor_row": VFX_FLOOR_ROW,
        "grid": {"columns": COLUMNS, "rows": rows_out, "cell_width": VFX_CELL, "cell_height": VFX_CELL},
        "clips": clips,
    }


# Arrow impact bursts: amber (normal arrow) and silver (moon arrow). The arrow
# flew left to right; the burst anchor is the impact point, so code only has to put
# the sprite on the arrow tip and rotate it by the arrow direction.
IMPACT_RAW = "artemis_impact_raw.png"
IMPACT_GRID = (4, 2)
IMPACT_CELL = 256
IMPACT_SPRITE_SCALE = 0.125
IMPACT_SIZE = 28.0  # on-screen px of the widest burst frame
IMPACT_ANCHOR = (216.0, 128.0)
IMPACT_CLIPS = {"arrow_impact": [0, 1, 2, 3], "arrow_impact_moon": [4, 5, 6, 7]}
IMPACT_WIDEST = {"arrow_impact": 2, "arrow_impact_moon": 6}


def impact_tip_anchor(arr: np.ndarray) -> tuple[float, float]:
    ys, xs = np.where(arr[..., 3] > 20)
    return float(xs.max()), float((ys.min() + ys.max()) / 2.0)


def build_impact() -> dict:
    cols, rows = IMPACT_GRID
    full = split_cells(key_magenta(Image.open(RAW_DIR / IMPACT_RAW)), cols, rows, "impact", 30)
    cells: list[Image.Image] = []
    clips: dict[str, list[int]] = {}
    for name, idx in IMPACT_CLIPS.items():
        widest = full[IMPACT_WIDEST[name]]
        xs = np.where((widest[..., 3] > 20).any(axis=0))[0]
        scale = (IMPACT_SIZE / IMPACT_SPRITE_SCALE) / float(xs.max() - xs.min() + 1)
        clips[name] = list(range(len(cells), len(cells) + len(idx)))
        cells.extend(place_fixed([full[i] for i in idx], scale, IMPACT_CELL, impact_tip_anchor, IMPACT_ANCHOR, name, 1))
    rows_out = (len(cells) + COLUMNS - 1) // COLUMNS
    sheet = Image.new("RGBA", (COLUMNS * IMPACT_CELL, rows_out * IMPACT_CELL), (0, 0, 0, 0))
    for index, cell in enumerate(cells):
        sheet.alpha_composite(cell, ((index % COLUMNS) * IMPACT_CELL, (index // COLUMNS) * IMPACT_CELL))
    sheet.save(OUT_DIR / "artemis_impact_sheet.png", optimize=True)
    return {
        "sheet": "artemis_impact_sheet.png",
        "sprite_scale": IMPACT_SPRITE_SCALE,
        "anchor": [IMPACT_ANCHOR[0], IMPACT_ANCHOR[1]],
        "grid": {"columns": COLUMNS, "rows": rows_out, "cell_width": IMPACT_CELL, "cell_height": IMPACT_CELL},
        "clips": clips,
    }


# Telegraph glyphs: white/grey art tinted in code. Each glyph is cropped tight and
# stored in its own atlas cell; the manifest lists the pixel region of each one.
GLYPHS_RAW = "artemis_glyphs_raw.png"
GLYPHS_GRID = (4, 2)
GLYPH_CELL = 256
GLYPH_COLUMN_EDGES = (490, 960, 1260)  # raw x (1536 wide) between rain|dive, dive|stag, stag|dot
GLYPH_SCALE = 0.5
GLYPH_NAMES = ["rain", "dive", "stag", "dot", "rain_hot", "dive_hot", "stag_hot", "dot_hot"]


def split_glyphs(rgba: np.ndarray) -> list[np.ndarray]:
    """The glyphs are not on the regular grid (the wall glyph and the dive ticks cross
    the cell lines), so components are assigned by fixed column bands instead."""
    height = rgba.shape[0]
    labels, count = ndimage.label(rgba[..., 3] > 20, structure=np.ones((3, 3)))
    centers = ndimage.center_of_mass(np.ones_like(labels), labels, range(1, count + 1))
    sizes = ndimage.sum(np.ones_like(labels), labels, range(1, count + 1))
    owner: dict[int, int] = {}
    for index in range(count):
        if sizes[index] < MIN_COMPONENT_PX:
            continue
        cy, cx = centers[index]
        column = sum(cx >= edge for edge in GLYPH_COLUMN_EDGES)
        owner[index + 1] = (0 if cy < height / 2 else 4) + column
    frames = []
    for cell in range(8):
        sel = np.isin(labels, [label for label, c in owner.items() if c == cell])
        ys, xs = np.where(sel)
        crop = rgba[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1].copy()
        crop[..., 3] = np.where(sel[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1], crop[..., 3], 0)
        frames.append(crop)
    return frames


def build_glyphs() -> dict:
    cols, rows = GLYPHS_GRID
    frames = split_glyphs(key_magenta(Image.open(RAW_DIR / GLYPHS_RAW)))
    sheet = Image.new("RGBA", (cols * GLYPH_CELL, rows * GLYPH_CELL), (0, 0, 0, 0))
    regions: dict[str, list[int]] = {}
    for index, name in enumerate(GLYPH_NAMES):
        arr = scale_rgba(frames[index], GLYPH_SCALE)
        h, w = arr.shape[:2]
        if w > GLYPH_CELL or h > GLYPH_CELL:
            raise ValueError(f"glyph {name} is {w}x{h}, larger than its cell")
        x, y = (index % cols) * GLYPH_CELL, (index // cols) * GLYPH_CELL
        sheet.alpha_composite(Image.fromarray(arr, "RGBA"), (x, y))
        regions[name] = [x, y, w, h]
    sheet.save(OUT_DIR / "artemis_glyphs_sheet.png", optimize=True)
    return {"sheet": "artemis_glyphs_sheet.png", "regions": regions}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--preview", type=Path, default=None)
    args = parser.parse_args()
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    prepared: dict[str, list[np.ndarray]] = {}
    for name, spec in SHEETS.items():
        cols, rows = spec["grid"]
        rgba = key_magenta(Image.open(RAW_DIR / spec["raw"]))
        needed = {i for clip in spec["clips"].values() for i in clip}
        prepared[name] = split_frames(rgba, cols, rows, name, needed)

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
        used, clips = pipeline.compact_clips(spec["clips"])
        cells = [to_cell(frames[src], scales[name], f"{name}[{src}]", spec.get("body_feet", False)) for src in used]
        sheet = pipeline.assemble_sheet(cells, OUT_CELL)
        file_name = f"artemis_{name}_sheet.png"
        sheet.save(OUT_DIR / file_name, optimize=True)
        manifest["sheets"][file_name] = pipeline.manifest_entry(sheet, OUT_CELL, clips, spec.get("events", {}))
        if args.preview:
            args.preview.mkdir(parents=True, exist_ok=True)
            bg = Image.new("RGBA", sheet.size, (24, 32, 56, 255))
            bg.alpha_composite(sheet)
            bg.save(args.preview / file_name)
    build_arrows()
    if (RAW_DIR / STAG_RAW).exists():
        manifest["stag"] = build_stag()
    if (RAW_DIR / VFX_RAW).exists():
        manifest["vfx"] = build_vfx()
    if (RAW_DIR / IMPACT_RAW).exists():
        manifest["impact"] = build_impact()
    if (RAW_DIR / GLYPHS_RAW).exists():
        manifest["glyphs"] = build_glyphs()
    (OUT_DIR / "animation_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("wrote", OUT_DIR)


if __name__ == "__main__":
    main()

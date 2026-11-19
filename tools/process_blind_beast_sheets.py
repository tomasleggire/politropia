#!/usr/bin/env python3
"""Build El Topo's sprite sheets from the raw Codex sheets.

Raw sheets live in tools/art_sources/blind_beast/raw/blind_beast_<sheet>_raw.png
(magenta background, regular grids: 4 x 2 cells, `claw` is 3 x 2; the contract is
docs/bosses/BLIND_BEAST_ANIMATIONS.md). Sheets arrive in batches: a missing raw sheet
is skipped with a message (exit 0) and an already processed sheet stays in the manifest.

Scale. The sprite node uses Artemis's pixel density (SPRITE_SCALE 0.2896 per processed
px). The standing figure of the `exposed_idle` frames (sole to the top of the head) is
scaled to STAND_HEIGHT = 70 / 0.2896 processed px: that sets the scale of the `exposed`
sheet. The thin cane (and a hair wisp) can stick out above the head, so the top of the
figure is the first row whose solid pixels are at least CANE_WIDTH_FRACTION of the
widest row (`boss_sheet_pipeline.body_height`), not the very first drawn row. Codex
draws every sheet at a slightly different size, so each other sheet gets its own
scale: the median size of the pink star nose (`boss_sheet_pipeline.color_block_size`;
the nose exists in every pose that shows the head) is matched to the `exposed` median.
`height_cells` (burrow, where the nose pose varies too much) measures the standing height of those cells instead. `size_cells` restricts the measured cells (the first `intro` frames show the old man,
`dig_in` and `defeat` may hide the head); cells where the nose is not found are ignored,
and a sheet with no nose in any measured cell stops with an error naming it. `scale_mult`
tunes a sheet by hand.

`props` and `fx` hold no figure: every cell keeps its place in the raw cell, each clip is
cropped with ONE box (so a looping mound keeps its motion) and centred in a 256 px cell
at one fixed factor (EFFECT_SCALE); the game rescales each effect to its hazard from the
per-clip `content` box the manifest records.

Usage: python tools/process_blind_beast_sheets.py [--preview DIR]
Needs Pillow, numpy and scipy (see the contract for the exact command).
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image

import boss_sheet_pipeline as pipeline

ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = ROOT / "tools" / "art_sources" / "blind_beast" / "raw"
OUT_DIR = ROOT / "assets" / "enemies" / "blind_beast"

OUT_CELL = 448
FEET_ROW = 416
SPRITE_SCALE = pipeline.sprite_scale_for(256)  # Artemis's on-screen pixel density, 0.2896
BODY_HEIGHT = 70.0  # on-screen px, sole to the top of the head
STAND_HEIGHT = BODY_HEIGHT / SPRITE_SCALE
CANE_WIDTH_FRACTION = 0.15
REFERENCE = "exposed"
# Scale assumed for the first sheet present while the reference is missing.
FALLBACK_BASE_SCALE = 0.8
# The pink star nose: its main tone and its shadow tone (RGB), and how far a pixel may be.
NOSE_TARGETS = [(224, 122, 143), (168, 72, 94)]
NOSE_TOLERANCE = 55.0
EFFECT_CELL = 256
EFFECT_SCALE = 0.5  # raw 384 x 512 cells fit a 256 px cell at this factor
EFFECT_KEY_HIGH = 60  # magenta excess above which an effect pixel is background (pockets inside the column are pinker)
LEAK_RED_OVER_GREEN = 25
LEAK_MAGENTA_BLUE_OVER_GREEN = 45
EFFECT_MIN_COMPONENT_PX = 40  # raw px; drops stray specks around the effects

# sheet -> raw grid (cols, rows), clips (raw cell indices), events (clip -> frame index
# of the strike inside the clip), `body_feet` (align the soles on the largest component
# only, so flying dirt and dust never move the feet row), `size_cells` (cells measured
# for the nose size), `scale_mult` (manual tuning) and `min_component_px` (drop smaller
# marks after keying).
SHEETS = {
    "exposed": {
        "grid": (4, 2),
        "clips": {"exposed_idle": [0, 1, 2, 3], "dazed": [4, 5, 6, 7]},
    },
    "burrow": {
        "grid": (4, 2),
        "body_feet": True,
        "min_component_px": 200,
        # The nose swings between side-on and front-on in this sheet, so it is a poor size
        # reference here; the standing, cane-in-hand frame 3 is measured by height instead.
        "height_cells": [3],
        "clips": {"emerge": [0, 1, 2, 3], "dig_in": [4, 5, 6, 7]},
    },
    "claw": {
        "grid": (3, 2),
        "body_feet": True,
        "clips": {"claw_windup": [0, 1], "claw_strike": [2, 3], "claw_recover": [4, 5]},
        "events": {"claw_strike": 0},
    },
    "slam": {
        "grid": (4, 2),
        "body_feet": True,
        "min_component_px": 200,
        "clips": {"slam_windup": [0, 1], "slam_strike": [2, 3], "phase_change": [4, 5, 6, 7]},
        "events": {"slam_strike": 0},
    },
    "intro": {
        "grid": (4, 2),
        "body_feet": True,
        # The first frames show the old man, before the nose exists.
        "size_cells": [4, 5, 6, 7],
        "clips": {"intro": list(range(8))},
    },
    "defeat": {
        "grid": (4, 2),
        "body_feet": True,
        # The lying frames hide the head: measure the standing ones.
        "size_cells": [0, 1, 2, 3, 4],
        "clips": {"defeat": list(range(8))},
    },
}

PROPS = {
    "grid": (4, 2),
    "clips": {"mound": [0, 1, 2, 3], "rock": [4], "rock_alt": [5], "crack": [6], "spike": [7]},
}

FX = {
    "grid": (4, 2),
    "clips": {"erupt_column": [0, 1, 2], "pulse_wave": [3, 4], "dust_puff": [5], "rock_impact": [6], "dig_dirt": [7]},
}


def raw_path(sheet: str) -> Path:
    return RAW_DIR / f"blind_beast_{sheet}_raw.png"


def sheet_file(sheet: str) -> str:
    return f"blind_beast_{sheet}_sheet.png"


def idle_stand_height(frames: list[np.ndarray | None], idle: list[int]) -> float:
    """Median standing height (raw px, cane excluded) of the idle frames."""
    return float(np.median([pipeline.body_height(frames[i], CANE_WIDTH_FRACTION) for i in idle]))


def measured_cells(spec: dict) -> list[int]:
    return spec.get("size_cells") or sorted({i for clip in spec["clips"].values() for i in clip})


def median_nose(frames: list[np.ndarray | None], spec: dict) -> tuple[float, int]:
    """Median nose size (raw px) over the measured cells that show it, and how many did."""
    sizes = [pipeline.color_block_size(frames[i], NOSE_TARGETS, NOSE_TOLERANCE) for i in measured_cells(spec)]
    found = [s for s in sizes if s > 0.0]
    return (float(np.median(found)) if found else 0.0), len(found)


def load_frames(sheet: str, spec: dict) -> list[np.ndarray | None]:
    cols, rows = spec["grid"]
    needed = {i for clip in spec["clips"].values() for i in clip}
    frames = pipeline.split_frames(pipeline.key_magenta(Image.open(raw_path(sheet))), cols, rows, sheet, needed)
    min_px = spec.get("min_component_px")
    if min_px:
        frames = [None if f is None else pipeline.drop_specks(f, min_px) for f in frames]
    return frames


def sheet_scales(prepared: dict[str, list[np.ndarray | None]]) -> tuple[dict[str, float], dict[str, float]]:
    """Scale of every prepared character sheet and the measured nose size of each.

    The reference is the `exposed` sheet; while it is missing, its expected scale is
    unknown, so the sheets are measured against the first one present and a note says so."""
    sizes = {}
    for name, frames in prepared.items():
        if SHEETS[name].get("height_cells"):
            continue
        size, found = median_nose(frames, SHEETS[name])
        if size <= 0.0:
            raise ValueError(f"{name}: no pink nose found in the measured cells {measured_cells(SHEETS[name])}, so its scale cannot be derived. Check the raw sheet or list other cells in `size_cells`.")
        sizes[name] = size
        print(f"  {name}: nose seen in {found} of {len(measured_cells(SHEETS[name]))} measured cells")
    ref = REFERENCE if REFERENCE in prepared else next((n for n in prepared if n in sizes), None)
    if ref == REFERENCE:
        stand = idle_stand_height(prepared[ref], SHEETS[ref]["clips"]["exposed_idle"])
        if stand <= 0.0:
            raise ValueError(f"{ref}: the idle frames have no height, so the base scale cannot be derived")
        base = STAND_HEIGHT / stand
        print(f"exposed_idle stands {stand:.0f} raw px (cane excluded) -> exposed scale {base:.4f}, {STAND_HEIGHT:.0f} px in the cell")
    else:
        base = FALLBACK_BASE_SCALE
        print(f"note: no exposed sheet yet, scale {base} assumed for {ref}; rerun when exposed arrives")
    scales = {}
    for name in prepared:
        mult = SHEETS[name].get("scale_mult", 1.0)
        cells = SHEETS[name].get("height_cells")
        if cells:
            height = float(np.median([pipeline.body_height(prepared[name][i], CANE_WIDTH_FRACTION) for i in cells]))
            scales[name] = STAND_HEIGHT / height * mult
            sizes[name] = height
            print(f"  {name}: standing frames {cells} are {height:.0f} raw px -> scale {scales[name]:.4f}")
            continue
        scales[name] = base * (sizes[ref] / sizes[name]) * mult
        print(f"  {name}: nose {sizes[name]:.0f} raw px -> scale {scales[name]:.4f}")
    return scales, sizes


def build_sheet(sheet: str, spec: dict, frames: list[np.ndarray | None], scale: float, preview: Path | None, label: str) -> dict:
    used, clips = pipeline.compact_clips(spec["clips"])
    cells = [pipeline.to_cell(frames[src], scale, f"{sheet}[{src}]", OUT_CELL, FEET_ROW, spec.get("body_feet", False)) for src in used]
    image = pipeline.assemble_sheet(cells, OUT_CELL)
    image.save(OUT_DIR / sheet_file(sheet), optimize=True)
    write_preview(image, sheet, preview, OUT_CELL, label)
    return pipeline.manifest_entry(image, OUT_CELL, clips, spec.get("events", {}))


def clear_pink_leaks(rgba: np.ndarray) -> np.ndarray:
    """Remove the magenta that bled into the effect sheets (the eruption column, the rock
    impact). The art of these sheets is brown, beige and grey, so a bright pixel whose blue
    exceeds its green (beige has green above blue) is bled background: a strongly magenta
    one is made transparent, a pale pink one is the lit side of a dust puff and is turned
    beige by capping its blue under its green. Bright warm pixels are the only candidates."""
    r, g, b = rgba[..., 0], rgba[..., 1], rgba[..., 2]
    warm = (r > 160) & (r - g >= LEAK_RED_OVER_GREEN)
    magenta = warm & (b - g >= LEAK_MAGENTA_BLUE_OVER_GREEN)
    out = rgba.copy()
    out[..., 2] = np.where(warm & ~magenta, np.minimum(b, np.maximum(0.0, g - 24.0)), b)
    out[..., 3] = np.where(magenta, 0.0, out[..., 3])
    return out


def build_effects(sheet: str, spec: dict, preview: Path | None) -> dict:
    """A props or fx sheet: one clip per effect, every frame cropped with the clip's one
    box (a looping mound keeps its motion, a single frame sits on the cell centre)."""
    cols, rows = spec["grid"]
    cells = pipeline.split_cells(clear_pink_leaks(pipeline.key_magenta(Image.open(raw_path(sheet)), high=EFFECT_KEY_HIGH)), cols, rows, sheet, EFFECT_MIN_COMPONENT_PX)
    placed: dict[int, Image.Image] = {}
    for clip, indices in spec["clips"].items():
        left, top, right, bottom = pipeline.require_box([cells[i] for i in indices], f"{sheet} clip '{clip}' (cells {indices})")
        for i in indices:
            frame = cells[i][top:bottom, left:right]
            placed[i] = pipeline.centered_cell(frame, EFFECT_SCALE, EFFECT_CELL, f"{sheet}[{i}]")
    used, clips = pipeline.compact_clips(spec["clips"])
    image = pipeline.assemble_sheet([placed[i] for i in used], EFFECT_CELL)
    image.save(OUT_DIR / sheet_file(sheet), optimize=True)
    write_preview(image, sheet, preview, EFFECT_CELL, f"{sheet} scale {EFFECT_SCALE}")
    entry = pipeline.manifest_entry(image, EFFECT_CELL, clips, {})
    return {
        "sheet": sheet_file(sheet),
        "sprite_scale": round(SPRITE_SCALE, 4),
        "grid": entry["grid"],
        "clips": entry["clips"],
        "content": pipeline.clip_contents(image, EFFECT_CELL, entry["clips"]),
    }


def write_preview(image: Image.Image, sheet: str, preview: Path | None, cell: int, label: str) -> None:
    if preview is None:
        return
    preview.mkdir(parents=True, exist_ok=True)
    references = {"Luz": pipeline.LUZ_HEIGHT, "Artemis": pipeline.ARTEMIS_HEIGHT, "Topo": BODY_HEIGHT}
    pipeline.write_preview(image, preview / sheet_file(sheet), cell, FEET_ROW, SPRITE_SCALE, references, label)


def load_manifest() -> dict:
    path = OUT_DIR / "animation_manifest.json"
    return json.loads(path.read_text()) if path.exists() else {}


def main() -> None:
    global RAW_DIR, OUT_DIR
    parser = argparse.ArgumentParser()
    parser.add_argument("--raw-dir", type=Path, default=RAW_DIR, help="folder with the raw sheets")
    parser.add_argument("--out-dir", type=Path, default=OUT_DIR, help="folder for the game sheets and the manifest")
    parser.add_argument("--preview", type=Path, default=None, help="write per-sheet previews (feet row, Luz/Artemis/Topo height lines, measured nose size)")
    args = parser.parse_args()
    RAW_DIR, OUT_DIR = args.raw_dir.resolve(), args.out_dir.resolve()

    present = {name: spec for name, spec in SHEETS.items() if raw_path(name).exists()}
    effects = {name: spec for name, spec in (("props", PROPS), ("fx", FX)) if raw_path(name).exists()}
    for name in [*SHEETS, "props", "fx"]:
        if name not in present and name not in effects:
            print(f"skip {name}: {raw_path(name)} not found")
    if not present and not effects:
        print("nothing to process")
        return

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    manifest = load_manifest()
    manifest.update({"cell": OUT_CELL, "feet_row": FEET_ROW, "sprite_scale": round(SPRITE_SCALE, 4)})
    manifest.setdefault("sheets", {})
    if present:
        prepared = {name: load_frames(name, spec) for name, spec in present.items()}
        scales, sizes = sheet_scales(prepared)
        for name, spec in present.items():
            measure = "standing height" if SHEETS[name].get("height_cells") else "nose"
            label = f"{measure} {sizes[name]:.0f} raw px, scale {scales[name]:.3f}"
            manifest["sheets"][sheet_file(name)] = build_sheet(name, spec, prepared[name], scales[name], args.preview, label)
            print(f"  {name}: done")
    for name, spec in effects.items():
        manifest[name] = build_effects(name, spec, args.preview)
        print(f"  {name}: done")
    pipeline.write_manifest(OUT_DIR / "animation_manifest.json", manifest)
    print("wrote", OUT_DIR)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Build El Profesor's sprite sheets from the raw Codex sheets.

Raw sheets live in tools/art_sources/boombox_teacher/raw/boombox_teacher_<sheet>_raw.png
(magenta background, regular grids: 4 x 2 cells, `thrust` is 3 x 2; the contract is
docs/bosses/BOOMBOX_TEACHER_ANIMATIONS.md). Sheets arrive in batches: a missing raw
sheet is skipped with a message and an already processed sheet stays in the manifest.

Scale. The sprite node uses Artemis's pixel density (SPRITE_SCALE 0.2896 per processed
px). The standing figure (sole to the top of the boombox, antenna excluded) of the loco
idle frames is scaled to STAND_HEIGHT = 92 / 0.2896 processed px: that sets the scale of
the loco sheet. Codex draws every sheet at a slightly different size, so the other
character sheets get their own scale: the median size of the boombox block (see
`boss_sheet_pipeline.block_size`; the boombox exists in every pose, crouched or lying)
of the sheet is matched to the loco median. `size_cells` restricts which cells are
measured, `scale_mult` is a manual multiplier for tuning. The props sheet has no
boombox: the briefcase of its cell 0 is scaled to BRIEFCASE_GAME_WIDTH on screen (the
hazard is 30 px wide) and every prop uses that factor (`PROPS_SCALE_MULT` tunes it).
The `fx` sheet (wave arcs, ground crest, chalk dust, steam loop) uses one fixed factor
(`FX_SCALE`); the game rescales each effect to its hazard from the per-clip `content`
box the manifest records. The `blackboard` raw image is keyed, cropped and saved as one
texture. A sheet whose boombox block measures 0 stops with a clear error.

Usage: python tools/process_boombox_teacher_sheets.py [--preview DIR]
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
RAW_DIR = ROOT / "tools" / "art_sources" / "boombox_teacher" / "raw"
OUT_DIR = ROOT / "assets" / "enemies" / "boombox_teacher"

OUT_CELL = 448
FEET_ROW = 416
PROPS_CELL = 256
SPRITE_SCALE = pipeline.sprite_scale_for(256)  # Artemis's on-screen pixel density, 0.2896
BODY_HEIGHT = 92.0  # on-screen px, sole to the top of the boombox
STAND_HEIGHT = BODY_HEIGHT / SPRITE_SCALE
ANTENNA_WIDTH_FRACTION = 0.30
BRIEFCASE_GAME_WIDTH = 30.0  # on-screen px, the thrown briefcase hazard (briefcase_size.x)
PROPS_SCALE_MULT = 1.0
REFERENCE = "loco"
# Scale assumed for the first sheet present while loco (the reference) is missing.
FALLBACK_BASE_SCALE = 0.8
FX_CELL = 256
FX_SCALE = 0.7  # one factor for the whole fx sheet; the game rescales each effect to its hazard
FX_MIN_COMPONENT_PX = 40  # raw px; drops stray specks around the effects
BLACKBOARD_SCALE = 0.4
BLACKBOARD_FILE = "boombox_teacher_blackboard.png"

# sheet -> raw grid (cols, rows), clips (raw cell indices), events (clip -> frame
# index of the strike inside the clip), `body_feet` (align the soles on the largest
# component only, so floating notes, steam and sparks never move the feet row),
# `size_cells` (cells measured for the boombox size), `scale_mult` (manual tuning) and
# `min_component_px` (drop smaller marks after keying).
SHEETS = {
    "loco": {
        "grid": (4, 2),
        "clips": {"idle": [0, 1, 2, 3], "walk": [4, 5, 6, 7]},
    },
    "thrust": {
        "grid": (3, 2),
        "clips": {
            "thrust_high_windup": [0],
            "thrust_high_strike": [1],
            "thrust_high_recover": [2],
            "thrust_low_windup": [3],
            "thrust_low_strike": [4],
            "thrust_low_recover": [5],
        },
        "events": {"thrust_high_strike": 0, "thrust_low_strike": 0},
    },
    "throw": {
        "grid": (4, 2),
        "clips": {
            "throw_windup": [0, 1],
            "throw_release": [2],
            "throw_wait": [3],
            "throw_catch": [4],
            "kick_windup": [5],
            "kick_strike": [6],
            "kick_recover": [7],
        },
        "events": {"throw_release": 0, "kick_strike": 0},
    },
    "conduct": {
        "grid": (4, 2),
        "body_feet": True,
        "clips": {"conduct": [0, 1, 2, 3], "lecture": [4, 5], "notes": [6, 7]},
    },
    "bass": {
        "grid": (4, 2),
        "body_feet": True,
        "min_component_px": 300,
        "clips": {"bass_lift": [0, 1], "bass_slam": [2, 3], "overheat": [4, 5, 6, 7]},
        "events": {"bass_slam": 0},
    },
    "trans": {
        "grid": (4, 2),
        "body_feet": True,
        "clips": {"phase_change": [0, 1, 2, 3], "intro": [4, 5, 6, 7]},
    },
    "defeat": {
        "grid": (4, 2),
        "body_feet": True,
        # The lying frames hide part of the boombox: measure the standing ones.
        "size_cells": [0, 1, 2, 3, 4],
        "clips": {"defeat": list(range(8))},
    },
}

PROPS = {
    "grid": (4, 2),
    "clips": {"briefcase_spin": [0, 1, 2, 3], "note": [4], "note_pair": [5], "steam": [6], "spark": [7]},
}

# Effects (no figure): one clip per effect. Every frame of a clip is cropped with the
# same box and centred, so a looping clip (steam) keeps its motion and a single frame
# (a wave, the ground crest) sits on the cell centre. `content` in the manifest is that
# box in sheet px: the game scales each effect from it.
FX = {
    "grid": (4, 2),
    "clips": {"wave_low": [0], "wave_high": [1], "bass_shock": [2], "chalk_dust": [3], "steam": [4, 5, 6, 7]},
}


def raw_path(sheet: str) -> Path:
    return RAW_DIR / f"boombox_teacher_{sheet}_raw.png"


def sheet_file(sheet: str) -> str:
    return f"boombox_teacher_{sheet}_sheet.png"


def idle_stand_height(frames: list[np.ndarray | None], idle: list[int]) -> float:
    """Median standing height (raw px, antenna excluded) of the idle frames."""
    return float(np.median([pipeline.body_height(frames[i], ANTENNA_WIDTH_FRACTION) for i in idle]))


def median_block(frames: list[np.ndarray | None], spec: dict) -> float:
    cells = spec.get("size_cells") or sorted({i for clip in spec["clips"].values() for i in clip})
    return float(np.median([pipeline.block_size(frames[i]) for i in cells]))


def load_frames(sheet: str, spec: dict) -> list[np.ndarray | None]:
    cols, rows = spec["grid"]
    needed = {i for clip in spec["clips"].values() for i in clip}
    frames = pipeline.split_frames(pipeline.key_magenta(Image.open(raw_path(sheet))), cols, rows, sheet, needed)
    min_px = spec.get("min_component_px")
    if min_px:
        frames = [None if f is None else pipeline.drop_specks(f, min_px) for f in frames]
    return frames


def sheet_scales(prepared: dict[str, list[np.ndarray | None]]) -> tuple[dict[str, float], dict[str, float]]:
    """Scale of every prepared character sheet and the measured boombox size of each.

    The reference is the loco sheet; while it is missing, its expected scale is unknown,
    so the sheets are measured against the first one present and a note says so."""
    sizes = {name: median_block(frames, SHEETS[name]) for name, frames in prepared.items()}
    for name, size in sizes.items():
        if size <= 0.0:
            raise ValueError(f"{name}: no boombox block found in the measured cells, so its scale cannot be derived. Check the raw sheet or list other cells in `size_cells`.")
    ref = REFERENCE if REFERENCE in prepared else next(iter(prepared))
    if ref == REFERENCE:
        stand = idle_stand_height(prepared[ref], SHEETS[ref]["clips"]["idle"])
        if stand <= 0.0:
            raise ValueError(f"{ref}: the idle frames have no height, so the base scale cannot be derived")
        base = STAND_HEIGHT / stand
        print(f"idle stands {stand:.0f} raw px (antenna excluded) -> loco scale {base:.4f}, {STAND_HEIGHT:.0f} px in the cell")
    else:
        base = FALLBACK_BASE_SCALE
        print(f"note: no loco sheet yet, scale {base} assumed for {ref}; rerun when loco arrives")
    scales = {}
    for name in prepared:
        mult = SHEETS[name].get("scale_mult", 1.0)
        scales[name] = base * (sizes[ref] / sizes[name]) * mult
        print(f"  {name}: boombox {sizes[name]:.0f} raw px -> scale {scales[name]:.4f}")
    return scales, sizes


def build_sheet(sheet: str, spec: dict, frames: list[np.ndarray | None], scale: float, preview: Path | None, label: str) -> dict:
    used, clips = pipeline.compact_clips(spec["clips"])
    cells = [pipeline.to_cell(frames[src], scale, f"{sheet}[{src}]", OUT_CELL, FEET_ROW, spec.get("body_feet", False)) for src in used]
    image = pipeline.assemble_sheet(cells, OUT_CELL)
    image.save(OUT_DIR / sheet_file(sheet), optimize=True)
    write_preview(image, sheet, preview, OUT_CELL, label)
    return pipeline.manifest_entry(image, OUT_CELL, clips, spec.get("events", {}))


def props_scale(frames: list[np.ndarray]) -> float:
    width = frames[0].shape[1]
    return BRIEFCASE_GAME_WIDTH / SPRITE_SCALE / width * PROPS_SCALE_MULT


def clip_contents(image: Image.Image, cell: int, clips: dict[str, list[int]]) -> dict[str, list[int]]:
    """Per clip, the [width, height] in sheet px of the box that holds its art in every frame."""
    sheet = np.asarray(image).astype(np.float32)
    columns = image.width // cell
    contents = {}
    for clip, indices in clips.items():
        frames = []
        for i in indices:
            row, col = divmod(i, columns)
            frames.append(sheet[row * cell : (row + 1) * cell, col * cell : (col + 1) * cell])
        box = pipeline.union_box(frames)
        if box is not None:
            contents[clip] = [box[2] - box[0], box[3] - box[1]]
    return contents


def build_props(preview: Path | None) -> dict:
    cols, rows = PROPS["grid"]
    frames = pipeline.split_frames(pipeline.key_magenta(Image.open(raw_path("props"))), cols, rows, "props")
    scale = props_scale(frames)
    print(f"  props: briefcase {frames[0].shape[1]} raw px -> {BRIEFCASE_GAME_WIDTH:.0f} px on screen, scale {scale:.4f}")
    cells = [pipeline.centered_cell(frame, scale, PROPS_CELL, f"props[{i}]") for i, frame in enumerate(frames)]
    image = pipeline.assemble_sheet(cells, PROPS_CELL)
    image.save(OUT_DIR / sheet_file("props"), optimize=True)
    write_preview(image, "props", preview, PROPS_CELL, f"props scale {scale:.3f}")
    entry = pipeline.manifest_entry(image, PROPS_CELL, PROPS["clips"], {})
    return {
        "sheet": sheet_file("props"),
        "sprite_scale": round(SPRITE_SCALE, 4),
        "grid": entry["grid"],
        "clips": entry["clips"],
        "content": clip_contents(image, PROPS_CELL, entry["clips"]),
    }


def build_fx(preview: Path | None) -> dict:
    cols, rows = FX["grid"]
    cells = pipeline.split_cells(pipeline.key_magenta(Image.open(raw_path("fx"))), cols, rows, "fx", FX_MIN_COMPONENT_PX)
    placed: dict[int, Image.Image] = {}
    for clip, indices in FX["clips"].items():
        left, top, right, bottom = pipeline.union_box([cells[i] for i in indices])
        for i in indices:
            frame = cells[i][top:bottom, left:right]
            placed[i] = pipeline.centered_cell(frame, FX_SCALE, FX_CELL, f"fx[{i}]")
    used, clips = pipeline.compact_clips(FX["clips"])
    image = pipeline.assemble_sheet([placed[i] for i in used], FX_CELL)
    image.save(OUT_DIR / sheet_file("fx"), optimize=True)
    write_preview(image, "fx", preview, FX_CELL, f"fx scale {FX_SCALE}")
    entry = pipeline.manifest_entry(image, FX_CELL, clips, {})
    return {
        "sheet": sheet_file("fx"),
        "grid": entry["grid"],
        "clips": entry["clips"],
        "content": clip_contents(image, FX_CELL, entry["clips"]),
    }


def build_blackboard(preview: Path | None) -> dict:
    """The blank blackboard keyed, cropped to its box and scaled: one texture."""
    frame = pipeline.key_magenta(Image.open(raw_path("blackboard")))
    left, top, right, bottom = pipeline.union_box([frame])
    board = pipeline.scale_rgba(frame[top:bottom, left:right], BLACKBOARD_SCALE)
    image = Image.fromarray(board, "RGBA")
    image.save(OUT_DIR / BLACKBOARD_FILE, optimize=True)
    if preview is not None:
        preview.mkdir(parents=True, exist_ok=True)
        backdrop = Image.new("RGBA", image.size, (24, 32, 56, 255))
        backdrop.alpha_composite(image)
        backdrop.save(preview / BLACKBOARD_FILE)
    print(f"  blackboard: {image.width}x{image.height} px")
    return {"texture": BLACKBOARD_FILE, "size": [image.width, image.height]}


def write_preview(image: Image.Image, sheet: str, preview: Path | None, cell: int, label: str) -> None:
    if preview is None:
        return
    preview.mkdir(parents=True, exist_ok=True)
    references = {"Luz": pipeline.LUZ_HEIGHT, "Artemis": pipeline.ARTEMIS_HEIGHT, "Profesor": BODY_HEIGHT}
    pipeline.write_preview(image, preview / sheet_file(sheet), cell, FEET_ROW, SPRITE_SCALE, references, label)


def load_manifest() -> dict:
    path = OUT_DIR / "animation_manifest.json"
    return json.loads(path.read_text()) if path.exists() else {}


def main() -> None:
    global RAW_DIR, OUT_DIR
    parser = argparse.ArgumentParser()
    parser.add_argument("--raw-dir", type=Path, default=RAW_DIR, help="folder with the raw sheets")
    parser.add_argument("--out-dir", type=Path, default=OUT_DIR, help="folder for the game sheets and the manifest")
    parser.add_argument("--preview", type=Path, default=None, help="write per-sheet previews (feet row, Luz/Artemis/Profesor height lines, measured boombox size)")
    args = parser.parse_args()
    RAW_DIR, OUT_DIR = args.raw_dir.resolve(), args.out_dir.resolve()

    present = {name: spec for name, spec in SHEETS.items() if raw_path(name).exists()}
    for name in SHEETS:
        if name not in present:
            print(f"skip {name}: {raw_path(name)} not found")
    props_present = raw_path("props").exists()
    if not props_present:
        print(f"skip props: {raw_path('props')} not found")
    extras = {name: raw_path(name).exists() for name in ("fx", "blackboard")}
    for name, found in extras.items():
        if not found:
            print(f"skip {name}: {raw_path(name)} not found")
    if not present and not props_present and not any(extras.values()):
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
            label = f"boombox {sizes[name]:.0f} raw px, scale {scales[name]:.3f}"
            manifest["sheets"][sheet_file(name)] = build_sheet(name, spec, prepared[name], scales[name], args.preview, label)
            print(f"  {name}: done")
    if props_present:
        manifest["props"] = build_props(args.preview)
    if extras["fx"]:
        manifest["fx"] = build_fx(args.preview)
        print("  fx: done")
    if extras["blackboard"]:
        manifest["blackboard"] = build_blackboard(args.preview)
    pipeline.write_manifest(OUT_DIR / "animation_manifest.json", manifest)
    print("wrote", OUT_DIR)


if __name__ == "__main__":
    main()

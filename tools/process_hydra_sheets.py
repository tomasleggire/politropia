#!/usr/bin/env python3
"""Build La Hidra's sprite sheets from the raw Codex sheets.

Raw sheets live in tools/art_sources/hydra/raw/hydra_<sheet>_raw.png (magenta background,
1536 x 1024; the contract is docs/bosses/HYDRA_ANIMATIONS.md). Sheets arrive in batches: a
missing raw sheet is skipped with a message (exit 0) and an already processed sheet stays in
the manifest. Nothing is written when no raw sheet exists.

Sheets
  body, defeat   The figure (3 x 2 raw cells of 512 x 512). Scale: the content height of the
                 first cell (`idle[0]` of `body`, cell 0 of `defeat`) becomes BODY_HEIGHT on
                 screen. Every frame goes in a BODY_CELL px cell with the lowest coil on
                 BODY_FEET_ROW and the feet centre on the cell centre.
  head_<kind>    One head (4 x 2 raw cells of 384 x 512). Scale: the content width of the
                 first cell (`idle[0]`) becomes HEAD_WIDTH on screen. Every frame goes in a
                 HEAD_CELL px cell and is aligned on a stable anchor, the upper back of the
                 skull, not on the bounding box: an open jaw changes the box and would make
                 the head jitter. The first idle frame is centred on the cell, so the head
                 sits on its origin in game.
  props          Six clips (stump, venom glob, venom pool, venom splash, two platforms), each
                 cropped with one shared box and centred in a 256 px cell at one factor, as
                 El Topo's props. The game rescales each one from the `content` box. The
                 `neck` cell (a straight horizontal neck piece) becomes a separate seamless
                 horizontal tile, `hydra_neck.png`: the centre of the piece followed by its
                 mirror image, padded with a transparent row on each side. The manifest
                 records its on-screen thickness.

Usage: python tools/process_hydra_sheets.py [--raw-dir DIR] [--out-dir DIR] [--preview DIR]
Needs Pillow, numpy and scipy (see the contract for the exact command).
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

import boss_sheet_pipeline as pipeline

ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = ROOT / "tools" / "art_sources" / "hydra" / "raw"
OUT_DIR = ROOT / "assets" / "enemies" / "hydra"

SPRITE_SCALE = pipeline.sprite_scale_for(256)  # the other bosses' on-screen pixel density, 0.2896
BODY_CELL = 640
BODY_FEET_ROW = 608
BODY_HEIGHT = 152.0  # on-screen px, lowest coil to the top of the body
BODY_STAND = BODY_HEIGHT / SPRITE_SCALE
HEAD_CELL = 256
HEAD_WIDTH = 56.0  # on-screen px, snout to the back of the skull
HEAD_STAND = HEAD_WIDTH / SPRITE_SCALE
HEAD_HEIGHT = 42.0  # on-screen px, only drawn in the preview
# Anchor of a head frame: the left-most solid column within this many rows (processed px)
# below the first wide row; thin crest spikes above it are skipped.
ANCHOR_ROWS = 40
ANCHOR_TOP_FRACTION = 0.15
MIN_COMPONENT_PX = 150  # raw px; drops stray marks the art agent left near a figure
EFFECT_CELL = 256
EFFECT_SCALE = 0.5  # raw 384 x 512 cells fit a 256 px cell at this factor
EFFECT_MIN_COMPONENT_PX = 40
NECK_THICKNESS = 18.0  # on-screen px, outline included (the placeholder neck is 16)
NECK_PAD = 2  # transparent rows above and below the tile, so a repeat never bleeds
NECK_FILE = "hydra_neck.png"
NECK_CELL = 0

BODY_SHEETS = {
    "body": {"grid": (3, 2), "clips": {"idle": [0, 1, 2, 3], "roar": [4, 5]}},
    "defeat": {"grid": (3, 2), "clips": {"defeat": [0, 1, 2, 3, 4, 5]}},
}
HEAD_CLIPS = {"idle": [0, 1, 2], "telegraph": [3], "attack": [4, 5], "roar": [6], "dazed": [7]}
HEAD_SHEETS = {f"head_{kind}": {"grid": (4, 2), "clips": HEAD_CLIPS} for kind in ("biter", "sweeper", "spitter")}
PROPS = {
    "grid": (4, 2),
    "clips": {"stump": [1], "venom_glob": [2], "venom_pool": [3, 4], "venom_splash": [5], "platform": [6], "platform_alt": [7]},
}
REFERENCE_CELL = 0  # the cell whose content size sets the scale of a figure sheet


def raw_path(sheet: str) -> Path:
    return RAW_DIR / f"hydra_{sheet}_raw.png"


def sheet_file(sheet: str) -> str:
    return f"hydra_{sheet}_sheet.png"


def load_frames(sheet: str, grid: tuple[int, int], clips: dict[str, list[int]]) -> list[np.ndarray]:
    """One cropped RGBA frame per raw cell, stray specks removed."""
    cols, rows = grid
    needed = {i for clip in clips.values() for i in clip}
    frames = pipeline.split_frames(pipeline.key_magenta(Image.open(raw_path(sheet))), cols, rows, sheet, needed)
    return [pipeline.drop_specks(f, MIN_COMPONENT_PX) for f in frames if f is not None]


# -- Body ---------------------------------------------------------------------------------------

def build_body(sheet: str, spec: dict, preview: Path | None) -> dict:
    frames = load_frames(sheet, spec["grid"], spec["clips"])
    raw_height = pipeline.standing_height(frames[REFERENCE_CELL])
    scale = BODY_STAND / raw_height
    print(f"  {sheet}: cell {REFERENCE_CELL} is {raw_height:.0f} raw px tall -> scale {scale:.4f}, {BODY_STAND:.0f} px in the cell")
    used, clips = pipeline.compact_clips(spec["clips"])
    cells = [pipeline.to_cell(frames[src], scale, f"{sheet}[{src}]", BODY_CELL, BODY_FEET_ROW, True) for src in used]
    image = pipeline.assemble_sheet(cells, BODY_CELL)
    image.save(OUT_DIR / sheet_file(sheet), optimize=True)
    if preview is not None:
        references = {"Luz": pipeline.LUZ_HEIGHT, "Artemis": pipeline.ARTEMIS_HEIGHT, "Hydra": BODY_HEIGHT}
        preview.mkdir(parents=True, exist_ok=True)
        pipeline.write_preview(image, preview / sheet_file(sheet), BODY_CELL, BODY_FEET_ROW, SPRITE_SCALE, references, f"{sheet} scale {scale:.3f}")
    return pipeline.manifest_entry(image, BODY_CELL, clips, {})


# -- Heads --------------------------------------------------------------------------------------

def head_anchor(frame: np.ndarray) -> tuple[float, float]:
    """The upper back of the skull of a right-facing head: the top of its massive part (thin
    crest spikes skipped) and the left-most solid column in the rows just below it."""
    top = pipeline.solid_top(frame, ANCHOR_TOP_FRACTION)
    band = frame[top : top + ANCHOR_ROWS, :, 3] > 128
    columns = np.where(band.sum(axis=0) >= 2)[0]
    left = int(columns.min()) if len(columns) else 0
    return float(left), float(top)


def place_on_anchor(arr: np.ndarray, anchor: tuple[float, float], target: tuple[float, float], label: str) -> Image.Image:
    """`arr` in a HEAD_CELL px cell with its anchor on `target`; art that leaves the cell is
    cut and reported."""
    left, top = round(target[0] - anchor[0]), round(target[1] - anchor[1])
    canvas = Image.new("RGBA", (HEAD_CELL * 3, HEAD_CELL * 3), (0, 0, 0, 0))
    canvas.alpha_composite(Image.fromarray(arr, "RGBA"), (left + HEAD_CELL, top + HEAD_CELL))
    cell = canvas.crop((HEAD_CELL, HEAD_CELL, 2 * HEAD_CELL, 2 * HEAD_CELL))
    lost = int((arr[..., 3] > 20).sum()) - int((np.asarray(cell)[..., 3] > 20).sum())
    if lost > 30:
        print(f"  note: {label} loses {lost} px outside the cell")
    return cell


def head_cells(frames: list[np.ndarray], used: list[int], scale: float, sheet: str) -> list[Image.Image]:
    """Every frame scaled by `scale` and put on one anchor point. The first idle frame is
    centred on the cell and fixes that point."""
    scaled = {src: pipeline.scale_rgba(frames[src], scale) for src in used}
    anchors = {src: head_anchor(scaled[src].astype(np.float32)) for src in used}
    first = scaled[REFERENCE_CELL]
    ax, ay = anchors[REFERENCE_CELL]
    target = (HEAD_CELL / 2 - first.shape[1] / 2 + ax, HEAD_CELL / 2 - first.shape[0] / 2 + ay)
    return [place_on_anchor(scaled[src], anchors[src], target, f"{sheet}[{src}]") for src in used]


def build_head(sheet: str, spec: dict, preview: Path | None) -> dict:
    frames = load_frames(sheet, spec["grid"], spec["clips"])
    raw_width = float(frames[REFERENCE_CELL].shape[1])
    scale = HEAD_STAND / raw_width
    print(f"  {sheet}: cell {REFERENCE_CELL} is {raw_width:.0f} raw px wide -> scale {scale:.4f}, {HEAD_STAND:.0f} px in the cell")
    used, clips = pipeline.compact_clips(spec["clips"])
    image = pipeline.assemble_sheet(head_cells(frames, used, scale, sheet), HEAD_CELL)
    image.save(OUT_DIR / sheet_file(sheet), optimize=True)
    write_head_preview(image, sheet, preview, f"{sheet} scale {scale:.3f}")
    entry = pipeline.manifest_entry(image, HEAD_CELL, clips, {})
    return {
        "sheet": sheet_file(sheet),
        "sprite_scale": round(SPRITE_SCALE, 4),
        "grid": entry["grid"],
        "clips": entry["clips"],
        "content": pipeline.clip_contents(image, HEAD_CELL, entry["clips"]),
    }


def write_head_preview(image: Image.Image, sheet: str, preview: Path | None, label: str) -> None:
    """Cells on a dark background with the origin cross and the 56 x 42 px box of the placeholder."""
    if preview is None:
        return
    preview.mkdir(parents=True, exist_ok=True)
    bg = Image.new("RGBA", image.size, (24, 32, 56, 255))
    bg.alpha_composite(image)
    draw = ImageDraw.Draw(bg)
    half_w, half_h = HEAD_STAND / 2, HEAD_HEIGHT / SPRITE_SCALE / 2
    for row in range(image.height // HEAD_CELL):
        for col in range(image.width // HEAD_CELL):
            x0, y0 = col * HEAD_CELL, row * HEAD_CELL
            cx, cy = x0 + HEAD_CELL / 2, y0 + HEAD_CELL / 2
            draw.rectangle([x0, y0, x0 + HEAD_CELL - 1, y0 + HEAD_CELL - 1], outline=(70, 80, 110, 255))
            draw.rectangle([cx - half_w, cy - half_h, cx + half_w, cy + half_h], outline=(80, 220, 120, 255))
            draw.line([cx - 8, cy, cx + 8, cy], fill=(255, 255, 255, 255))
            draw.line([cx, cy - 8, cx, cy + 8], fill=(255, 255, 255, 255))
    draw.text((6, image.height - 14), label, fill=(255, 255, 255, 255))
    bg.save(preview / sheet_file(sheet))


# -- Props and neck -----------------------------------------------------------------------------

def neck_tile(piece: np.ndarray) -> np.ndarray:
    """A seamless horizontal tile from a straight neck piece: its centre half followed by the
    mirror image of that half, so the left and right edges are the same column. Cut to the
    drawn rows, scaled to NECK_THICKNESS on screen and padded with a transparent row on each
    side."""
    width = piece.shape[1]
    centre = piece[:, width // 4 : width - width // 4]
    tile = np.concatenate([centre, centre[:, ::-1]], axis=1)
    box = pipeline.alpha_box(tile)
    if box is None:
        raise ValueError("props: the neck cell has no drawn pixels")
    tile = tile[box[1] : box[3]]
    scale = (NECK_THICKNESS / SPRITE_SCALE - 2 * NECK_PAD) / tile.shape[0]
    scaled = pipeline.scale_rgba(tile, scale)
    return np.pad(scaled, ((NECK_PAD, NECK_PAD), (0, 0), (0, 0)))


def write_neck(piece: np.ndarray, preview: Path | None) -> dict:
    tile = neck_tile(piece)
    image = Image.fromarray(tile, "RGBA")
    image.save(OUT_DIR / NECK_FILE, optimize=True)
    if preview is not None:
        preview.mkdir(parents=True, exist_ok=True)
        strip = Image.new("RGBA", (image.width * 6, image.height), (24, 32, 56, 255))
        for i in range(6):
            strip.alpha_composite(image, (i * image.width, 0))
        strip.save(preview / NECK_FILE)
    return {
        "texture": NECK_FILE,
        "thickness": round(image.height * SPRITE_SCALE, 2),
        "tile": [image.width, image.height],
    }


def build_props(spec: dict, preview: Path | None) -> tuple[dict, dict]:
    """The props entry (every clip cropped with one shared box, centred in a 256 px cell) and
    the neck entry."""
    cols, rows = spec["grid"]
    cells = pipeline.split_cells(pipeline.key_magenta(Image.open(raw_path("props"))), cols, rows, "props", EFFECT_MIN_COMPONENT_PX)
    neck_box = pipeline.require_box([cells[NECK_CELL]], f"props neck (cell {NECK_CELL})")
    neck = write_neck(cells[NECK_CELL][neck_box[1] : neck_box[3], neck_box[0] : neck_box[2]], preview)
    placed: dict[int, Image.Image] = {}
    for clip, indices in spec["clips"].items():
        left, top, right, bottom = pipeline.require_box([cells[i] for i in indices], f"props clip '{clip}' (cells {indices})")
        for i in indices:
            placed[i] = pipeline.centered_cell(cells[i][top:bottom, left:right], EFFECT_SCALE, EFFECT_CELL, f"props[{i}]")
    used, clips = pipeline.compact_clips(spec["clips"])
    image = pipeline.assemble_sheet([placed[i] for i in used], EFFECT_CELL)
    image.save(OUT_DIR / sheet_file("props"), optimize=True)
    if preview is not None:
        pipeline.write_preview(image, preview / sheet_file("props"), EFFECT_CELL, EFFECT_CELL // 2, SPRITE_SCALE, {}, f"props scale {EFFECT_SCALE}")
    entry = pipeline.manifest_entry(image, EFFECT_CELL, clips, {})
    props = {
        "sheet": sheet_file("props"),
        "sprite_scale": round(SPRITE_SCALE, 4),
        "grid": entry["grid"],
        "clips": entry["clips"],
        "content": pipeline.clip_contents(image, EFFECT_CELL, entry["clips"]),
    }
    return props, neck


def load_manifest() -> dict:
    path = OUT_DIR / "animation_manifest.json"
    return json.loads(path.read_text()) if path.exists() else {}


def main() -> None:
    global RAW_DIR, OUT_DIR
    parser = argparse.ArgumentParser()
    parser.add_argument("--raw-dir", type=Path, default=RAW_DIR, help="folder with the raw sheets")
    parser.add_argument("--out-dir", type=Path, default=OUT_DIR, help="folder for the game sheets and the manifest")
    parser.add_argument("--preview", type=Path, default=None, help="write per-sheet previews (feet row and height lines, head origin box, neck strip)")
    args = parser.parse_args()
    RAW_DIR, OUT_DIR = args.raw_dir.resolve(), args.out_dir.resolve()

    names = [*BODY_SHEETS, *HEAD_SHEETS, "props"]
    present = [name for name in names if raw_path(name).exists()]
    for name in names:
        if name not in present:
            print(f"skip {name}: {raw_path(name)} not found")
    if not present:
        print("nothing to process")
        return

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    manifest = load_manifest()
    manifest.update({"cell": BODY_CELL, "feet_row": BODY_FEET_ROW, "sprite_scale": round(SPRITE_SCALE, 4)})
    manifest.setdefault("sheets", {})
    for name in present:
        if name in BODY_SHEETS:
            manifest["sheets"][sheet_file(name)] = build_body(name, BODY_SHEETS[name], args.preview)
        elif name in HEAD_SHEETS:
            manifest[name] = build_head(name, HEAD_SHEETS[name], args.preview)
        else:
            manifest["props"], manifest["neck"] = build_props(PROPS, args.preview)
        print(f"  {name}: done")
    pipeline.write_manifest(OUT_DIR / "animation_manifest.json", manifest)
    print("wrote", OUT_DIR)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Build Luz's ground dash, air dash, wall cling and wall jump clips from the P10 Codex raws.

Re-run with the project venv (pillow + numpy + scipy):

    <venv>/bin/python tools/process_luz_mobility.py

Raw sheets live in tools/art_sources/luz/raw/ (gitignored): 1536x1536, 3x3 cells of 512x512,
right-facing, magenta key (see tools/art_sources/luz/prompts/dash_wall.md):

    luz_mobility_ground_dash_raw.png  8 frames -> ground_dash
    luz_mobility_air_dash_raw.png     6 frames -> air_dash
    luz_mobility_wall_raw.png         8 frames -> wall_cling (0-3) and wall_jump (4-7)

Same pipeline as process_luz_jump_fall_land.py (it is imported and reused): key cleaning,
component ownership, ruler normalised to RULER_TARGET_LENGTH, hair match, work canvas centred
on the old 512 cell so the idle body offset and `_sprite.offset` stay valid. None of these
sheets has a standing frame (the dash is a low slide, the others are airborne or on a wall),
so the scale comes from the FACE size (tools/luz_face.py) against the idle's: the head is the
same size as in idle, run, jump and fall. Extra anchors:

    floor  body centroid x on the idle's, lowest sole on the idle's feet row (the slide)
    wall   rightmost body pixel (the palm) on the wall line, torso height on the idle's

Writes assets/player/luz/luz_mobility_sheet.png (replaces the old sheet, whose short-ruler
cells and unused ledge_hang / ledge_climb clips are dropped). Missing raws keep the previous
output for that clip only if the sheet already holds the new clips.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import luz_face as lf  # noqa: E402
import luz_ruler_length as rl  # noqa: E402
import process_luz_attacks as pa  # noqa: E402
import process_luz_combat_hits as pch  # noqa: E402
import process_luz_jump_fall_land as pj  # noqa: E402
import process_luz_run_turn_skid as base  # noqa: E402

ASSET_DIR = pa.ASSET_DIR
RAW_DIR = pa.RAW_DIR
MANIFEST_PATH = pa.MANIFEST_PATH
SHEET_FILE = "luz_mobility_sheet.png"
SHIFT, VSHIFT, FEET_ROW = pa.SHIFT, pa.VSHIFT, pa.FEET_ROW

# Wall surface, in texels right of the collider centre (= the old 512 cell centre): half the
# 29 px collider (14.5 px x 6.9) plus a little, so the palm touches the wall rays (16.5 px).
WALL_OFFSET = 108
WALL_X = SHIFT + 256 + WALL_OFFSET

CLIPS = {
    "ground_dash": {
        "raw": "luz_mobility_ground_dash_raw.png",
        "slots": [0, 1, 2, 3, 4, 5, 6, 7],
        "anchor": ["front"] + ["floor"] * 7,
        "doc": [("B", -35), ("B", -20), ("B", -10), ("B", 5), ("B", 5), ("B", 0), ("B", -10), ("B", -25)],
    },
    "air_dash": {
        "raw": "luz_mobility_air_dash_raw.png",
        "slots": [0, 1, 2, 3, 4, 5],
        "anchor": "body",
        "doc": [("B", -40), ("B", -10), ("B", -5), ("B", -5), ("B", -15), ("B", -35)],
    },
    "wall_cling": {
        "raw": "luz_mobility_wall_raw.png",
        "slots": [0, 1, 2, 3],
        "anchor": "wall",
        "doc": [("B", -60), ("B", -60), ("B", -65), ("B", -60)],
    },
    "wall_jump": {
        "raw": "luz_mobility_wall_raw.png",
        "slots": [4, 5, 6, 7],
        "anchor": ["wall", "torso", "torso", "torso"],
        "doc": [("B", -45), ("B", -35), ("B", -30), ("B", -40)],
    },
}
# The wall raw was drawn with a head 20% smaller than the idle's at the same body size, so the
# face alone (scale 0.954) would blow the body up 14%: its navy clothes area (sqrt, raw px) is
# 182 against 199 on the first wall raw, which matched the idle at 0.767 (body-only scale 0.84).
# The scale is the middle of both so neither the head nor the body pops against the idle.
SCALE_OVERRIDE = {"luz_mobility_wall_raw.png": 0.89}
SHEET_ORDER = ["ground_dash", "air_dash", "wall_cling", "wall_jump"]


def place_ex(source: Image.Image, scale: float, anchor: str, idle: dict[str, float], front_ref: float, label: str) -> Image.Image:
    if anchor not in ("floor", "wall"):
        return _place_original(source, scale, anchor, idle, front_ref, label)
    scaled = pj.scaled_copy(source, scale)
    x0, y0, x1, y1 = base.alpha_bbox(scaled)
    scaled = scaled.crop((x0, y0, x1 + 1, y1 + 1))
    mask = base.body_mask(scaled)
    if not mask.any():
        mask = np.array(scaled.getchannel("A")) > 16
    ys, xs = np.where(mask)
    if anchor == "floor":
        left = round(idle["body_x"] - float(xs.mean())) + SHIFT
        top = FEET_ROW - int(ys.max()) + VSHIFT
    else:
        left = WALL_X - int(xs.max())
        _, cy = pj.torso_centroid(mask)
        top = round(idle["torso_y"] - cy) + VSHIFT
    out = Image.new("RGBA", (pj.WORK_W, pj.WORK_H), (0, 0, 0, 0))
    if left < 0 or left + scaled.width > pj.WORK_W or top < 0 or top + scaled.height > pj.WORK_H:
        raise ValueError(f"{label}: art leaves the work canvas (left={left}, top={top}, size={scaled.size})")
    out.alpha_composite(scaled, (left, top))
    return out


_place_original = pj.place
pj.place = place_ex


def load_raws() -> dict[str, tuple[dict[int, Image.Image], float]]:
    face_ref = pj.idle_face()
    result = {}
    for raw_name in sorted({c["raw"] for c in CLIPS.values()}):
        path = RAW_DIR / raw_name
        if not path.exists():
            continue
        wanted = sorted({s for c in CLIPS.values() if c["raw"] == raw_name for s in c["slots"]})
        frames = pa.raw_frames(base.clean_key(Image.open(path)), raw_name, wanted)
        face = lf.median_face([pj.scaled_copy(f, pj.PROVISIONAL_SCALE) for f in frames.values()])
        if face is None:
            raise ValueError(f"{raw_name}: no face found to fix the scale")
        scale = pj.PROVISIONAL_SCALE * face_ref / face
        print(f"{raw_name}: scale={scale:.3f} (face {face:.1f} at {pj.PROVISIONAL_SCALE} vs idle {face_ref:.1f})")
        if raw_name in SCALE_OVERRIDE:
            scale = SCALE_OVERRIDE[raw_name]
            print(f"  override: scale={scale:.3f}")
        result[raw_name] = (frames, scale)
    return result


def main() -> int:
    pch.FEET_ROW = FEET_ROW + VSHIFT
    manifest = json.loads(MANIFEST_PATH.read_text())
    idle = pj.idle_references()
    front_ref = pa.idle_reference()[0]
    raws = load_raws()
    ruler_report: list[dict] = []
    built: dict[str, list[Image.Image]] = {}
    for name in SHEET_ORDER:
        frames = pj.process_clip(name, CLIPS[name], idle, front_ref, raws, ruler_report)
        if frames is not None:
            built[name] = frames
    if len(built) < len(SHEET_ORDER):
        print(f"missing raws: only {sorted(built)} built, the sheet is not written")
        return 1
    manifest["sheets"].pop(SHEET_FILE, None)
    pj.SHEET_LAYOUT["mobility"] = {"file": SHEET_FILE, "order": SHEET_ORDER}
    pj.build_sheet("mobility", built, manifest)
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n")
    lengths = [info["after"] for info in ruler_report if info.get("after")]
    if lengths:
        print(f"ruler target {rl.RULER_TARGET_LENGTH:.0f} texels: final min {min(lengths):.1f} max {max(lengths):.1f}")
    for info in ruler_report:
        if info.get("kept_drawn"):
            print(f"NOTE: ruler of {info['label']} kept as drawn (hidden behind the body)")
    bad = [i["label"] for i in ruler_report if (not i.get("found") and not i.get("kept_drawn")) or i.get("overflow")]
    for label in bad:
        print(f"WARNING: ruler not normalised in {label}")
    return 2 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())

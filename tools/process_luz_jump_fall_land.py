#!/usr/bin/env python3
"""Build Luz's jump, fall, landing, double jump and crouch clips from the P9 Codex raw sheets.

Re-run with the project venv (pillow + numpy):

    /tmp/luzvenv/bin/python tools/process_luz_jump_fall_land.py

Raw sheets live in tools/art_sources/luz/raw/ (gitignored): 1536x1536, 3x3 cells of 512x512,
right-facing, on a magenta key (see tools/art_sources/luz/prompts/jump_fall_land.md):

    luz_jump_ascent_raw.png  5 frames -> jump_ascent (plays as `jump`)
    luz_jump_fall_raw.png    5 frames (+1 spare) -> fall
    luz_jump_land_raw.png    5 frames -> land
    luz_jump_double_raw.png  6 frames -> double_jump
    luz_crouch_raw.png       8 frames -> crouch (enter 0-2, hold 3-4) and crouch_exit (5-7)

Same pipeline as process_luz_attacks.py (key cleaning, component ownership, per-sheet scale,
ruler normalised to RULER_TARGET_LENGTH, work canvas centred on the old 512 cell so the idle
body offset and `_sprite.offset` stay valid). Differences: the per-sheet scale comes from the
standing frame of the landing and crouch sheets (standing height 331 over the drawn height),
airborne frames are anchored by the torso (upper-body centroid) on the idle's, so the
torso follows the physics trajectory like the Penitent's sash, and the somersault frames by the
body centroid.

Writes assets/player/luz/luz_jump_sheet.png (jump_ascent, fall, land, double_jump) and
luz_crouch_sheet.png (crouch, crouch_exit) and their manifest entries; the old short-ruler
jump/fall/crouch/land cells of luz_locomotion_sheet.png are removed from the manifest.
Missing raws are skipped. Exit code 2 when a ruler could not be normalised.
"""

from __future__ import annotations

import json
import math
import statistics
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, str(Path(__file__).resolve().parent))
import luz_ruler_length as rl  # noqa: E402
import process_luz_attacks as pa  # noqa: E402  (patches the wood mask, shares the work canvas)
import process_luz_combat_hits as pch  # noqa: E402
import process_luz_run_turn_skid as base  # noqa: E402
import luz_face as lf  # noqa: E402

ROOT = pa.ROOT
RAW_DIR = pa.RAW_DIR
ASSET_DIR = pa.ASSET_DIR
MANIFEST_PATH = pa.MANIFEST_PATH
OUT_CELL = pa.OUT_CELL
WORK_W, WORK_H, SHIFT, VSHIFT = pa.WORK_W, pa.WORK_H, pa.SHIFT, pa.VSHIFT
FEET_ROW = pa.FEET_ROW
MAX_TEXTURE = pa.MAX_TEXTURE

# Rows (output texels, from the topmost body row) averaged for the torso anchor: head and chest.
TORSO_BAND = 150

# clip -> raw sheet, slots (raw cells, in clip order), anchor and documentation of the art request.
# anchor: "front" (planted front foot on the idle's), "torso" (upper-body centroid on the idle's),
# "body" (whole-body centroid on the idle's, for the somersault).
CLIPS = {
    "jump_ascent": {
        "sheet": "jump",
        "raw": "luz_jump_ascent_raw.png",
        "slots": [0, 1, 2, 3, 4],
        "anchor": "torso",
        "doc": [("B", -40), ("B", -45), ("B", -50), ("B", -45), ("B", -40)],
    },
    "fall": {
        "sheet": "jump",
        "raw": "luz_jump_fall_raw.png",
        "slots": [0, 1, 2, 3, 4],
        "anchor": "torso",
        "doc": [("B", -30), ("B", -15), ("B", -30), ("B", -40), ("B", -35)],
    },
    "land": {
        "sheet": "jump",
        "raw": "luz_jump_land_raw.png",
        "slots": [0, 1, 2, 3, 4],
        "anchor": "front",
        # The stance frame is drawn with the ruler hanging at ~55 deg; the idle holds it at 35.
        "force": {4: ("B", -25.0)},
        "doc": [("B", -30), ("B", -25), ("B", -25), ("B", -30), ("B", -35)],
    },
    "double_jump": {
        "sheet": "jump",
        "raw": "luz_jump_double_raw.png",
        "slots": [0, 1, 2, 3, 4, 5],
        "anchor": ["torso", "body", "body", "body", "torso", "torso"],
        "doc": [("B", -50), ("B", -45), ("B", -45), ("B", -45), ("B", -40), ("B", -40)],
    },
    "crouch": {
        "sheet": "crouch",
        "raw": "luz_crouch_raw.png",
        "slots": [0, 1, 2, 3, 4],
        "anchor": "front",
        "doc": [("B", -35), ("B", -35), ("B", -30), ("B", -30), ("B", -30)],
    },
    "crouch_exit": {
        "sheet": "crouch",
        "raw": "luz_crouch_raw.png",
        "slots": [5, 6, 7],
        "anchor": "front",
        "force": {2: ("B", -25.0)},  # the stance frame is drawn with the ruler hanging steeply
        "doc": [("B", -35), ("B", -35), ("B", -35)],
    },
}


SHEET_LAYOUT = {
    "jump": {"file": "luz_jump_sheet.png", "order": ["jump_ascent", "fall", "land", "double_jump"]},
    "crouch": {"file": "luz_crouch_sheet.png", "order": ["crouch", "crouch_exit"]},
}
OLD_LOCOMOTION_CLIPS = ["jump_ascent", "fall", "crouch", "land"]


def figure_top(mask: np.ndarray) -> int:
    widths = mask.sum(axis=1)
    return int(np.argmax(widths >= 12))


def idle_references() -> dict[str, float]:
    """Idle statistics averaged over the clip: standing height, torso centroid (x, y), body centroid (x, y)."""
    sheet = Image.open(ASSET_DIR / "luz_idle_sheet.png").convert("RGBA")
    heights, torso, body = [], [], []
    for slot in (0, 1, 2, 4, 5, 6, 7):
        cell = sheet.crop(((slot % 4) * OUT_CELL, (slot // 4) * OUT_CELL, (slot % 4 + 1) * OUT_CELL, (slot // 4 + 1) * OUT_CELL))
        mask = base.body_mask(cell)
        rows = np.where(mask.any(axis=1))[0]
        heights.append(float(rows.max() - rows.min() + 1))
        torso.append(torso_centroid(mask))
        ys, xs = np.where(mask)
        body.append((float(xs.mean()), float(ys.mean())))
    return {
        "height": statistics.mean(heights),
        "torso_x": statistics.mean(t[0] for t in torso),
        "torso_y": statistics.mean(t[1] for t in torso),
        "body_x": statistics.mean(b[0] for b in body),
        "body_y": statistics.mean(b[1] for b in body),
    }


def torso_centroid(mask: np.ndarray) -> tuple[float, float]:
    top = figure_top(mask)
    sub = mask[top : top + TORSO_BAND]
    ys, xs = np.where(sub)
    return float(xs.mean()), float(ys.mean() + top)


# Raw sheets with a standing frame (slot, 0-based): the scale is the idle's standing height over
# the standing figure's height. The sheets without one (jump, fall, double jump: airborne) used
# to take the mean of those scales (0.767), which made the fall's head 12% smaller than the
# jump's and the idle's (a visible pop on the phone). They are now scaled from the face size
# (tools/luz_face.py) so their head matches the idle's; the fall then eases from the idle face
# to the face of the landing's standing frame over its frames, so fall -> land has no pop either.
STANDING_SLOT = {"luz_jump_land_raw.png": 4, "luz_crouch_raw.png": 7}
PROVISIONAL_SCALE = 0.767
FACE_RAMP_TO_LAND = {"fall"}


def scaled_copy(source: Image.Image, scale: float) -> Image.Image:
    w, h = max(1, round(source.width * scale)), max(1, round(source.height * scale))
    return pch.unpremultiply(pch.premultiply(source).resize((w, h), pch.RESAMPLE))


def idle_face() -> float:
    sheet = Image.open(ASSET_DIR / "luz_idle_sheet.png").convert("RGBA")
    frames = [sheet.crop(((s % 4) * OUT_CELL, (s // 4) * OUT_CELL, (s % 4 + 1) * OUT_CELL, (s // 4 + 1) * OUT_CELL)) for s in (0, 1, 2, 4, 5, 6, 7)]
    return lf.median_face(frames)


def place(source: Image.Image, scale: float, anchor: str, idle: dict[str, float], front_ref: float, label: str) -> Image.Image:
    scaled = scaled_copy(source, scale)
    x0, y0, x1, y1 = base.alpha_bbox(scaled)
    scaled = scaled.crop((x0, y0, x1 + 1, y1 + 1))
    mask = base.body_mask(scaled)
    if not mask.any():
        mask = np.array(scaled.getchannel("A")) > 16
    if anchor == "front":
        _, right_f, bottom = pa.feet_span(mask)
        left = round(front_ref - right_f)
        top = FEET_ROW - bottom
    elif anchor == "torso":
        cx, cy = torso_centroid(mask)
        left = round(idle["torso_x"] - cx)
        top = round(idle["torso_y"] - cy)
    else:
        ys, xs = np.where(mask)
        left = round(idle["body_x"] - float(xs.mean()))
        top = round(idle["body_y"] - float(ys.mean()))
    left += SHIFT
    top += VSHIFT
    out = Image.new("RGBA", (WORK_W, WORK_H), (0, 0, 0, 0))
    if left < 0 or left + scaled.width > WORK_W or top < 0 or top + scaled.height > WORK_H:
        raise ValueError(f"{label}: art leaves the work canvas (left={left}, top={top}, size={scaled.size})")
    out.alpha_composite(scaled, (left, top))
    return out


def load_raws(idle: dict[str, float]) -> dict[str, tuple[dict[int, Image.Image], float]]:
    """Cropped raw frames and the raw -> output scale of every raw file that exists."""
    sources: dict[str, dict[int, Image.Image]] = {}
    for raw_name in sorted({c["raw"] for c in CLIPS.values()}):
        raw_path = RAW_DIR / raw_name
        if not raw_path.exists():
            continue
        wanted = sorted({s for c in CLIPS.values() if c["raw"] == raw_name for s in c["slots"]})
        sources[raw_name] = pa.raw_frames(base.clean_key(Image.open(raw_path)), raw_name, wanted)
    measured: dict[str, float] = {}
    for raw_name, slot in STANDING_SLOT.items():
        if raw_name in sources:
            rows = np.where(base.body_mask(sources[raw_name][slot]).any(axis=1))[0]
            measured[raw_name] = idle["height"] / float(rows.max() - rows.min() + 1)
    if not measured:
        raise ValueError("no standing reference raw (land or crouch) to fix the scale")
    result: dict[str, tuple[dict[int, Image.Image], float]] = {}
    face_ref = idle_face()
    for name, frames in sources.items():
        if name in measured:
            result[name] = (frames, measured[name])
            print(f"{name}: scale={measured[name]:.3f} (standing height)")
            continue
        face = lf.median_face([scaled_copy(f, PROVISIONAL_SCALE) for f in frames.values()])
        if face is None:
            raise ValueError(f"{name}: no face found to fix the scale")
        scale = PROVISIONAL_SCALE * face_ref / face
        result[name] = (frames, scale)
        print(f"{name}: scale={scale:.3f} (face {face:.1f} at {PROVISIONAL_SCALE} vs idle {face_ref:.1f}; before: 0.767)")
    return result


def land_face_ratio(raws: dict) -> float:
    """Face of the landing's standing frame over the idle's (the fall eases to it)."""
    name = "luz_jump_land_raw.png"
    if name not in raws:
        return 1.0
    frames, scale = raws[name]
    face = lf.face_size(scaled_copy(frames[STANDING_SLOT[name]], scale))
    return 1.0 if face is None else face / idle_face()


def process_clip(name: str, config: dict, idle: dict[str, float], front_ref: float, raws: dict, ruler_report: list[dict], land_ratio: float = 1.0):
    if config["raw"] not in raws:
        print(f"{name}: {config['raw']} not found, skipped (previous output kept)")
        return None
    sources, scale = raws[config["raw"]]
    idle_hair = base.idle_hair_luminance()
    frames = []
    for index, slot in enumerate(config["slots"]):
        label = f"{name}[{index}]"
        anchor = config["anchor"][index] if isinstance(config["anchor"], list) else config["anchor"]
        count = len(config["slots"])
        ratio = 1.0 + (land_ratio - 1.0) * index / max(count - 1, 1) if name in FACE_RAMP_TO_LAND else 1.0
        placed = place(sources[slot], scale * ratio, anchor, idle, front_ref, label)
        force = config.get("force", {}).get(index)
        theta = pa.theta_for(placed, force[0], float(force[1])) if force else None
        frame, info = pa.fit_ruler(placed, label, theta)
        if not info.get("found"):
            # The ruler is hidden behind the body (somersault): the drawn one is kept as is.
            frame = placed
            info = {**info, "label": label, "kept_drawn": True}
        ruler_report.append(info)
        rgba = np.array(frame)
        lum = base.hair_luminance(rgba, rl.band_mask(frame))
        gain = idle_hair / lum
        if gain > 1.04:
            frame = base.match_hair(frame, idle_hair)
        frame = pa.defringe(frame)
        mask = base.body_mask(frame)
        fl, fr, bottom = pa.feet_span(mask)
        x0, y0, x1, y1 = base.alpha_bbox(frame)
        tx, ty = torso_centroid(mask)
        final = pa.ruler_angle(frame)
        doc = config["doc"][index]
        print(
            f"  {index} slot {slot} {anchor}: h={y1 - y0 + 1:3d} top={y0 - VSHIFT} sole={bottom - VSHIFT} "
            f"feet=[{fl:.0f},{fr:.0f}] torso=({tx - SHIFT:.0f},{ty - VSHIFT:.0f}) "
            f"ruler {('%s%+.0f' % final) if final else '?'} doc {doc[0]}{doc[1]:+d} | {base.describe_ruler(info)}"
        )
        frames.append(frame)
    return frames


def build_sheet(sheet_key: str, clip_frames: dict[str, list[Image.Image]], manifest: dict) -> None:
    layout = SHEET_LAYOUT[sheet_key]
    sheet_name = layout["file"]
    path = ASSET_DIR / sheet_name
    previous = Image.open(path).convert("RGBA") if path.exists() else None
    old_entry = manifest["sheets"].get(sheet_name)
    if len(clip_frames) < len(layout["order"]):
        if old_entry is None or previous is None:
            raise ValueError(f"{sheet_name}: missing raws and no previous sheet to keep: {sorted(set(layout['order']) - set(clip_frames))}")
    width, height = pa.cell_size_for(clip_frames)
    if old_entry is not None:
        width, height = max(width, old_entry["grid"]["cell_width"]), max(height, old_entry["grid"]["cell_height"])
    columns = MAX_TEXTURE // width
    ordered = []
    for name in layout["order"]:
        frames = clip_frames.get(name)
        frames = [pa.centred(f, width, height) for f in frames] if frames is not None else pa.old_frames(previous, old_entry, old_entry["clips"][name], width, height)
        ordered.append((name, frames))
    slots = sum(len(frames) for _, frames in ordered)
    rows = (slots + columns - 1) // columns
    if rows * height > MAX_TEXTURE:
        raise ValueError(f"{sheet_name}: {slots} cells of {width}x{height} do not fit {MAX_TEXTURE}px")
    sheet = Image.new("RGBA", (columns * width, rows * height), (0, 0, 0, 0))
    clips: dict[str, list[int]] = {}
    cursor = 0
    for name, frames in ordered:
        for i, frame in enumerate(frames):
            sheet.alpha_composite(frame, (((cursor + i) % columns) * width, ((cursor + i) // columns) * height))
        clips[name] = list(range(cursor, cursor + len(frames)))
        cursor += len(frames)
    sheet.save(path)
    manifest["sheets"][sheet_name] = {"grid": {"columns": columns, "rows": rows, "cell_width": width, "cell_height": height}, "clips": clips}
    print(f"wrote {sheet_name}: {columns}x{rows} cells of {width}x{height}: {clips}")


def main() -> int:
    pch.FEET_ROW = FEET_ROW + VSHIFT  # luz_ruler_length measures the floor clearance against this row
    manifest = json.loads(MANIFEST_PATH.read_text())
    idle = idle_references()
    front_ref = pa.idle_reference()[0]
    print(f"idle: height {idle['height']:.0f}, torso ({idle['torso_x']:.1f},{idle['torso_y']:.1f}), body ({idle['body_x']:.1f},{idle['body_y']:.1f}), front foot {front_ref:.1f}")
    ruler_report: list[dict] = []
    raws = load_raws(idle)
    land_ratio = land_face_ratio(raws)
    print(f"fall eases to the landing face ratio {land_ratio:.3f}")
    built: dict[str, dict[str, list[Image.Image]]] = {}
    for name, config in CLIPS.items():
        frames = process_clip(name, config, idle, front_ref, raws, ruler_report, land_ratio)
        if frames is not None:
            built.setdefault(config["sheet"], {})[name] = frames
    for sheet_key, clip_frames in built.items():
        build_sheet(sheet_key, clip_frames, manifest)
    if built:
        locomotion = manifest["sheets"].get("luz_locomotion_sheet.png")
        if locomotion is not None:
            for clip in OLD_LOCOMOTION_CLIPS:
                locomotion["clips"].pop(clip, None)
            if not locomotion["clips"]:
                del manifest["sheets"]["luz_locomotion_sheet.png"]
        MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n")

    lengths = [info["after"] for info in ruler_report if info.get("after")]
    if lengths:
        print(f"ruler target {rl.RULER_TARGET_LENGTH:.0f} texels: final min {min(lengths):.1f} max {max(lengths):.1f}")
    for info in ruler_report:
        if info.get("kept_drawn"):
            print(f"NOTE: ruler of {info['label']} kept as drawn (hidden behind the body)")
    bad = [info["label"] for info in ruler_report if (not info.get("found") and not info.get("kept_drawn")) or info.get("overflow")]
    for label in bad:
        print(f"WARNING: ruler not normalised in {label}")
    return 2 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())

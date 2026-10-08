#!/usr/bin/env python3
"""Build Luz's six attack clips from the P8 Codex raw sheets.

Re-run with the project venv (pillow + numpy):

    /tmp/luzvenv/bin/python tools/process_luz_attacks.py

Raw sheets live in tools/art_sources/luz/raw/ (gitignored): 1536x1536, 3x3 cells of
512x512, right-facing, RGB on a noisy magenta key (see
tools/art_sources/luz/prompts/attacks_penitent.md, sections 3-5):

    luz_attack_hit1_raw.png    9 frames -> ground_attack_1
    luz_attack_hit2_raw.png    8 frames -> ground_attack_2
    luz_attack_hit3_raw.png    9 frames -> ground_attack_3
    luz_attack_crouch_raw.png  8 frames -> crouch_attack
    luz_attack_air_raw.png     8 frames -> air_horizontal_attack
    luz_attack_up_raw.png      8 frames -> up_attack

Pipeline per frame (cloned from process_luz_run_turn_skid.py): clean the key
(`clean_key`), give every connected component to the raw cell holding most of its
pixels, scale by a per-sheet factor so the head matches the idle (Codex draws every
sheet at a different size; the factors were fitted by overlaying the face on the idle
face), put the lowest sole of the body on the shared feet row (413) and centre the feet
span on the idle feet span (ground clips) or the body centroid on the idle body
centroid (air: the feet float), then `luz_ruler_length.normalize_ruler` brings the
ruler to RULER_TARGET_LENGTH. A frame whose ruler cannot fit the 512 cell is
re-aimed (`RULER_FORCE`, swings the ruler about the grip by an explicit angle) and
reported as repainted.

Writes assets/player/luz/luz_ground_combat_sheet.png (4 clips, 4x9 cells) and
luz_air_combat_sheet.png (up + air; the old plunge cells 16-23 are carried over) and
the matching manifest entries, including the per-clip phase table ("phases") and the
30 fps tick table ("frame_ticks_30fps") that the combat code times from.
Exit code 2 when a ruler could not be normalised.
"""

from __future__ import annotations

import json
import math
import statistics
import sys
from collections import Counter
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import luz_ruler_length as rl  # noqa: E402
import process_luz_combat_hits as pch  # noqa: E402
import process_luz_run_turn_skid as base  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = ROOT / "tools" / "art_sources" / "luz" / "raw"
ASSET_DIR = ROOT / "assets" / "player" / "luz"
MANIFEST_PATH = ASSET_DIR / "animation_manifest.json"

RAW_CELL = 512
RAW_COLUMNS = 3
OUT_CELL = pch.OUT_CELL_SIZE
OUT_COLUMNS = 4
FEET_ROW = pch.FEET_ROW
MIN_COMPONENT_PX = 400
# Rows (output texels) above the lowest sole used to measure the feet span.
FEET_BAND = 26
# Idle body centroid y (ruler excluded): the air clips anchor their body here.
IDLE_BODY_Y = 254.8

# Per-sheet scale raw -> output. Fitted by overlaying the face of an upright-head frame
# on the idle face (Codex's head size changes per sheet: standing hit1/up are ~425 and
# ~418 raw px, hit2/hit3 have no standing frame).
SCALES = {
    "hit1": 0.77,
    "hit2": 0.67,
    "hit3": 0.90,
    "crouch": 0.72,
    "air": 0.74,
    "up": 0.79,
}

# Frame tables. slots: raw cell indices in clip order. ticks: hold of each pose at 30 fps
# (1 tick = 33 ms, from the Penitent video). doc: ruler angle the art request asks for
# per frame, (direction, degrees above horizontal), used to report the drawn angle error.
# phases: indices into the clip. contact: first active frame (manifest contact_frames).
CLIPS = {
    "ground_attack_1": {
        "sheet": "ground",
        "raw": "hit1",
        "slots": list(range(9)),
        "ticks": [1, 2, 1, 1, 2, 2, 3, 3, 2],
        "doc": [("B", -35), ("B", -20), ("F", -15), ("B", 30), ("F", -5), ("F", 5), ("B", 25), ("B", 15), ("B", -35)],
        "phases": {"windup": [0, 1, 2, 3], "active": [4, 5, 6], "hold": [7], "recovery": [8]},
        "contact": 4,
        "anchor": "front",
    },
    "ground_attack_2": {
        "sheet": "ground",
        "raw": "hit2",
        "slots": list(range(8)),
        "ticks": [1, 3, 2, 1, 2, 2, 2, 1],
        "doc": [("B", -20), ("B", 30), ("F", -10), ("F", 0), ("B", -25), ("F", -15), ("B", -35), ("B", -35)],
        "phases": {"windup": [0, 1], "active": [2, 3, 4, 5], "hold": [6], "recovery": [7]},
        "contact": 2,
        "anchor": "front",
    },
    "ground_attack_3": {
        "sheet": "ground",
        "raw": "hit3",
        "slots": list(range(9)),
        "ticks": [2, 2, 2, 1, 2, 6, 2, 3, 2],
        "doc": [("B", 10), ("B", 30), ("B", 35), ("F", -40), ("B", -20), ("B", -15), ("B", -30), ("B", -35), ("B", -35)],
        "phases": {"windup": [0, 1, 2, 3], "active": [4, 5], "recovery": [6, 7, 8]},
        "contact": 4,
        "anchor": "front",
    },
    "crouch_attack": {
        "sheet": "ground",
        "raw": "crouch",
        "slots": list(range(8)),
        "ticks": [3, 1, 1, 1, 2, 2, 2, 2],
        "doc": [("B", -25), ("B", -30), ("B", 30), ("B", 40), ("F", -35), ("B", -25), ("B", -30), ("B", -25)],
        "phases": {"windup": [0, 1, 2, 3], "active": [4, 5], "recovery": [6, 7]},
        "contact": 4,
        "anchor": "front",
    },
    "air_horizontal_attack": {
        "sheet": "air",
        "raw": "air",
        "slots": list(range(8)),
        "ticks": [1, 1, 1, 2, 2, 3, 1, 2],
        "doc": [("B", -30), ("B", 30), ("B", 20), ("F", -30), ("B", -15), ("F", -10), ("B", -30), ("B", -35)],
        "phases": {"windup": [0, 1, 2], "active": [3, 4, 5], "recovery": [6, 7]},
        "contact": 3,
        "anchor": "body",
    },
    "up_attack": {
        "sheet": "air",
        "raw": "up",
        "slots": list(range(8)),
        "ticks": [1, 1, 1, 1, 1, 4, 4, 2],
        "doc": [("B", -35), ("B", -25), ("B", 5), ("F", 10), ("F", 60), ("F", 60), ("F", 50), ("B", -35)],
        "phases": {"windup": [0, 1, 2, 3], "active": [4, 5, 6], "recovery": [7]},
        "contact": 4,
        "anchor": "front",
    },
}

# Frames whose ruler is re-aimed to an explicit angle (direction, degrees above
# horizontal) because the drawn one cannot be normalised in the 512 cell. Filled from
# the first run's report; see main().
RULER_FORCE: dict[tuple[str, int], tuple[str, float]] = {
    # The up attack is drawn at ~45 deg and crosses the cell top; the art request asks for 60.
    ("up_attack", 4): ("F", 60.0),
    ("up_attack", 5): ("F", 60.0),
    ("up_attack", 6): ("F", 50.0),
}
# Automatic re-aim: when the module's free swing ends more than this far from the angle the art
# request asks for (and the drawn angle was close to it), the ruler is repainted at the request's angle.
AUTO_AIM_TOLERANCE = 15.0

SHEET_LAYOUT = {
    "ground": {
        "file": "luz_ground_combat_sheet.png",
        "rows": 9,
        "order": ["ground_attack_1", "ground_attack_2", "ground_attack_3", "crouch_attack"],
    },
    "air": {
        "file": "luz_air_combat_sheet.png",
        "rows": 6,
        "order": ["up_attack", "air_horizontal_attack"],
        "keep_cells": list(range(16, 24)),  # plunge + plunge_land, untouched
    },
}


_ORIGINAL_WOOD_MASK = rl.wood_mask


def _closed_wood_mask(rgba: np.ndarray) -> np.ndarray:
    """wood_mask plus a 3x3 closing over opaque wood-ordered pixels.

    The attack sheets are scaled by 0.67-0.9 (the run sheets by ~1), which blends the ruler's
    outline and ticks into in-between browns; the plain mask then falls apart into small pieces
    and the hair becomes the "ruler". Closing the gaps keeps the ruler one elongated component."""
    mask = _ORIGINAL_WOOD_MASK(rgba)
    r, g, b, a = (rgba[..., k].astype(np.int16) for k in range(4))
    candidate = (a > 128) & (r > g) & (g > b) & (r - b >= 40) & (r < 250) & (r > 60)
    pad = np.pad(mask, 2)
    grown = np.zeros_like(pad)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            grown |= np.roll(np.roll(pad, dy, axis=0), dx, axis=1)
    closed = grown.copy()
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            closed &= np.roll(np.roll(grown, dy, axis=0), dx, axis=1)
    closed = closed[2:-2, 2:-2]
    return mask | (closed & candidate)


rl.wood_mask = _closed_wood_mask


def raw_frames(raw: Image.Image, name: str, wanted: list[int]) -> dict[int, Image.Image]:
    """Crop each wanted raw cell to the art owned by that cell (components may cross cells)."""
    if raw.size != (RAW_COLUMNS * RAW_CELL, RAW_COLUMNS * RAW_CELL):
        raise ValueError(f"{name}: expected {RAW_COLUMNS * RAW_CELL}px square, got {raw.size}")
    labels, sizes, boxes = pch.label_components(raw.getchannel("A").tobytes(), raw.width, raw.height)
    votes: dict[int, Counter] = {}
    for index, label in enumerate(labels):
        if label and sizes[label] >= MIN_COMPONENT_PX:
            y, x = divmod(index, raw.width)
            cell = min(y // RAW_CELL, RAW_COLUMNS - 1) * RAW_COLUMNS + min(x // RAW_CELL, RAW_COLUMNS - 1)
            votes.setdefault(label, Counter())[cell] += 1
    owned: dict[int, set[int]] = {cell: set() for cell in range(RAW_COLUMNS * RAW_COLUMNS)}
    for label, counter in votes.items():
        owned[counter.most_common(1)[0][0]].add(label)
    label_array = np.array(labels, dtype=np.int32).reshape(raw.height, raw.width)
    frames: dict[int, Image.Image] = {}
    for cell in wanted:
        if not owned[cell]:
            raise ValueError(f"{name}: cell {cell} has no art")
        x0 = min(boxes[label][0] for label in owned[cell])
        y0 = min(boxes[label][1] for label in owned[cell])
        x1 = max(boxes[label][2] for label in owned[cell])
        y1 = max(boxes[label][3] for label in owned[cell])
        crop = np.array(raw.crop((x0, y0, x1 + 1, y1 + 1)))
        keep = np.isin(label_array[y0 : y1 + 1, x0 : x1 + 1], list(owned[cell]))
        crop[~keep] = 0
        frames[cell] = Image.fromarray(crop, "RGBA")
    return frames


def feet_span(mask: np.ndarray) -> tuple[float, float, int]:
    """(left, right, lowest row) of the body's feet: body pixels within FEET_BAND rows of the lowest."""
    rows = np.where(mask.any(axis=1))[0]
    bottom = int(rows.max())
    xs = np.where(mask[max(0, bottom - FEET_BAND) : bottom + 1].any(axis=0))[0]
    return float(xs.min()), float(xs.max()), bottom


def idle_reference() -> tuple[float, float, float]:
    """(front-foot x, body centroid x, feet-span midpoint x) averaged over the idle clip."""
    sheet = Image.open(ASSET_DIR / "luz_idle_sheet.png").convert("RGBA")
    mids, centres, fronts = [], [], []
    for slot in (0, 1, 2, 4, 5, 6, 7):
        cell = sheet.crop(((slot % 4) * OUT_CELL, (slot // 4) * OUT_CELL, (slot % 4 + 1) * OUT_CELL, (slot // 4 + 1) * OUT_CELL))
        mask = base.body_mask(cell)
        left, right, _ = feet_span(mask)
        mids.append((left + right) / 2)
        fronts.append(right)
        centres.append(float(np.where(mask)[1].mean()))
    return statistics.mean(fronts), statistics.mean(centres), statistics.mean(mids)


def place(source: Image.Image, scale: float, mode: str, ref: float, label: str) -> Image.Image:
    """Scale `source`, then put it on the feet row with its front foot on the idle's front foot
    ("front", the planted foot of the Penitent's stance: the rear foot slides, the front one
    never moves) or on the idle body centroid ("body", the air clips: the feet float)."""
    w, h = max(1, round(source.width * scale)), max(1, round(source.height * scale))
    scaled = pch.unpremultiply(pch.premultiply(source).resize((w, h), pch.RESAMPLE))
    x0, y0, x1, y1 = base.alpha_bbox(scaled)
    scaled = scaled.crop((x0, y0, x1 + 1, y1 + 1))
    mask = base.body_mask(scaled)
    if not mask.any():
        mask = np.array(scaled.getchannel("A")) > 16
    if mode == "front":
        _, right_f, bottom = feet_span(mask)
        left = round(ref - right_f)
        top = FEET_ROW - bottom
    else:
        ys, xs = np.where(mask)
        left = round(ref - float(xs.mean()))
        top = round(IDLE_BODY_Y - float(ys.mean()))
    # Art that would cross the right edge (an arm and ruler thrown forward) pushes the whole frame
    # back by the smallest amount that keeps it inside the cell; reported as a slide.
    slide = max(0, left + scaled.width - (OUT_CELL - 3))
    if slide:
        print(f"    SLIDE {label}: frame moved {slide} texels back so the drawn arm and ruler stay inside the cell")
        left -= slide
    canvas = Image.new("RGBA", (OUT_CELL + 2 * 200, OUT_CELL + 2 * 200), (0, 0, 0, 0))
    canvas.alpha_composite(scaled, (left + 200, top + 200))
    out = canvas.crop((200, 200, 200 + OUT_CELL, 200 + OUT_CELL))
    lost = int(np.array(canvas.getchannel("A")).astype(bool).sum() - np.array(out.getchannel("A")).astype(bool).sum())
    if lost:
        print(f"    WARNING {label}: {lost} px of art leave the cell on placement (left={left}, top={top}, size={scaled.size})")
    return out


def defringe(frame: Image.Image) -> Image.Image:
    """Recolour magenta-tinted edge pixels (the dark outline blended with the key) from the
    solid, non-pink pixels around them; alpha is untouched."""
    a = np.array(frame).astype(np.float64)
    r, g, b, al = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    pink = (al > 0) & (np.minimum(r, b) - g > 28)
    if not pink.any():
        return frame
    good = ((al > 200) & ~pink).astype(np.float64)
    weights = np.zeros_like(good)
    colour = np.zeros_like(a[..., :3])
    padded_w = np.pad(good, 3)
    padded_c = np.pad(a[..., :3] * good[..., None], ((3, 3), (3, 3), (0, 0)))
    for dy in range(-3, 4):
        for dx in range(-3, 4):
            weights += padded_w[3 + dy : 3 + dy + good.shape[0], 3 + dx : 3 + dx + good.shape[1]]
            colour += padded_c[3 + dy : 3 + dy + good.shape[0], 3 + dx : 3 + dx + good.shape[1]]
    fix = pink & (weights > 0)
    a[..., :3][fix] = colour[fix] / weights[fix][:, None]
    # Pixels with no solid neighbour: pull the colour to its green channel (grey-dark).
    rest = pink & ~fix
    a[..., 0][rest] = g[rest]
    a[..., 2][rest] = g[rest]
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


def ruler_angle(frame: Image.Image) -> tuple[str, float] | None:
    """(direction F/B, degrees above horizontal) of the drawn ruler, grip to tip."""
    ruler = rl.find_ruler(np.array(frame.convert("RGBA")))
    if ruler is None:
        return None
    dx, dy = float(ruler.d[0]), float(ruler.d[1])
    return ("F" if dx >= 0 else "B", math.degrees(math.atan2(-dy, abs(dx))))


def theta_for(frame: Image.Image, direction: str, degrees: float) -> float:
    """Swing (rl convention, y down, positive = clockwise) that aims the ruler at the target."""
    ruler = rl.find_ruler(np.array(frame.convert("RGBA")))
    now = math.degrees(math.atan2(ruler.d[1], ruler.d[0]))
    sign = 1.0 if direction == "F" else -1.0
    target = math.degrees(math.atan2(-math.sin(math.radians(degrees)), sign * math.cos(math.radians(degrees))))
    return (target - now + 180.0) % 360.0 - 180.0


def fit_ruler(frame: Image.Image, label: str, theta: float | None) -> tuple[Image.Image, dict]:
    """Normalise the ruler to RULER_TARGET_LENGTH; when it cannot fit the 512 cell (the arm is
    already at the cell edge), use the longest length that fits, in 5 texel steps."""
    target = rl.RULER_TARGET_LENGTH
    result, info = rl.normalize_ruler(frame, target, label, force_theta=theta)
    while info.get("overflow") and target > 60:
        target -= 5.0
        result, info = rl.normalize_ruler(frame, target, label, force_theta=theta)
    info["fitted_target"] = target
    return result, info


def process_clip(name: str, config: dict, refs: tuple[float, float, float], report: list[dict], ruler_report: list[dict]) -> list[Image.Image] | None:
    raw_path = RAW_DIR / f"luz_attack_{config['raw']}_raw.png"
    if not raw_path.exists():
        print(f"{name}: {raw_path.name} not found, skipped (previous output kept)")
        return None
    raw = base.clean_key(Image.open(raw_path))
    sources = raw_frames(raw, raw_path.name, config["slots"])
    scale = SCALES[config["raw"]]
    mode = config["anchor"]
    ref = refs[0] if mode == "front" else refs[1]
    print(f"{name}: scale={scale:.3f} anchor={mode} (raw {raw_path.name})")
    idle_hair = base.idle_hair_luminance()
    frames = []
    for index, slot in enumerate(config["slots"]):
        label = f"{name}[{index}]"
        placed = place(sources[slot], scale, mode, ref, label)
        drawn = ruler_angle(placed)
        force = RULER_FORCE.get((name, index))
        theta = theta_for(placed, force[0], float(force[1])) if force else None
        frame, info = fit_ruler(placed, label, theta)
        doc_now = config["doc"][index]
        final_now = ruler_angle(frame)
        if (
            force is None and drawn and final_now and doc_now[0] == "F" and doc_now[0] == drawn[0] == final_now[0]
            and abs(drawn[1] - doc_now[1]) <= 20 and abs(final_now[1] - doc_now[1]) > AUTO_AIM_TOLERANCE
        ):
            force = doc_now
            theta = theta_for(placed, force[0], float(force[1]))
            frame, info = fit_ruler(placed, label, theta)
        info["repainted"] = force is not None
        ruler_report.append(info)
        # Hair luminance: lift only a clearly darker hair to the idle's.
        rgba = np.array(frame)
        lum = base.hair_luminance(rgba, rl.band_mask(frame))
        gain = idle_hair / lum
        if gain > 1.04:
            frame = base.match_hair(frame, idle_hair)
        frame = defringe(frame)
        mask = base.body_mask(frame)
        fl, fr, bottom = feet_span(mask)
        x0, y0, x1, y1 = base.alpha_bbox(frame)
        final = ruler_angle(frame)
        doc = config["doc"][index]
        print(
            f"  {index} slot {slot}: h={y1 - y0 + 1:3d} sole={bottom} feet=[{fl:.0f},{fr:.0f}] mid={(fl + fr) / 2:.0f} "
            f"body_cx={float(np.where(mask)[1].mean()):.0f} hair_gain={gain:.3f}"
        )
        print(
            f"     ruler drawn {drawn[0]}{drawn[1]:+.0f} final "
            f"{('%s%+.0f' % final) if final else '?'} doc {doc[0]}{doc[1]:+d} | {base.describe_ruler(info)}"
            + ("  REPAINTED" if force else "")
        )
        report.append({"clip": name, "index": index, "drawn": drawn, "final": final, "doc": doc, "info": info})
        frames.append(frame)
    return frames


def build_sheet(sheet_key: str, clip_frames: dict[str, list[Image.Image]], manifest: dict) -> None:
    layout = SHEET_LAYOUT[sheet_key]
    sheet_name = layout["file"]
    path = ASSET_DIR / sheet_name
    previous = Image.open(path).convert("RGBA") if path.exists() else None
    sheet = Image.new("RGBA", (OUT_COLUMNS * OUT_CELL, layout["rows"] * OUT_CELL), (0, 0, 0, 0))
    entry = manifest["sheets"][sheet_name]
    clips: dict[str, list[int]] = {}
    contact: dict[str, int] = {}
    phases = entry.get("phases", {})
    ticks = entry.get("frame_ticks_30fps", {})
    cursor = 0
    for name in layout["order"]:
        frames = clip_frames.get(name)
        if frames is None:
            frames = _old_frames(previous, entry["clips"][name])
        for i, frame in enumerate(frames):
            sheet.alpha_composite(frame, (((cursor + i) % OUT_COLUMNS) * OUT_CELL, ((cursor + i) // OUT_COLUMNS) * OUT_CELL))
        clips[name] = list(range(cursor, cursor + len(frames)))
        if name in clip_frames:
            config = CLIPS[name]
            contact[name] = config["contact"]
            phases[name] = config["phases"]
            ticks[name] = config["ticks"]
        elif name in entry.get("contact_frames", {}):
            contact[name] = entry["contact_frames"][name]
        cursor += len(frames)
    # Untouched clips (air sheet: plunge, plunge_land) keep their cells and indices.
    for name, indices in entry["clips"].items():
        if name in layout["order"]:
            continue
        for old_index in indices:
            cell = _old_frames(previous, [old_index])[0]
            sheet.alpha_composite(cell, ((old_index % OUT_COLUMNS) * OUT_CELL, (old_index // OUT_COLUMNS) * OUT_CELL))
        clips[name] = list(indices)
    sheet.save(path)
    entry["grid"] = {"columns": OUT_COLUMNS, "rows": layout["rows"], "cell_width": OUT_CELL, "cell_height": OUT_CELL}
    entry["clips"] = clips
    entry["contact_frames"] = contact
    entry["phases"] = phases
    entry["frame_ticks_30fps"] = ticks
    print(f"wrote {sheet_name}: {clips}")


def _old_frames(previous: Image.Image, indices: list[int]) -> list[Image.Image]:
    return [
        previous.crop(((i % 4) * OUT_CELL, (i // 4) * OUT_CELL, (i % 4 + 1) * OUT_CELL, (i // 4 + 1) * OUT_CELL))
        for i in indices
    ]


def main() -> int:
    manifest = json.loads(MANIFEST_PATH.read_text())
    refs = idle_reference()
    print(f"idle front foot x={refs[0]:.1f}, body centroid x={refs[1]:.1f}, feet midpoint x={refs[2]:.1f}")
    report: list[dict] = []
    ruler_report: list[dict] = []
    built: dict[str, dict[str, list[Image.Image]]] = {}
    for name, config in CLIPS.items():
        frames = process_clip(name, config, refs, report, ruler_report)
        if frames is not None:
            built.setdefault(config["sheet"], {})[name] = frames
    for sheet_key, clip_frames in built.items():
        # A partial rebuild (some raws missing) keeps the other clips of the sheet as they are.
        build_sheet(sheet_key, clip_frames, manifest)
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n")

    lengths = [info["after"] for info in ruler_report if info.get("after")]
    if lengths:
        print(f"ruler target {rl.RULER_TARGET_LENGTH:.0f} texels: final min {min(lengths):.1f} max {max(lengths):.1f}")
    bad = [info["label"] for info in ruler_report if not info.get("found") or info.get("overflow")]
    for label in bad:
        print(f"WARNING: ruler not normalised in {label}")
    return 2 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())

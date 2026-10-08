#!/usr/bin/env python3
"""Build Luz's run, idle, turn and skid clips from the Codex raw sheets.

Re-run with one command (PIL is not installed for the system python; `uv` is not
available here, so use a venv):

    python3 -m venv /tmp/luzvenv && /tmp/luzvenv/bin/pip install pillow numpy
    /tmp/luzvenv/bin/python tools/process_luz_run_turn_skid.py

(with uv: `uv run --with pillow --with numpy python tools/process_luz_run_turn_skid.py`).

Raw sheets live in tools/art_sources/luz/raw/ (gitignored), cells of 384x512,
facing right, see tools/art_sources/luz/prompts/run_turn_skid.md:

    luz_run_raw.png        1536x1536 (4x3)  -> run            (12 frames)
    luz_idle_raw.png       1536x1024 (4x2)  -> idle_breathing (8 frames)
    luz_turn_skid_raw.png  1536x1536 (4x3)  -> turn (slots 0-3), skid (slots 4-9)

A missing raw sheet is skipped and its previous output/manifest entry is kept.

Pipeline per sheet (cloned from process_luz_rest_ritual.py): clean the key
(magenta and red fringe), give every connected component to the raw cell holding
most of its pixels, scale, put the lowest opaque row on the shared feet row (413)
and anchor the alpha centroid to the existing idle frame, so feet and scale match
the untouched sheets (frame cell 512x512, on-screen scale body_height/331.5).
The last step of every frame is luz_ruler_length.normalize_ruler: Codex draws the
ruler (her sword) at a different length per sheet, so it is lengthened by script to
one length (RULER_TARGET_LENGTH) in every clip. A frame whose ruler would leave the
512x512 cell is kept as drawn and reported (exit code 2).
Writes assets/player/luz/luz_{run,idle,turn_skid}_sheet.png and the matching
sections of animation_manifest.json; it drops the superseded `run` (and, once the
new idle exists, `idle_breathing`) clips from luz_locomotion_sheet.png. Never run
process_luz_sheet.py, it would regenerate the old locomotion sheet.
"""

from __future__ import annotations

import json
import statistics
import sys
from collections import Counter
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import luz_ruler_length as rl  # noqa: E402
import process_luz_combat_hits as pch  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = ROOT / "tools" / "art_sources" / "luz" / "raw"
ASSET_DIR = ROOT / "assets" / "player" / "luz"
MANIFEST_PATH = ASSET_DIR / "animation_manifest.json"
LOCOMOTION_SHEET = "luz_locomotion_sheet.png"

RAW_CELL_W = 384
RAW_CELL_H = 512
OUT_CELL = pch.OUT_CELL_SIZE
OUT_COLUMNS = 4
FEET_ROW = pch.FEET_ROW
MIN_COMPONENT_PX = 400
# Planted-foot float allowed when flattening the run bob (output texels, 0.6 world px).
MAX_FLOAT = 4
# Standing-idle height (hair top to sole) of the existing idle frames, in output px.
IDLE_STANDING_HEIGHT = 331.5
# Raw standing-equivalent heights (hair top to sole) per sheet, measured on the v3
# sheets: skid slots 6-9 (standing) have a median of 383.5 raw px; the run frames
# (lean, ~92% of standing) have a median of 303 raw px, i.e. ~329 standing.
TURN_SKID_STANDING_HEIGHT = 383.5
# Run v2 (8 frames, the sheet the user accepted): Codex draws its standing-equivalent
# body at ~380 raw px (frame heights 315-363, median 339.5), so the same fixed scale
# as the first accepted integration (0.8724) is kept.
RUN_STANDING_HEIGHT = 380.0
TURN_SKID_SCALE = IDLE_STANDING_HEIGHT / TURN_SKID_STANDING_HEIGHT
RUN_SCALE = IDLE_STANDING_HEIGHT / RUN_STANDING_HEIGHT
# Head bob allowed in the run (output texels, 2 world px).
RUN_BOB_RANGE = 14

# scale None = measured from the sheet: IDLE_STANDING_HEIGHT / median frame height.
# The idle sheet is built first: hair_match reads its hair luminance.
SHEETS = {
    "luz_idle_sheet.png": {
        "raw_file": "luz_idle_raw.png",
        "raw_columns": 4,
        "raw_rows": 2,
        "scale": None,
        "clips": {"idle_breathing": [0, 1, 2, 4, 5, 6, 7]},
    },
    "luz_run_sheet.png": {
        "raw_file": "luz_run_raw_v2.png",
        "raw_columns": 4,
        "raw_rows": 2,
        "scale": RUN_SCALE,
        "clips": {"run": list(range(8))},
        # The Codex poses bob more than a Penitent-like run; bob_fix limits the
        # hair-top travel of the cycle to RUN_BOB_RANGE texels around its middle.
        "bob_range": RUN_BOB_RANGE,
        "body_anchor": True,
    },
    "luz_turn_skid_sheet.png": {
        "raw_file": "luz_turn_skid_raw.png",
        "raw_columns": 4,
        "raw_rows": 3,
        "scale": TURN_SKID_SCALE,
        # Turn: slot 0 (standing, one-hand trailing grip), slot 2 (low pivot, no ball
        # crouch), slot 3 (standing, trailing grip). Skid: only the braking slots 4-5
        # (5 held twice, so the arm pulls in softly); the hold part is the real idle
        # because Codex drew the standing slots 6-9 with puffier, darker hair. Slots
        # 2 and 6-11 are unused.
        "clips": {"turn": [1, 3], "skid": [4, 5, 5]},
        # Codex paints the hair 4-7% darker than the idle in the sway slots (and 8-10%
        # in the run sheet); lift it to the idle mean so the clips do not pop.
        "hair_match": [1, 3, 4, 5],
        "body_anchor": True,
        # Codex draws the standing slots with the same head but wider clothes and legs
        # than the idle (lower-body width +17% at the same height), so the stop looked
        # like a size pop into the idle: squeeze their body below the head to the idle
        # width (see squeeze_body). Slots 4-5 are the wide braking stance and stay as drawn.
        "body_match": [1, 3],
    },
}

def clean_key(raw: Image.Image) -> Image.Image:
    """Real alpha from a raw sheet: key flat magenta and peel red/magenta fringes."""
    a = np.array(raw.convert("RGBA")).astype(np.int16)
    r, g, b, al = a[..., 0], a[..., 1], a[..., 2], a[..., 3]

    # Flat magenta background (and its anti-aliased edge).
    m = np.minimum(r, b) - g
    al = np.where(m > 100, 0, al)
    soft = (m > 30) & (m <= 100) & (al > 0)
    al = np.where(soft, np.minimum(al, 255 * (100 - m) // 70), al)
    r = np.where(soft, np.maximum(0, r - m), r)
    b = np.where(soft, np.maximum(0, b - m), b)

    # Near-invisible halo pixels carry the key colour (red/pink); drop them.
    al = np.where(al <= 12, 0, al)

    # Saturated red/pink pixels touching transparency are key bleed, not art (the
    # real colours are navy, white, tan and orange-blond: green is never ~0).
    bad = (r > 140) & (g < 64) & (b < 130) & (r - g > 90)
    for _ in range(4):
        pad = np.pad(al > 0, 1)
        touches_clear = ~(pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])
        peel = bad & touches_clear & (al > 0)
        if not peel.any():
            break
        al = np.where(peel, 0, al)

    out = np.stack([r, g, b, al], axis=-1)
    out[al == 0] = 0
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")


def raw_frames(raw: Image.Image, name: str, columns: int, rows: int, wanted: list[int]) -> dict[int, Image.Image]:
    """Crop each wanted raw cell to the art owned by that cell (components may cross cells)."""
    if raw.size != (columns * RAW_CELL_W, rows * RAW_CELL_H):
        raise ValueError(f"{name}: expected {columns * RAW_CELL_W}x{rows * RAW_CELL_H}, got {raw.size}")
    labels, sizes, boxes = pch.label_components(raw.getchannel("A").tobytes(), raw.width, raw.height)
    votes: dict[int, Counter] = {}
    for index, label in enumerate(labels):
        if label and sizes[label] >= MIN_COMPONENT_PX:
            y, x = divmod(index, raw.width)
            cell = (y // RAW_CELL_H) * columns + min(x // RAW_CELL_W, columns - 1)
            votes.setdefault(label, Counter())[cell] += 1
    owned: dict[int, set[int]] = {cell: set() for cell in range(columns * rows)}
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


def alpha_bbox(im: Image.Image, threshold: int = 16) -> tuple[int, int, int, int]:
    mask = np.array(im.getchannel("A")) > threshold
    ys, xs = np.where(mask)
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


def centroid_x(im: Image.Image) -> float:
    mask = (np.array(im.getchannel("A")) > 8).sum(axis=0)
    return float((mask * np.arange(im.width)).sum() / max(mask.sum(), 1))


def idle_anchor_x() -> float:
    sheet = Image.open(ASSET_DIR / LOCOMOTION_SHEET).convert("RGBA")
    return centroid_x(sheet.crop((0, 0, OUT_CELL, OUT_CELL)))


def place(source: Image.Image, scale: float, anchor_x: float, label: str) -> Image.Image:
    w, h = max(1, round(source.width * scale)), max(1, round(source.height * scale))
    scaled = pch.unpremultiply(pch.premultiply(source).resize((w, h), pch.RESAMPLE))
    x0, y0, x1, y1 = alpha_bbox(scaled)
    scaled = scaled.crop((x0, y0, x1 + 1, y1 + 1))
    left = round(anchor_x - centroid_x(scaled))
    top = FEET_ROW - (scaled.height - 1)
    if left < 0 or top < 0 or left + scaled.width > OUT_CELL:
        raise ValueError(f"{label}: art does not fit output cell (left={left}, top={top}, size={scaled.size})")
    out = Image.new("RGBA", (OUT_CELL, OUT_CELL), (0, 0, 0, 0))
    out.alpha_composite(scaled, (left, top))
    return out


def bob_fix(frame: Image.Image, target_top: int) -> Image.Image:
    """Move the hair top of `frame` to `target_top` without moving the planted sole.

    Frames sitting lower than the target are first lifted by at most MAX_FLOAT
    texels (0.6 world px of planted-foot float); the remainder is a vertical
    stretch about the sole row (at most ~7%), so feet stay on the shared row.
    Frames above the target are squashed the same way (about 1%).
    """
    _, top, _, bottom = alpha_bbox(frame)
    height = bottom - top + 1
    lift = min(MAX_FLOAT, max(0, top - target_top))
    new_height = (bottom - lift) - target_top + 1
    if lift == 0 and new_height == height:
        return frame
    art = frame.crop((0, top, frame.width, bottom + 1))
    resized = pch.unpremultiply(pch.premultiply(art).resize((frame.width, new_height), pch.RESAMPLE))
    out = Image.new("RGBA", frame.size, (0, 0, 0, 0))
    out.alpha_composite(resized, (0, bottom - lift - (new_height - 1)))
    return out


def hair_mask(rgba: np.ndarray, exclude: np.ndarray | None = None) -> np.ndarray:
    """Hair-hued opaque pixels (blond to dark brown) in the head band of a frame."""
    r, g, b, a = (rgba[..., k].astype(np.int16) for k in range(4))
    mask = (a > 200) & (r > b + 25) & (r > g + 8) & (g > b + 5) & (r > 90)
    if exclude is not None:
        mask &= ~exclude
    rows = np.where(a > 200)[0]
    mask[rows.min() + 170 :] = False
    return mask


def hair_luminance(rgba: np.ndarray, exclude: np.ndarray | None = None) -> float:
    mask = hair_mask(rgba, exclude)
    lum = 0.3 * rgba[..., 0] + 0.59 * rgba[..., 1] + 0.11 * rgba[..., 2]
    return float(lum[mask].mean())


def idle_hair_luminance() -> float:
    sheet = np.array(Image.open(ASSET_DIR / "luz_idle_sheet.png").convert("RGBA"))
    cells = [sheet[: OUT_CELL, (i % OUT_COLUMNS) * OUT_CELL : (i % OUT_COLUMNS + 1) * OUT_CELL] for i in (0, 1, 2)]
    return statistics.mean(hair_luminance(cell) for cell in cells)


def match_hair(frame: Image.Image, target: float) -> Image.Image:
    """Scale the hair-hued pixels' RGB so their mean luminance equals `target`."""
    rgba = np.array(frame)
    ruler = rl.band_mask(frame)  # the ruler shares the hair hue; never lift it
    gain = target / hair_luminance(rgba, ruler)
    mask = hair_mask(rgba, ruler)
    rgba[..., :3][mask] = np.clip(rgba[..., :3][mask].astype(float) * gain, 0, 255).astype(np.uint8)
    print(f"    hair gain x{gain:.3f}")
    return Image.fromarray(rgba, "RGBA")


def body_mask(frame: Image.Image) -> np.ndarray:
    """Opaque pixels of the figure without the ruler."""
    return (np.array(frame.getchannel("A")) > 16) & ~rl.band_mask(frame)


def lower_body_width(mask: np.ndarray) -> float:
    """Mean row width of the body below the head and shoulders (rows from 30% of its height)."""
    rows = np.where(mask.any(axis=1))[0]
    top, bottom = int(rows.min()), int(rows.max())
    start = top + round(0.3 * (bottom - top))
    return float(mask[start : bottom + 1].sum() / (bottom - start + 1))


def idle_reference() -> tuple[float, float]:
    """(lower-body width, body centroid x) averaged over the idle clip's frames."""
    sheet = Image.open(ASSET_DIR / "luz_idle_sheet.png").convert("RGBA")
    widths, centres = [], []
    for slot in SHEETS["luz_idle_sheet.png"]["clips"]["idle_breathing"]:
        cell = sheet.crop(((slot % OUT_COLUMNS) * OUT_CELL, (slot // OUT_COLUMNS) * OUT_CELL, (slot % OUT_COLUMNS + 1) * OUT_CELL, (slot // OUT_COLUMNS + 1) * OUT_CELL))
        mask = body_mask(cell)
        widths.append(lower_body_width(mask))
        centres.append(float(np.where(mask)[1].mean()))
    return statistics.mean(widths), statistics.mean(centres)


def squeeze_body(frame: Image.Image, target_width: float) -> tuple[Image.Image, float]:
    """Squeeze the body below the head horizontally until its lower width is `target_width`.

    It only narrows: the factor is clamped to [0.8, 1]. The factor eases in from
    1 at 12% of the figure height (hair and face) to the full value at 30%
    (shoulders), about the body's own centre line, so the head keeps its size and
    the height and feet row stay exactly where they were.
    """
    mask = body_mask(frame)
    factor = min(1.0, max(0.8, target_width / lower_body_width(mask)))
    if factor >= 0.999:
        return frame, 1.0
    rgba = pch.premultiply(frame)
    arr = np.array(rgba).astype(np.float64)
    rows = np.where(mask.any(axis=1))[0]
    top, bottom = int(rows.min()), int(rows.max())
    height = bottom - top
    centre = float(np.where(mask)[1].mean())
    xs = np.arange(frame.width, dtype=np.float64)
    out = np.zeros_like(arr)
    for y in range(top, bottom + 1):
        t = min(1.0, max(0.0, ((y - top) / height - 0.12) / 0.18))
        k = 1.0 + (factor - 1.0) * t
        source = centre + (xs - centre) / k
        for channel in range(4):
            out[y, :, channel] = np.interp(source, xs, arr[y, :, channel], left=0.0, right=0.0)
    squeezed = pch.unpremultiply(Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA"))
    return squeezed, factor


def anchor_body(frame: Image.Image, target_centre: float) -> Image.Image:
    """Shift the frame sideways so the body (ruler excluded) centres on `target_centre`."""
    shift = round(target_centre - float(np.where(body_mask(frame))[1].mean()))
    if shift == 0:
        return frame
    out = Image.new("RGBA", frame.size, (0, 0, 0, 0))
    out.alpha_composite(frame, (shift, 0))
    if np.array(out.getchannel("A")).sum() != np.array(frame.getchannel("A")).sum():
        raise ValueError(f"body anchor shift {shift} leaves the cell")
    return out


def report_frame(label: str, frame: Image.Image) -> None:
    x0, y0, x1, y1 = alpha_bbox(frame)
    print(f"  {label}: height={y1 - y0 + 1:3d} feet_row={y1} x=[{x0},{x1}] centroid_x={centroid_x(frame):.1f}")


def describe_ruler(info: dict) -> str:
    if not info.get("found"):
        return "NOT FOUND"
    if info.get("overflow"):
        return f"OVERFLOW ({info['overflow']} texels leave the cell; kept at {info['before']:.1f})"
    tilt = f", tilt {info['tilt']:+.1f} deg" if info.get("tilt") else ""
    if info.get("clearance") is not None and info["clearance"] < rl.FLOOR_CLEARANCE:
        tilt += f", CLEARANCE ONLY {info['clearance']:.0f}"
    return f"{info['before']:.1f} -> {info['after']:.1f} (period {info['period']:.1f}{tilt})"


def build_sheet(sheet_name: str, config: dict, anchor_x: float, ruler_report: list[dict]) -> dict | None:
    raw_path = RAW_DIR / config["raw_file"]
    if not raw_path.exists():
        print(f"{sheet_name}: {raw_path.name} not found, skipped (previous output kept)")
        return None
    raw = clean_key(Image.open(raw_path))
    slots = sorted({slot for slots in config["clips"].values() for slot in slots})
    sources = raw_frames(raw, config["raw_file"], config["raw_columns"], config["raw_rows"], slots)
    scale = config["scale"]
    if scale is None:
        heights = [source.height for source in sources.values()]
        scale = IDLE_STANDING_HEIGHT / statistics.median(heights)
    print(f"{sheet_name}: scale={scale:.4f} (raw {config['raw_file']})")

    rows = config["raw_rows"]
    sheet = Image.new("RGBA", (OUT_COLUMNS * OUT_CELL, rows * OUT_CELL), (0, 0, 0, 0))
    placed = {slot: place(sources[slot], scale, anchor_x, f"{sheet_name}[{slot}]") for slot in slots}
    if config.get("body_match") or config.get("body_anchor"):
        idle_width, idle_centre = idle_reference()
    for slot in config.get("body_match", []):
        placed[slot], factor = squeeze_body(placed[slot], idle_width)
        print(f"    slot {slot}: body squeezed x{factor:.3f} to the idle lower width {idle_width:.1f}")
    if config.get("body_anchor"):
        # The alpha centroid used by place() includes the ruler, which differs per
        # sheet: centre the body itself on the idle's so clips never jump sideways.
        placed = {slot: anchor_body(frame, idle_centre) for slot, frame in placed.items()}
    if "bob_range" in config:
        tops = {slot: alpha_bbox(frame)[1] for slot, frame in placed.items()}
        middle = (min(tops.values()) + max(tops.values())) / 2
        half = config["bob_range"] / 2
        placed = {
            slot: bob_fix(frame, round(min(max(tops[slot], middle - half), middle + half)))
            for slot, frame in placed.items()
        }
    for slot in slots:
        frame = placed[slot]
        frame, info = rl.normalize_ruler(frame, rl.RULER_TARGET_LENGTH, f"{sheet_name}[{slot}]")
        ruler_report.append(info)
        if slot in config.get("hair_match", []):
            frame = match_hair(frame, idle_hair_luminance())
        sheet.alpha_composite(frame, ((slot % OUT_COLUMNS) * OUT_CELL, (slot // OUT_COLUMNS) * OUT_CELL))
        report_frame(f"slot {slot}", frame)
        print(f"    ruler {describe_ruler(info)}")
    sheet.save(ASSET_DIR / sheet_name)
    return {
        "grid": {"columns": OUT_COLUMNS, "rows": rows, "cell_width": OUT_CELL, "cell_height": OUT_CELL},
        "clips": {name: list(slots_) for name, slots_ in config["clips"].items()},
        "scale": round(scale, 4),
    }


def main() -> int:
    anchor_x = idle_anchor_x()
    manifest = json.loads(MANIFEST_PATH.read_text())
    sheets = manifest["sheets"]
    built = []
    ruler_report: list[dict] = []
    for sheet_name, config in SHEETS.items():
        entry = build_sheet(sheet_name, config, anchor_x, ruler_report)
        if entry is None:
            continue
        sheets[sheet_name] = {"grid": entry["grid"], "clips": entry["clips"]}
        built.append(sheet_name)

    # The new clips supersede the old locomotion ones; the catalog would otherwise
    # append both sets of frames to the same animation.
    locomotion_clips = sheets[LOCOMOTION_SHEET]["clips"]
    if "luz_run_sheet.png" in sheets:
        locomotion_clips.pop("run", None)
    if "luz_idle_sheet.png" in sheets:
        locomotion_clips.pop("idle_breathing", None)

    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Built {built or 'nothing'}; anchor_x={anchor_x:.1f}")
    lengths = [info["after"] for info in ruler_report if info.get("after")]
    if lengths:
        print(f"ruler target {rl.RULER_TARGET_LENGTH:.0f} texels: final min {min(lengths):.1f} max {max(lengths):.1f}")
    bad = [info["label"] for info in ruler_report if not info.get("found") or info.get("overflow")]
    for label in bad:
        print(f"WARNING: ruler not normalised in {label}")
    return 2 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())

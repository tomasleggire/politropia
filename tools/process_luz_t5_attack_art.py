#!/usr/bin/env python3
"""Rebuild Luz's T5 crouch, up, and air attack clips from raw art.

Unlike the earlier ground-combo source sheets, image generation occasionally
lets a ruler tip cross an invisible raw-cell boundary. This processor labels
the complete sheet first, then assigns each connected character silhouette to
the cell in which most of its pixels lie. That keeps the whole hand-held ruler
with its frame instead of slicing it at the nominal grid line.

Run after process_luz_sheet.py and process_luz_combat_hits.py, then before
paint_luz_ruler.py and generate_luz_slash_smears.py. Both output sheets and the
ruler track are rebuilt deterministically from the raw T5 sheets and the
pristine legacy air sheet.
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

import process_luz_combat_hits as pch
import process_luz_sheet as legacy

ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = ROOT / "tools" / "art_sources" / "luz" / "raw"
PREVIEW_DIR = ROOT / "tools" / "art_sources" / "luz" / "preview"
ASSET_DIR = ROOT / "assets" / "player" / "luz"
MANIFEST_PATH = ASSET_DIR / "animation_manifest.json"
TRACK_PATH = ASSET_DIR / "luz_ruler_track.json"

RAW_COLUMNS = 4
RAW_ROWS = 2
RAW_CELL_WIDTH = 384
RAW_CELL_HEIGHT = 512
OUT_CELL = pch.OUT_CELL_SIZE
OUT_COLUMNS = 4
FEET_ROW = pch.FEET_ROW
CANVAS_PADDING = pch.CANVAS_PADDING
CONTACT_FRAME = 3

CLIPS = {
    "crouch_attack": {
        "raw_file": "crouch_attack_t5_raw.png",
        "sheet": "luz_ground_combat_sheet.png",
        "scale": 0.90,
    },
    "up_attack": {
        "raw_file": "up_attack_t5_raw.png",
        "sheet": "luz_air_combat_sheet.png",
        "scale": 0.78,
    },
    "air_horizontal_attack": {
        "raw_file": "air_horizontal_attack_t5_raw.png",
        "sheet": "luz_air_combat_sheet.png",
        "scale": 0.78,
    },
}


def _font():
    try:
        return ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 20)
    except OSError:
        return ImageFont.load_default()


def _components(raw: Image.Image):
    alpha = raw.getchannel("A").tobytes()
    labels, sizes, boxes = pch.label_components(alpha, raw.width, raw.height)
    cell_counts = [[0] * (RAW_COLUMNS * RAW_ROWS) for _ in range(len(sizes) + 1)]
    for index, label in enumerate(labels):
        if label == 0:
            continue
        y, x = divmod(index, raw.width)
        cell = min(y // RAW_CELL_HEIGHT, RAW_ROWS - 1) * RAW_COLUMNS + min(x // RAW_CELL_WIDTH, RAW_COLUMNS - 1)
        cell_counts[label][cell] += 1
    return labels, sizes, boxes, cell_counts


def _frame_components(raw: Image.Image, name: str):
    if raw.size != (RAW_COLUMNS * RAW_CELL_WIDTH, RAW_ROWS * RAW_CELL_HEIGHT):
        raise ValueError(f"{name}: expected a 1536x1024 raw sheet, got {raw.size}")
    labels, sizes, boxes, counts = _components(raw)
    selected: list[int] = []
    for cell in range(RAW_COLUMNS * RAW_ROWS):
        candidates = [label for label in sizes if counts[label][cell] > 0]
        if not candidates:
            raise ValueError(f"{name}: cell {cell} has no alpha-connected art")
        main = max(candidates, key=lambda label: counts[label][cell])
        if sizes[main] < 5000:
            raise ValueError(f"{name}: cell {cell} main component is unexpectedly small ({sizes[main]} px)")
        if main in selected:
            raise ValueError(f"{name}: one connected component was selected for multiple cells")
        selected.append(main)

    frames = []
    for cell, main in enumerate(selected):
        x0, y0, x1, y1 = boxes[main]
        # Keep only the dominant silhouette. The generators sometimes spill
        # remnants of adjacent poses over a nominal cell; attaching nearby
        # fragments recreated a second ruler/ghost pose in the processed art.
        owned = {main}
        crop = raw.crop((x0, y0, x1 + 1, y1 + 1)).copy()
        pixels = crop.load()
        for cy in range(crop.height):
            for cx in range(crop.width):
                gx, gy = x0 + cx, y0 + cy
                label = labels[gy * raw.width + gx]
                if label not in owned:
                    pixels[cx, cy] = (0, 0, 0, 0)
        frames.append((crop, x0, y0, x1, y1, sizes[main]))
    return frames


def _process_frame(raw_frame: tuple, cell: int, clip_name: str, scale: float) -> Image.Image:
    source, x0, y0, x1, y1, _ = raw_frame
    scaled_w = max(1, round(source.width * scale))
    scaled_h = max(1, round(source.height * scale))
    scaled = pch.unpremultiply(pch.premultiply(source).resize((scaled_w, scaled_h), pch.RESAMPLE))

    raw_cell_x = (cell % RAW_COLUMNS) * RAW_CELL_WIDTH
    left = CANVAS_PADDING + round((x0 - raw_cell_x) * scale)
    top = FEET_ROW - (scaled_h - 1)
    if top < 0:
        crop_top = -top
        scaled = scaled.crop((0, crop_top, scaled_w, scaled_h))
        scaled_h -= crop_top
        top = 0
    if left + scaled_w > OUT_CELL:
        left = OUT_CELL - scaled_w
    if left < 0 or top < 0 or left + scaled_w > OUT_CELL or top + scaled_h > OUT_CELL:
        raise ValueError(f"{clip_name} frame {cell}: scaled art does not fit output cell")
    output = Image.new("RGBA", (OUT_CELL, OUT_CELL), (0, 0, 0, 0))
    output.alpha_composite(scaled, (left, top))
    return output


def _place_clip(sheet: Image.Image, start: int, frames: list[Image.Image], columns: int) -> None:
    for local_index, frame in enumerate(frames):
        cell = start + local_index
        col, row = cell % columns, cell // columns
        sheet.alpha_composite(frame, (col * OUT_CELL, row * OUT_CELL))


def _render_previews(sheet: Image.Image, clip: str, start: int) -> None:
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    (PREVIEW_DIR / ".gitignore").write_text("*\n")
    cols = OUT_COLUMNS
    onion = Image.new("RGBA", (OUT_CELL, OUT_CELL), (30, 30, 34, 255))
    for local in range(8):
        cell = start + local
        col, row = cell % cols, cell // cols
        frame = sheet.crop((col * OUT_CELL, row * OUT_CELL, (col + 1) * OUT_CELL, (row + 1) * OUT_CELL))
        if local < 7:
            frame.putalpha(frame.getchannel("A").point(lambda value: value * 35 // 100))
        onion.alpha_composite(frame)
    draw = ImageDraw.Draw(onion)
    draw.line((0, FEET_ROW, OUT_CELL, FEET_ROW), fill=(255, 0, 255, 220), width=1)
    draw.text((6, 6), clip, fill=(255, 255, 0, 255), font=_font())
    onion.save(PREVIEW_DIR / f"t5_onion__{clip}.png")

    frames = []
    for local in range(8):
        cell = start + local
        col, row = cell % cols, cell // cols
        frames.append(sheet.crop((col * OUT_CELL, row * OUT_CELL, (col + 1) * OUT_CELL, (row + 1) * OUT_CELL)))
    timeline = Image.new("RGBA", (OUT_CELL * 4, OUT_CELL * 2), (30, 30, 34, 255))
    for local, frame in enumerate(frames):
        timeline.alpha_composite(frame, ((local % 4) * OUT_CELL, (local // 4) * OUT_CELL))
    draw = ImageDraw.Draw(timeline)
    for local in range(8):
        draw.text(((local % 4) * OUT_CELL + 6, (local // 4) * OUT_CELL + 6), str(local), fill=(255, 255, 0, 255), font=_font())
    timeline.save(PREVIEW_DIR / f"t5_timeline__{clip}.png")


def _process_clip(name: str, config: dict) -> tuple[list[Image.Image], list[dict]]:
    raw_path = RAW_DIR / config["raw_file"]
    raw = Image.open(raw_path).convert("RGBA")
    raw_frames = _frame_components(raw, name)
    frames, records = [], []
    for local_index, raw_frame in enumerate(raw_frames):
        frame = _process_frame(raw_frame, local_index, name, config["scale"])
        measurement = pch.measure_ruler(frame)
        if local_index == CONTACT_FRAME and measurement.get("low_confidence"):
            raise ValueError(f"{name}: contact frame {local_index} has no reliable ruler measurement: {measurement}")
        frames.append(frame)
        records.append({"frame": local_index, **measurement})
    return frames, records


def main() -> int:
    manifest = json.loads(MANIFEST_PATH.read_text())
    track = json.loads(TRACK_PATH.read_text())

    ground_name = "luz_ground_combat_sheet.png"
    ground_section = manifest["sheets"][ground_name]
    ground_start = int(ground_section["clips"]["crouch_attack"][0])
    ground_rows = (ground_start + 8 + OUT_COLUMNS - 1) // OUT_COLUMNS
    ground = Image.open(ASSET_DIR / ground_name).convert("RGBA")
    resized_ground = Image.new("RGBA", (OUT_COLUMNS * OUT_CELL, ground_rows * OUT_CELL), (0, 0, 0, 0))
    resized_ground.alpha_composite(ground.crop((0, 0, ground.width, min(ground.height, resized_ground.height))))
    draw = ImageDraw.Draw(resized_ground)
    for cell in range(ground_start, ground_start + 8):
        col, row = cell % OUT_COLUMNS, cell // OUT_COLUMNS
        draw.rectangle((col * OUT_CELL, row * OUT_CELL, (col + 1) * OUT_CELL - 1, (row + 1) * OUT_CELL - 1), fill=(0, 0, 0, 0))
    crouch_frames, crouch_records = _process_clip("crouch_attack", CLIPS["crouch_attack"])
    _place_clip(resized_ground, ground_start, crouch_frames, OUT_COLUMNS)
    ground_section["grid"] = {"columns": OUT_COLUMNS, "rows": ground_rows, "cell_width": OUT_CELL, "cell_height": OUT_CELL}
    ground_section["clips"]["crouch_attack"] = list(range(ground_start, ground_start + 8))
    ground_section.setdefault("contact_frames", {})["crouch_attack"] = CONTACT_FRAME
    resized_ground.save(ASSET_DIR / ground_name)
    _render_previews(resized_ground, "crouch_attack", ground_start)
    track["clips"]["crouch_attack"] = {"contact_frame": CONTACT_FRAME, "frames": crouch_records}

    air_name = "luz_air_combat_sheet.png"
    air_section = manifest["sheets"][air_name]
    pristine = legacy.process_sheet(air_name, legacy.SHEETS[air_name], verbose=False)["out_sheet"]
    up_frames, up_records = _process_clip("up_attack", CLIPS["up_attack"])
    lateral_frames, lateral_records = _process_clip("air_horizontal_attack", CLIPS["air_horizontal_attack"])
    plunge_frames = list(air_section["clips"]["plunge"])
    land_frames = list(air_section["clips"]["plunge_land"])
    air_layout = {
        "up_attack": list(range(0, 8)),
        "air_horizontal_attack": list(range(8, 16)),
        "plunge": list(range(16, 20)),
        "plunge_land": list(range(20, 24)),
    }
    rebuilt_air = Image.new("RGBA", (OUT_COLUMNS * OUT_CELL, 6 * OUT_CELL), (0, 0, 0, 0))
    _place_clip(rebuilt_air, 0, up_frames, OUT_COLUMNS)
    _place_clip(rebuilt_air, 8, lateral_frames, OUT_COLUMNS)
    for clip_name, indices in (("plunge", plunge_frames), ("plunge_land", land_frames)):
        old_start = int(indices[0])
        new_start = air_layout[clip_name][0]
        for local_index in range(4):
            old_cell, new_cell = old_start + local_index, new_start + local_index
            old_col, old_row = old_cell % 4, old_cell // 4
            new_col, new_row = new_cell % OUT_COLUMNS, new_cell // OUT_COLUMNS
            source = pristine.crop((old_col * OUT_CELL, old_row * OUT_CELL, (old_col + 1) * OUT_CELL, (old_row + 1) * OUT_CELL))
            rebuilt_air.alpha_composite(source, (new_col * OUT_CELL, new_row * OUT_CELL))
    air_section["grid"] = {"columns": OUT_COLUMNS, "rows": 6, "cell_width": OUT_CELL, "cell_height": OUT_CELL}
    air_section["clips"] = air_layout
    air_section["contact_frames"] = {"up_attack": CONTACT_FRAME, "air_horizontal_attack": CONTACT_FRAME}
    rebuilt_air.save(ASSET_DIR / air_name)
    for clip_name, start in (("up_attack", 0), ("air_horizontal_attack", 8)):
        _render_previews(rebuilt_air, clip_name, start)
    track["clips"]["up_attack"] = {"contact_frame": CONTACT_FRAME, "frames": up_records}
    track["clips"]["air_horizontal_attack"] = {"contact_frame": CONTACT_FRAME, "frames": lateral_records}

    manifest_path = MANIFEST_PATH
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    TRACK_PATH.write_text(json.dumps(track, indent=2) + "\n")
    print(f"Rebuilt crouch_attack, up_attack, air_horizontal_attack as 8-frame clips; contact_frame={CONTACT_FRAME}.")
    for clip_name in CLIPS:
        clip = track["clips"][clip_name]
        contact = clip["frames"][CONTACT_FRAME]
        print(f"{clip_name}: frames={len(clip['frames'])} contact_tip={contact['tip']} grip={contact['grip']} axis={contact['axis_angle_deg']}deg")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

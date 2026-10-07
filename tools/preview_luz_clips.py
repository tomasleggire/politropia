#!/usr/bin/env python3
"""Render quality-gate previews of Luz's new clips (run, idle, turn, skid).

    /tmp/luzvenv/bin/python tools/preview_luz_clips.py [OUT_DIR]

(needs pillow + numpy and ffmpeg; see process_luz_run_turn_skid.py for the venv.)

Reads assets/player/luz/animation_manifest.json, so it previews exactly what the
game loads. Per clip it writes, into OUT_DIR (default: ./luz_previews, keep it
outside the repo):

    <clip>_game.gif / .mp4   body 48 px tall, upscaled x3, real playback fps
    <clip>_large.gif / .mp4  body ~200 px tall
    <clip>_contact.png       numbered frames with feet/centre guides + onion skin

Run also gets a scrolling floor at the real run speed so foot sliding is visible.
Frame times follow player.gd: run 28 fps, idle 8 fps, turn 4 frames in turn_time,
skid 6 frames in skid_brake_time + skid_hold_time. Turn is also rendered at the
0.12 s the art request recommends (`turn_0.12s`).
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
ASSET_DIR = ROOT / "assets" / "player" / "luz"
CELL = 512
FEET_ROW = 413
BODY_SRC_HEIGHT = 331.5  # standing idle height in source px = 48 world px
CROP = (60, 60, 452, 430)  # x0, y0, x1, y1 of the cell region worth showing
BG = (22, 22, 28, 255)
RUN_SPEED = 150.0  # px/s, player.gd run_max_speed

# name -> (manifest clip, fps, looping, scrolling floor speed in world px/s)
CLIPS = {
    "run": ("run", 28.0, True, RUN_SPEED),
    "idle": ("idle_breathing", 8.0, True, 0.0),
    "turn": ("turn", 4 / 0.06, False, 0.0),
    "turn_0.12s": ("turn", 4 / 0.12, False, 0.0),
    "skid": ("skid", 6 / 0.31, False, 0.0),
}


def font(size: int = 18):
    try:
        return ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", size)
    except OSError:
        return ImageFont.load_default()


def load_clip_frames(manifest: dict, clip: str) -> list[Image.Image]:
    for sheet_name, sheet in manifest["sheets"].items():
        if clip in sheet["clips"]:
            grid = sheet["grid"]
            image = Image.open(ASSET_DIR / sheet_name).convert("RGBA")
            frames = []
            for index in sheet["clips"][clip]:
                col, row = index % grid["columns"], index // grid["columns"]
                frames.append(image.crop((col * CELL, row * CELL, (col + 1) * CELL, (row + 1) * CELL)))
            return frames
    raise KeyError(f"clip '{clip}' is not in the manifest")


def render_video_frames(frames, fps, loop, floor_speed, body_px, upscale, seconds) -> list[Image.Image]:
    scale = body_px / BODY_SRC_HEIGHT * upscale
    crop = frames[0].crop(CROP).size
    size = (round(crop[0] * scale), round((FEET_ROW - CROP[1] + 60) * scale))
    feet_y = round((FEET_ROW - CROP[1]) * scale)
    out = []
    count = max(len(frames), round(seconds * fps)) if loop else len(frames) + round(0.5 * fps)
    tick_gap = 24 * upscale * body_px / 48
    for step in range(count):
        frame = frames[step % len(frames)] if loop else frames[min(step, len(frames) - 1)]
        canvas = Image.new("RGBA", size, BG)
        draw = ImageDraw.Draw(canvas)
        draw.line((0, feet_y, size[0], feet_y), fill=(90, 90, 110, 255), width=1)
        if floor_speed > 0:
            shift = (step / fps) * floor_speed * upscale * body_px / 48
            x = -(shift % tick_gap)
            while x < size[0]:
                draw.line((x, feet_y, x, feet_y + 8), fill=(150, 150, 170, 255), width=2)
                x += tick_gap
        sprite = frame.crop(CROP).resize((round(crop[0] * scale), round(crop[1] * scale)), Image.LANCZOS)
        canvas.alpha_composite(sprite, (0, feet_y - round((FEET_ROW - CROP[1]) * scale)))
        out.append(canvas.convert("RGB"))
    return out


def encode(frames: list[Image.Image], fps: float, stem: Path) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        for i, frame in enumerate(frames):
            frame.save(Path(tmp) / f"f{i:04d}.png")
        src = ["ffmpeg", "-y", "-loglevel", "error", "-framerate", f"{fps:.4f}", "-i", f"{tmp}/f%04d.png"]
        width = frames[0].width - frames[0].width % 2
        height = frames[0].height - frames[0].height % 2
        subprocess.run(src + ["-vf", f"crop={width}:{height}:0:0,format=yuv420p", "-c:v", "libx264", "-crf", "16", f"{stem}.mp4"], check=True)
        palette = f"{tmp}/p.png"
        subprocess.run(src + ["-vf", "palettegen", palette], check=True)
        subprocess.run(src + ["-i", palette, "-lavfi", "paletteuse", "-loop", "0", f"{stem}.gif"], check=True)


def contact_sheet(frames: list[Image.Image], dest: Path, title: str) -> None:
    cw, ch = CROP[2] - CROP[0], CROP[3] - CROP[1]
    columns = 4
    rows = (len(frames) + columns - 1) // columns
    sheet = Image.new("RGBA", (cw * columns, ch * rows + ch), BG)
    draw = ImageDraw.Draw(sheet)
    onion = Image.new("RGBA", (cw, ch), BG)
    for i, frame in enumerate(frames):
        cell = frame.crop(CROP)
        ox, oy = (i % columns) * cw, (i // columns) * ch
        sheet.alpha_composite(cell, (ox, oy))
        ghost = cell.copy()
        ghost.putalpha(ghost.getchannel("A").point(lambda v: v * 45 // 100))
        onion.alpha_composite(ghost)
        draw.text((ox + 6, oy + 4), f"{title} {i}", fill=(255, 255, 0, 255), font=font())
    onion_ox, onion_oy = 0, rows * ch
    sheet.alpha_composite(onion, (onion_ox, onion_oy))
    guide_x = 273 - CROP[0]
    for i in range(len(frames)):
        ox, oy = (i % columns) * cw, (i // columns) * ch
        draw.line((ox, oy + FEET_ROW - CROP[1], ox + cw, oy + FEET_ROW - CROP[1]), fill=(255, 0, 255, 200))
        draw.line((ox + guide_x, oy, ox + guide_x, oy + ch), fill=(255, 255, 0, 70))
    draw.line((0, onion_oy + FEET_ROW - CROP[1], cw, onion_oy + FEET_ROW - CROP[1]), fill=(255, 0, 255, 200))
    draw.line((guide_x, onion_oy, guide_x, onion_oy + ch), fill=(255, 255, 0, 70))
    draw.text((6, onion_oy + 4), "onion skin", fill=(255, 255, 0, 255), font=font())
    sheet.convert("RGB").save(dest)


def main() -> int:
    if shutil.which("ffmpeg") is None:
        print("ffmpeg is required", file=sys.stderr)
        return 1
    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd() / "luz_previews"
    out_dir.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((ASSET_DIR / "animation_manifest.json").read_text())
    for name, (clip, fps, loop, floor_speed) in CLIPS.items():
        frames = load_clip_frames(manifest, clip)
        contact_sheet(frames, out_dir / f"{name}_contact.png", name)
        for label, body_px, upscale in (("game", 48, 3), ("large", 200, 1)):
            video = render_video_frames(frames, fps, loop, floor_speed, body_px, upscale, 3.0)
            encode(video, fps, out_dir / f"{name}_{label}")
        print(f"{name}: {len(frames)} frames at {fps:.1f} fps ({len(frames) / fps:.3f} s per pass)")
    print(f"Previews in {out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

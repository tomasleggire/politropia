#!/usr/bin/env python3
"""Turn a luz_capture.gd recording into frames, close-ups and comparisons.

    python3 -m venv /tmp/luzvenv && /tmp/luzvenv/bin/pip install pillow numpy   # once
    /tmp/luzvenv/bin/python tools/capture/extract.py <out_dir> [~/Desktop/Caminar.mov]

<out_dir> holds run.avi and track.csv from tools/capture/luz_capture.gd. Writes:
    frames/f_NNNN.png        every 2nd full frame
    closeup/c_NNNN.png       Luz crop (120x90 world px, x6 nearest), every frame
    closeup.mp4              the close-up at 60 fps
    contact_*.png            contact sheets (run, skid, turn) of the close-up
    compare_*.mp4 (+ png)    Luz vs the Penitent (run, stop, turn; Penitent mirrored,
                             both scaled to the same body height), when Caminar.mov is given
Needs ffmpeg on PATH. The close-up crop follows Luz (track.csv), so ground motion
is the thing to look at: feet must not skate.
"""

from __future__ import annotations

import csv
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

OUT_W, OUT_H = 720, 540
LUZ_WIN = (120, 90)  # world px; 6x nearest => 720x540 (Luz 48 px = 288 px)
FEET_FRAC = 0.78
PENITENT_BODY_VIDEO_PX = 148.0  # Penitent body = 48 world px (3.0 video px per art px)
LUZ_FEET_OFFSET = 23.0  # collider half height below the node origin
# Sync points (Luz capture frame -> Caminar.mov frame; Caminar runs leftwards, mirrored).
COMPARE = {
    "run": (100, 40, 60),
    "stop": (204, 84, 60),
    "turn": (264, 14, 50),
}


def run(*cmd: str) -> None:
    subprocess.run(cmd, check=True)


def load_track(path: Path) -> list[dict]:
    with path.open() as handle:
        return list(csv.DictReader(handle))


def luz_crop(frame: Image.Image, row: dict) -> Image.Image:
    k = frame.width / 640.0  # track.csv is in base-viewport units (640x360)
    w, h = LUZ_WIN
    feet_y = float(row["sy"]) + LUZ_FEET_OFFSET
    left = round((float(row["sx"]) - w / 2) * k)
    top = round((feet_y - FEET_FRAC * h) * k)
    return frame.crop((left, top, left + round(w * k), top + round(h * k))).resize((OUT_W, OUT_H), Image.NEAREST)


def penitent_tracks(frames: list[Path]) -> tuple[np.ndarray, np.ndarray]:
    stack = np.stack([np.array(Image.open(f).convert("RGB"))[::2, ::2].astype(np.int16) for f in frames[::4]])
    background = np.median(stack, 0)
    xs, feet = [], []
    for f in frames:
        a = np.array(Image.open(f).convert("RGB"))[::2, ::2].astype(np.int16)
        ys, x = np.where(np.abs(a - background).sum(2) > 60)
        if len(x) < 30:
            xs.append(np.nan)
            feet.append(np.nan)
        else:
            xs.append(np.median(x) * 2)
            feet.append(np.percentile(ys, 98) * 2)
    return np.array(xs), np.array(feet)


def smooth(values: np.ndarray, k: int = 9) -> np.ndarray:
    pad = np.pad(values, k // 2, mode="edge")
    return np.convolve(pad, np.ones(k) / k, mode="valid")


def penitent_crop(frame: Image.Image, x: float, feet: float) -> Image.Image:
    scale = PENITENT_BODY_VIDEO_PX / 48.0  # video px per world px
    w, h = OUT_W / 6 * scale, OUT_H / 6 * scale  # window in video px (Luz is 6x)
    left, top = round(x - w / 2), round(feet - FEET_FRAC * h)
    out = frame.crop((left, top, round(left + w), round(top + h))).resize((OUT_W, OUT_H), Image.LANCZOS)
    return out.transpose(Image.FLIP_LEFT_RIGHT)


def contact_sheet(images: list[Image.Image], path: Path, columns: int = 6) -> None:
    tw, th = images[0].width // 2, images[0].height // 2
    thumbs = [i.resize((tw, th), Image.NEAREST) for i in images]
    rows = (len(thumbs) + columns - 1) // columns
    sheet = Image.new("RGB", (columns * tw, rows * th))
    for index, image in enumerate(thumbs):
        sheet.paste(image, ((index % columns) * tw, (index // columns) * th))
    sheet.save(path)


def encode(frames_dir: Path, pattern: str, out: Path) -> None:
    run("ffmpeg", "-v", "error", "-y", "-framerate", "60", "-i", str(frames_dir / pattern),
        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "16", str(out))


def main() -> int:
    out = Path(sys.argv[1])
    caminar = Path(sys.argv[2]).expanduser() if len(sys.argv) > 2 else None
    full = out / "full"
    for sub in (full, out / "frames", out / "closeup"):
        sub.mkdir(parents=True, exist_ok=True)
    run("ffmpeg", "-v", "error", "-y", "-i", str(out / "run.avi"), "-fps_mode", "passthrough", str(full / "f_%04d.png"))
    track = load_track(out / "track.csv")
    luz_images = []
    for index, row in enumerate(track):
        frame_path = full / f"f_{index + 1:04d}.png"
        if not frame_path.exists():
            break
        frame = Image.open(frame_path).convert("RGB")
        if index % 2 == 0:
            frame.save(out / "frames" / f"f_{index:04d}.png")
        crop = luz_crop(frame, row)
        ImageDraw.Draw(crop).text((8, 8), f"{index} {row['anim']}[{row['aframe']}] vx={row['vx']}", fill=(255, 255, 255))
        crop.save(out / "closeup" / f"c_{index:04d}.png")
        luz_images.append(crop)
    encode(out / "closeup", "c_%04d.png", out / "closeup.mp4")
    contact_sheet(luz_images[100:160:2], out / "contact_run.png")
    contact_sheet(luz_images[204:264:2], out / "contact_skid.png")
    contact_sheet(luz_images[264:324:2], out / "contact_turn.png")
    if caminar is not None and caminar.exists():
        cam = out / "caminar"
        cam.mkdir(exist_ok=True)
        run("ffmpeg", "-v", "error", "-y", "-i", str(caminar), "-fps_mode", "passthrough", str(cam / "f_%04d.png"))
        files = sorted(cam.glob("f_*.png"))
        xs, feet = penitent_tracks(files)
        xs = smooth(np.nan_to_num(xs, nan=float(np.nanmedian(xs))))
        feet = smooth(np.nan_to_num(feet, nan=float(np.nanmedian(feet))), 31)
        for name, (luz_start, pen_start, count) in COMPARE.items():
            pairs = out / f"cmp_{name}"
            pairs.mkdir(exist_ok=True)
            images = []
            for k in range(count):
                left = luz_images[min(luz_start + k, len(luz_images) - 1)]
                pn = pen_start + k
                right = penitent_crop(Image.open(files[pn]).convert("RGB"), xs[pn], feet[pn])
                both = Image.new("RGB", (OUT_W * 2, OUT_H))
                both.paste(left, (0, 0))
                both.paste(right, (OUT_W, 0))
                ImageDraw.Draw(both).text((OUT_W + 8, 8), f"Penitent n{pn} (mirrored)", fill=(255, 255, 255))
                both.save(pairs / f"p_{k:04d}.png")
                images.append(both)
            encode(pairs, "p_%04d.png", out / f"compare_{name}.mp4")
            contact_sheet(images[::4], out / f"compare_{name}.png", 2)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Give Luz's ruler (her sword) the same visible length in every clip.

Codex could not draw a consistent long ruler, so this module lengthens (or trims)
the drawn one by script: it finds the ruler in a processed 512x512 frame, fits its
axis, and rebuilds the free end along that axis from the ruler's own pixels. The
extension repeats one tick period of the body (so ticks and dots keep their
rhythm and the wood keeps its own cross-section and outline) and the original end
cap is moved to the new tip. Nothing outside the ruler's free end is touched.

Used by process_luz_run_turn_skid.py as the last step of every frame; run this
file directly to measure the rulers of a sheet:

    python3 tools/luz_ruler_length.py assets/player/luz/luz_run_sheet.png
"""

from __future__ import annotations

import math
import sys
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import process_luz_combat_hits as pch  # noqa: E402

# Visible ruler length (grip end to tip, along the axis) in output texels. Luz
# stands 331.5 texels tall (48 world px); the Penitent's sword is ~36 of his ~50
# px, so 0.65 of the standing height = 215 texels = ~31 world px.
RULER_TARGET_LENGTH = 215.0
RULER_TOLERANCE = 0.03
# The end cap (outline + a little wood) that is moved, not repeated.
CAP_LENGTH = 6.0
# Texels of body measured for the tick period before the cap.
PERIOD_WINDOW = 110.0
PERIOD_MIN = 7.0
PERIOD_MAX = 14.0
# The ruler may swing about the grip by up to this much (degrees, in TILT_STEP steps) when
# the straight extension would leave the cell or sink below the floor line.
MAX_TILT = 40.0
TILT_STEP = 0.5
EDGE_MARGIN = 2.0
GRIP_ZONE = 12.0  # texels from the grip where only ruler-coloured pixels are erased
FLOOR_SLACK = 6.0  # texels the ruler tip may sit below the feet row (~1 world px)
# Working canvas margin around the cell, so an overflow is measured, not clipped.
CANVAS_MARGIN = 400


@dataclass
class Ruler:
    origin: np.ndarray  # a point on the axis (x, y)
    d: np.ndarray  # unit vector grip -> tip
    n: np.ndarray  # unit normal
    t_grip: float
    t_tip: float
    s_lo: float
    s_hi: float

    @property
    def length(self) -> float:
        return self.t_tip - self.t_grip


def wood_mask(rgba: np.ndarray) -> np.ndarray:
    """Vectorised pch._is_ruler_pixel (wood fill and dark brown outline/ticks)."""
    r, g, b, a = (rgba[..., k].astype(np.int16) for k in range(4))
    order = (r > g) & (g > b)
    spread = (r - g >= 10) & (r - g <= 95) & (g - b >= 8) & (g - b <= 85)
    fill = (r >= 195) & (r <= 250) & (g >= 125) & (g <= 195) & (b >= 75) & (b <= 145)
    outline = (r >= 70) & (r <= 165) & (g >= 45) & (g <= 105) & (b >= 20) & (b <= 75)
    return (a > 128) & order & spread & (fill | outline)


def _pca(points: np.ndarray) -> tuple[np.ndarray, np.ndarray, float]:
    mean = points.mean(axis=0)
    cov = np.cov((points - mean).T)
    values, vectors = np.linalg.eigh(cov)
    return mean, vectors[:, 1], float(values[1] / max(values[0], 1e-6))


def find_ruler(rgba: np.ndarray) -> Ruler | None:
    """Locate the ruler: the largest very elongated wood-coloured component."""
    h, w = rgba.shape[:2]
    mask = wood_mask(rgba)
    labels, sizes, _ = pch.label_components((mask * 255).astype(np.uint8).tobytes(), w, h)
    label_array = np.array(labels, dtype=np.int32).reshape(h, w)
    best = None
    for label, size in sizes.items():
        if size < 150:
            continue
        ys, xs = np.nonzero(label_array == label)
        pts = np.stack([xs, ys], axis=1).astype(float)
        _, _, elongation = _pca(pts)
        if elongation >= 12.0 and (best is None or size > best[0]):
            best = (size, pts)
    if best is None:
        return None
    pts = best[1]
    # Trimmed axis fit: drop skin/hair pixels that merged into the component.
    for _ in range(3):
        mean, axis, _ = _pca(pts)
        normal = np.array([-axis[1], axis[0]])
        perp = (pts - mean) @ normal
        keep = np.abs(perp) <= max(3.0, 2.2 * np.percentile(np.abs(perp), 90))
        pts = pts[keep]
    mean, axis, _ = _pca(pts)
    normal = np.array([-axis[1], axis[0]])

    # Grip end = the end nearer to the rest of the body (the hand).
    opaque = rgba[..., 3] > 128
    ys, xs = np.nonzero(opaque & ~mask)
    others = np.stack([xs, ys], axis=1).astype(float)
    body = others.mean(axis=0) if len(others) else mean
    t = (pts - mean) @ axis
    ends = [mean + axis * t.min(), mean + axis * t.max()]
    if np.linalg.norm(ends[0] - body) > np.linalg.norm(ends[1] - body):
        axis, normal = -axis, -normal
    t = (pts - mean) @ axis
    s = (pts - mean) @ normal
    t_grip, t_tip = float(t.min()), float(t.max())
    body_zone = (t > t_tip - 70) & (t < t_tip - 12)
    zone = s[body_zone] if body_zone.any() else s
    return Ruler(mean, axis, normal, t_grip, t_tip, float(zone.min()) - 0.5, float(zone.max()) + 0.5)


def _sample(premult: np.ndarray, xs: np.ndarray, ys: np.ndarray) -> np.ndarray:
    """Bilinear sample of a premultiplied float RGBA image at (xs, ys) pixel centres."""
    h, w = premult.shape[:2]
    x0 = np.floor(xs - 0.5).astype(int)
    y0 = np.floor(ys - 0.5).astype(int)
    fx = (xs - 0.5 - x0)[..., None]
    fy = (ys - 0.5 - y0)[..., None]

    def at(ix: np.ndarray, iy: np.ndarray) -> np.ndarray:
        inside = ((ix >= 0) & (ix < w) & (iy >= 0) & (iy < h))[..., None]
        return np.where(inside, premult[np.clip(iy, 0, h - 1), np.clip(ix, 0, w - 1)], 0.0)

    return (
        at(x0, y0) * (1 - fx) * (1 - fy)
        + at(x0 + 1, y0) * fx * (1 - fy)
        + at(x0, y0 + 1) * (1 - fx) * fy
        + at(x0 + 1, y0 + 1) * fx * fy
    )


def _to_premult(rgba: np.ndarray) -> np.ndarray:
    out = rgba.astype(float)
    out[..., :3] *= out[..., 3:4] / 255.0
    return out


def _from_premult(premult: np.ndarray) -> np.ndarray:
    alpha = premult[..., 3:4]
    rgb = np.where(alpha > 0, premult[..., :3] * 255.0 / np.maximum(alpha, 1e-6), 0.0)
    out = np.concatenate([rgb, alpha], axis=-1)
    return np.clip(np.rint(out), 0, 255).astype(np.uint8)


def tick_period(premult: np.ndarray, ruler: Ruler, t_cap: float) -> float:
    """Repeat unit of the ticks: smallest lag that correlates almost as well as the best."""
    ts = np.arange(max(ruler.t_grip + 14.0, t_cap - PERIOD_WINDOW), t_cap - 1.0, 0.5)
    ss = np.linspace(ruler.s_lo, ruler.s_hi, 9)
    tt, sg = np.meshgrid(ts, ss, indexing="ij")
    xs = ruler.origin[0] + ruler.d[0] * tt + ruler.n[0] * sg
    ys = ruler.origin[1] + ruler.d[1] * tt + ruler.n[1] * sg
    colour = _sample(premult, xs, ys)
    signal = colour[..., :3].mean(axis=-1)  # (T, S): wood tone, ticks are the dark marks
    signal = signal - signal.mean(axis=0, keepdims=True)
    flat = signal.reshape(len(ts), -1)
    lags = np.arange(PERIOD_MIN, min(PERIOD_MAX, (t_cap - ruler.t_grip) / 2.2), 0.25)
    corr = []
    for lag in lags:
        k = int(round(lag * 2))
        a, b = flat[:-k], flat[k:]
        if len(a) < 8:
            corr.append(-1.0)
            continue
        corr.append(float((a * b).sum() / (np.sqrt((a * a).sum() * (b * b).sum()) + 1e-9)))
    corr = np.array(corr)
    if len(corr) == 0 or corr.max() <= 0.2:
        return float(PERIOD_MAX)
    # Local maxima near the best correlation; take the smallest lag.
    good = [i for i in range(1, len(corr) - 1) if corr[i] >= corr[i - 1] and corr[i] >= corr[i + 1] and corr[i] >= 0.92 * corr.max()]
    return float(lags[good[0]]) if good else float(lags[int(corr.argmax())])


def _rotate(v: np.ndarray, degrees: float) -> np.ndarray:
    c, s = math.cos(math.radians(degrees)), math.sin(math.radians(degrees))
    return np.array([c * v[0] - s * v[1], s * v[0] + c * v[1]])


def _rect(grip: np.ndarray, d: np.ndarray, n: np.ndarray, length: float, s_lo: float, s_hi: float) -> np.ndarray:
    return np.array([grip + d * u + n * s for u in (0.0, length) for s in (s_lo, s_hi)])


def _source_u(u: np.ndarray, length: float, delta: float, period: float) -> np.ndarray:
    """Position along the ORIGINAL ruler that supplies the new ruler's position u."""
    cap = length - CAP_LENGTH
    periodic = cap - period + np.mod(u - (cap - period), period)
    if delta >= 0:
        return np.where(u >= cap + delta, u - delta, np.where(u >= cap, periodic, u))
    return np.where(u >= cap + delta, u - delta, u)


def _normalize_once(frame: Image.Image, target: float, label: str) -> tuple[Image.Image, dict]:
    """Return (frame with the ruler at `target` texels, info).

    The free end is rebuilt along the ruler's own axis. Only when that would leave the
    cell, or sink the tip below the floor line, the whole ruler is swung about the
    grip by the smallest angle that fits (info["tilt"], degrees); a ruler that still
    cannot fit within MAX_TILT leaves the frame unchanged with info["overflow"] set."""
    rgba = np.array(frame.convert("RGBA"))
    ruler = find_ruler(rgba)
    if ruler is None:
        return frame, {"label": label, "found": False}
    h, w = rgba.shape[:2]
    pad = CANVAS_MARGIN
    canvas = np.zeros((h + 2 * pad, w + 2 * pad, 4), dtype=np.uint8)
    canvas[pad : pad + h, pad : pad + w] = rgba
    grip = ruler.origin + pad + ruler.d * ruler.t_grip
    length0 = ruler.length
    delta = target - length0
    t_cap_abs = ruler.t_tip - CAP_LENGTH
    period = tick_period(_to_premult(rgba), ruler, t_cap_abs)
    s_lo, s_hi = ruler.s_lo - 2.0, ruler.s_hi + 2.0
    info = {"label": label, "found": True, "before": length0, "period": period, "delta": delta, "overflow": 0, "tilt": 0.0}

    # Pixels that belong to the old ruler (erased before repainting).
    height, width = canvas.shape[:2]
    gy, gx = np.mgrid[0:height, 0:width]
    rel_x, rel_y = gx + 0.5 - grip[0], gy + 0.5 - grip[1]
    old_u = rel_x * ruler.d[0] + rel_y * ruler.d[1]
    old_s = rel_x * ruler.n[0] + rel_y * ruler.n[1]
    in_band = (old_s >= s_lo) & (old_s <= s_hi)
    r, g, b = (canvas[..., k].astype(np.int16) for k in range(3))
    # Near the hand only ruler-coloured pixels (wood, dark outline, soft edge) are
    # erased so the fist survives; further out everything inside the band is ruler.
    solid_like = wood_mask(canvas) | ((r < 130) & (r + g + b < 330) & (r >= b - 10) & (canvas[..., 3] > 128))
    soft_edge = (canvas[..., 3] > 0) & (canvas[..., 3] <= 128)
    ruler_like = solid_like | soft_edge
    wide_band = (old_s >= s_lo - 5.0) & (old_s <= s_hi + 5.0)
    old_ruler = (old_u >= -0.5) & (old_u <= length0 + 6.0) & (canvas[..., 3] > 0) & (
        (in_band & (old_u >= GRIP_ZONE)) | (wide_band & ((ruler_like & (old_u >= GRIP_ZONE)) | solid_like))
    )

    src = _to_premult(canvas)
    floor_limit = pch.FEET_ROW + pad + FLOOR_SLACK
    best = None
    for step in range(int(MAX_TILT / TILT_STEP) + 1):
        for sign in ((0,) if step == 0 else (1, -1)):
            theta = sign * step * TILT_STEP
            d2 = _rotate(ruler.d, theta)
            n2 = np.array([-d2[1], d2[0]])
            corners = _rect(grip, d2, n2, target, s_lo, s_hi)
            if corners[:, 0].min() < pad + EDGE_MARGIN or corners[:, 0].max() > pad + w - EDGE_MARGIN:
                continue
            if corners[:, 1].min() < pad + EDGE_MARGIN or corners[:, 1].max() > floor_limit:
                continue
            best = (theta, d2, n2)
            break
        if best:
            break
    if best is None:
        # Report the unconstrained overflow measured on the straight extension.
        corners = _rect(grip, ruler.d, ruler.n, target, s_lo, s_hi)
        info["overflow"] = int(max(0, pad + EDGE_MARGIN - corners[:, 0].min()) + max(0, corners[:, 0].max() - (pad + w - EDGE_MARGIN)) + max(0, corners[:, 1].max() - floor_limit))
        info["overflow"] = max(info["overflow"], 1)
        return frame, info

    theta, d2, n2 = best
    info["tilt"] = theta
    if theta == 0.0 and abs(delta) < 0.75:
        info["after"] = length0
        return frame, info

    rotated = theta != 0.0
    u_zone_start = 0.0 if rotated else length0 - CAP_LENGTH + min(delta, 0.0)
    erase = old_ruler & (old_u >= u_zone_start)
    base = src.copy()
    base[erase] = 0.0

    # Repaint zone in the new frame of reference.
    zone_start = 0.0 if rotated else length0 - CAP_LENGTH + min(delta, 0.0)
    corners = _rect(grip, d2, n2, target + 3.0, s_lo, s_hi)
    x0 = int(math.floor(corners[:, 0].min())) - 1
    x1 = int(math.ceil(corners[:, 0].max())) + 1
    y0 = int(math.floor(corners[:, 1].min())) - 1
    y1 = int(math.ceil(corners[:, 1].max())) + 1
    px_x, px_y = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
    rx, ry = px_x - grip[0], px_y - grip[1]
    u = rx * d2[0] + ry * d2[1]
    s = rx * n2[0] + ry * n2[1]
    zone = (u >= zone_start - 0.02) & (u <= target + 3.0) & (s >= s_lo) & (s <= s_hi)
    u_src = _source_u(u, length0, delta, period)
    sx = grip[0] + ruler.d[0] * u_src + ruler.n[0] * s
    sy = grip[1] + ruler.d[1] * u_src + ruler.n[1] * s
    painted = _sample(src, sx, sy)
    painted[~zone] = 0.0

    out = base.copy()
    region = out[y0 : y1 + 1, x0 : x1 + 1]
    # The ruler goes UNDER whatever body pixels remain (hand, legs).
    region += painted * (1.0 - region[..., 3:4] / 255.0)
    result = _from_premult(out)
    ys, xs = np.nonzero(result[..., 3] > 8)
    info["overflow"] = int(((xs < pad) | (xs >= pad + w) | (ys < pad) | (ys >= pad + h)).sum())
    if info["overflow"]:
        return frame, info
    cell = result[pad : pad + h, pad : pad + w]
    after = find_ruler(cell)
    info["after"] = after.length if after else None
    return Image.fromarray(cell, "RGBA"), info


def normalize_ruler(frame: Image.Image, target: float = RULER_TARGET_LENGTH, label: str = "") -> tuple[Image.Image, dict]:
    """Lengthen or trim the ruler to `target` visible texels (see _normalize_once). The
    visible length depends on how the fist covers the grip, so one corrective pass
    re-aims at the measured error."""
    result, info = _normalize_once(frame, target, label)
    after = info.get("after")
    if after is not None and abs(after - target) > 1.0 and not info.get("overflow"):
        retry, retry_info = _normalize_once(frame, target + (target - after), label)
        if retry_info.get("after") is not None and abs(retry_info["after"] - target) < abs(after - target):
            return retry, retry_info
    return result, info


def band_mask(frame: Image.Image, margin: float = 4.0) -> np.ndarray:
    """Pixels inside the ruler's rectangle (for other steps that must not touch it)."""
    rgba = np.array(frame.convert("RGBA"))
    mask = np.zeros(rgba.shape[:2], dtype=bool)
    ruler = find_ruler(rgba)
    if ruler is None:
        return mask
    gy, gx = np.mgrid[0 : rgba.shape[0], 0 : rgba.shape[1]]
    rx, ry = gx + 0.5 - ruler.origin[0], gy + 0.5 - ruler.origin[1]
    t = rx * ruler.d[0] + ry * ruler.d[1]
    s = rx * ruler.n[0] + ry * ruler.n[1]
    return (t >= ruler.t_grip - margin) & (t <= ruler.t_tip + margin) & (s >= ruler.s_lo - margin) & (s <= ruler.s_hi + margin)


def measure(frame: Image.Image) -> float | None:
    ruler = find_ruler(np.array(frame.convert("RGBA")))
    return ruler.length if ruler else None


def main() -> int:
    for arg in sys.argv[1:]:
        sheet = Image.open(arg).convert("RGBA")
        cell = 512
        for row in range(sheet.height // cell):
            for col in range(sheet.width // cell):
                crop = sheet.crop((col * cell, row * cell, (col + 1) * cell, (row + 1) * cell))
                if crop.getchannel("A").getbbox() is None:
                    continue
                length = measure(crop)
                print(f"{Path(arg).name} cell {row * (sheet.width // cell) + col}: {length if length is None else round(length, 1)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

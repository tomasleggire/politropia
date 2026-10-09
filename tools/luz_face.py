"""Face size of a Luz frame, used to give sheets without a standing pose the same body scale.

The face is the skin-coloured blob around the blue iris. Its geometric mean size (sqrt of
bounding width x height, in texels) is stable to about 3 percent across poses at the same
body scale, unlike the body height, which changes with the pose. Measure on frames that are
already at about the output scale (the eye search radius is in texels).
"""

from __future__ import annotations

import statistics

import numpy as np
from PIL import Image
from scipy import ndimage

RADIUS = 14


def _eye(a: np.ndarray) -> np.ndarray:
    r, g, b, al = (a[..., i].astype(int) for i in range(4))
    return (al > 200) & (b > 170) & (b - r > 50) & (g > 130)


def _skin(a: np.ndarray) -> np.ndarray:
    r, g, b, al = (a[..., i].astype(int) for i in range(4))
    return (al > 200) & (r > 205) & (g > 150) & (b > 115) & (r - b < 110) & (r - g < 55)


def face_size(frame: Image.Image) -> float | None:
    """sqrt(width x height) of the face blob, or None when the eye or the face is hidden."""
    a = np.array(frame.convert("RGBA"))
    eye = _eye(a)
    if not eye.any():
        return None
    lab, n = ndimage.label(eye)
    sizes = ndimage.sum(eye, lab, range(1, n + 1))
    ys, xs = np.where(lab == int(np.argmax(sizes)) + 1)
    cy, cx = int(ys.mean()), int(xs.mean())
    skin = ndimage.binary_closing(_skin(a) | eye, iterations=1)
    lab2, _ = ndimage.label(skin)
    win = lab2[max(0, cy - RADIUS) : cy + RADIUS + 1, max(0, cx - RADIUS) : cx + RADIUS + 1]
    ids = [v for v in np.unique(win) if v]
    if not ids:
        return None
    best = max(ids, key=lambda v: int((win == v).sum()))
    ys, xs = np.where(lab2 == best)
    return float(((xs.max() - xs.min() + 1) * (ys.max() - ys.min() + 1)) ** 0.5)


def median_face(frames: list[Image.Image]) -> float | None:
    values = [v for v in (face_size(f) for f in frames) if v is not None]
    return statistics.median(values) if values else None

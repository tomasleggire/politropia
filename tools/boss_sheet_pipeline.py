"""Shared helpers to turn raw Codex boss sheets into game sprite sheets.

Raw sheets are drawn on a magenta background in a regular grid. The helpers here
key the magenta, split the figures (connected components assigned to the grid cell
they mostly fall in), rescale every frame with ONE scale for the whole set, put the
lowest sole on a shared feet row, anchor the feet on the cell centre, and write the
sheet PNG plus the manifest entry that `BossAnimationCatalog` (and the older
`ArtemisAnimationCatalog`) read.

It is used by tools/process_artemis_sheets.py, tools/process_boombox_teacher_sheets.py and
tools/process_blind_beast_sheets.py, and is meant for La Hidra later. Nothing in here knows a boss by name.
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

# Luz is drawn so 331.5 source px become 48 px on screen: 0.1448 per source pixel at
# a 512 px reference cell. A boss sheet with a smaller cell scales the sprite node up.
LUZ_SPRITE_SCALE = 0.1448
LUZ_REFERENCE_CELL = 512.0
LUZ_HEIGHT = 48.0
ARTEMIS_HEIGHT = 56.0
MIN_COMPONENT_PX = 40
COLUMNS = 4


def sprite_scale_for(out_cell: int) -> float:
    """Sprite node scale that gives a processed cell Luz's on-screen pixel size."""
    return LUZ_SPRITE_SCALE * LUZ_REFERENCE_CELL / out_cell


def key_magenta(raw: Image.Image, low: int = 30, high: int = 100) -> np.ndarray:
    """Return float RGBA (0..255 alpha) with the magenta background keyed out.

    A pixel whose magenta excess (min(r, b) - g) is at most `low` is opaque, above `high`
    transparent, and in between partly transparent. A sheet whose art encloses pockets of
    a pinker background tone can lower `high` (the defaults are the shipped behaviour)."""
    arr = np.asarray(raw.convert("RGB")).astype(np.int32)
    r, g, b = arr[..., 0], arr[..., 1], arr[..., 2]
    m = np.minimum(r, b) - g
    alpha = np.clip((high - m) / float(high - low), 0.0, 1.0)
    alpha[m <= low] = 1.0
    alpha[m > high] = 0.0
    # remove the magenta tint from the partially transparent fringe
    fringe = (m > low) & (m <= high)
    out = arr.copy()
    out[..., 0] = np.where(fringe, np.maximum(0, r - m), r)
    out[..., 2] = np.where(fringe, np.maximum(0, b - m), b)
    rgba = np.dstack([out, alpha * 255.0]).astype(np.float32)
    return rgba


def split_frames(rgba: np.ndarray, cols: int, rows: int, name: str, needed: set[int] | None = None) -> list[np.ndarray | None]:
    """One cropped RGBA frame per grid cell (None for a cell outside `needed`)."""
    height, width = rgba.shape[:2]
    cell_w, cell_h = width / cols, height / rows
    mask = rgba[..., 3] > 20
    labels, count = ndimage.label(mask, structure=np.ones((3, 3)))
    owner: dict[int, int] = {}
    sizes = ndimage.sum(mask, labels, range(1, count + 1))
    centers = ndimage.center_of_mass(mask, labels, range(1, count + 1))
    for index in range(count):
        if sizes[index] < MIN_COMPONENT_PX:
            continue
        cy, cx = centers[index]
        owner[index + 1] = int(min(cy // cell_h, rows - 1)) * cols + int(min(cx // cell_w, cols - 1))
    frames = []
    for cell in range(cols * rows):
        keep = [label for label, c in owner.items() if c == cell]
        if not keep:
            if needed is not None and cell not in needed:
                frames.append(None)
                continue
            raise ValueError(f"{name}: cell {cell} has no art")
        sel = np.isin(labels, keep)
        ys, xs = np.where(sel)
        crop = rgba[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1].copy()
        crop[..., 3] = np.where(sel[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1], crop[..., 3], 0)
        frames.append(crop)
    return frames


def split_cells(rgba: np.ndarray, cols: int, rows: int, name: str, min_px: int) -> list[np.ndarray]:
    """Full raw cells (not cropped to the art) with stray specks removed, so frames
    keep their position relative to each other (effects, dissolves, props)."""
    height, width = rgba.shape[:2]
    cell_w, cell_h = width // cols, height // rows
    labels, count = ndimage.label(rgba[..., 3] > 20, structure=np.ones((3, 3)))
    sizes = ndimage.sum(np.ones_like(labels), labels, range(1, count + 1))
    centers = ndimage.center_of_mass(np.ones_like(labels), labels, range(1, count + 1))
    owner: dict[int, int] = {}
    for index in range(count):
        if sizes[index] >= min_px:
            cy, cx = centers[index]
            owner[index + 1] = int(min(cy // cell_h, rows - 1)) * cols + int(min(cx // cell_w, cols - 1))
    cells = []
    for cell in range(cols * rows):
        keep = [label for label, c in owner.items() if c == cell]
        if not keep:
            raise ValueError(f"{name}: cell {cell} has no art")
        r, c = divmod(cell, cols)
        block = rgba[r * cell_h : (r + 1) * cell_h, c * cell_w : (c + 1) * cell_w].copy()
        sel = np.isin(labels, keep)[r * cell_h : (r + 1) * cell_h, c * cell_w : (c + 1) * cell_w]
        block[..., 3] = np.where(sel, block[..., 3], 0)
        cells.append(block)
    return cells


def alpha_box(frame: np.ndarray, threshold: float = 20.0) -> tuple[int, int, int, int] | None:
    """(left, top, right, bottom) of the pixels above `threshold` alpha (right and bottom
    exclusive), or None when the frame is empty."""
    ys, xs = np.where(frame[..., 3] > threshold)
    if len(xs) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def union_box(frames: list[np.ndarray]) -> tuple[int, int, int, int] | None:
    """Smallest box that holds the art of every frame (None when all are empty)."""
    boxes = [box for box in (alpha_box(f) for f in frames) if box is not None]
    if not boxes:
        return None
    return min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes)


def require_box(frames: list[np.ndarray], label: str) -> tuple[int, int, int, int]:
    """`union_box`, but an error naming `label` (sheet and cells) when nothing is drawn."""
    box = union_box(frames)
    if box is None:
        raise ValueError(f"{label}: no drawn pixels (the cells are empty after keying); check the raw sheet")
    return box


def standing_height(frame: np.ndarray) -> float:
    """Height of the whole cropped frame (every pixel of art counts)."""
    return float(frame.shape[0])


def sole_bottom(frame: np.ndarray) -> int:
    """Lowest row holding a solid run of art (ignores stray fringe pixels)."""
    solid = (frame[..., 3] > 128).sum(axis=1)
    rows = np.where(solid >= 6)[0]
    return int(rows.max()) if len(rows) else frame.shape[0] - 1


def solid_top(frame: np.ndarray, min_width_fraction: float) -> int:
    """First row whose solid run is at least `min_width_fraction` of the widest row.

    A thin antenna, hair wisp or spark above the head is narrower than that and is
    skipped, so the result is the top of the massive part of the figure."""
    solid = (frame[..., 3] > 128).sum(axis=1)
    rows = np.where(solid >= max(6.0, solid.max() * min_width_fraction))[0]
    return int(rows.min()) if len(rows) else 0


def body_height(frame: np.ndarray, min_width_fraction: float) -> float:
    """Sole row minus `solid_top` plus one: the standing height without thin extras."""
    return float(sole_bottom(frame) - solid_top(frame, min_width_fraction) + 1)


def feet_center_x(frame: np.ndarray, bottom: int) -> float:
    band = max(6, int(frame.shape[0] * 0.12))
    sub = frame[max(0, bottom - band) : bottom + 1, :, 3] > 128
    xs = np.where(sub.any(axis=0))[0]
    weights = sub.sum(axis=0).astype(np.float64)
    return float((np.arange(len(weights)) * weights).sum() / max(weights.sum(), 1.0)) if len(xs) else frame.shape[1] / 2


def body_mask_bottom(arr: np.ndarray) -> tuple[int, float]:
    """Sole row and feet centre of the largest component (the body, not the sparkles)."""
    labels, count = ndimage.label(arr[..., 3] > 128, structure=np.ones((3, 3)))
    sizes = ndimage.sum(np.ones_like(labels), labels, range(1, count + 1))
    body = labels == (int(np.argmax(sizes)) + 1)
    solo = np.zeros_like(arr)
    solo[..., 3] = np.where(body, 255.0, 0.0)
    bottom = sole_bottom(solo)
    return bottom, feet_center_x(solo, bottom)


def scale_rgba(frame: np.ndarray, scale: float) -> np.ndarray:
    """Lanczos resize in premultiplied alpha (no dark or magenta fringes)."""
    premult = frame.copy()
    premult[..., :3] *= premult[..., 3:4] / 255.0
    img = Image.fromarray(premult.astype(np.uint8), "RGBA")
    img = img.resize((max(1, round(img.width * scale)), max(1, round(img.height * scale))), Image.LANCZOS)
    arr = np.asarray(img).astype(np.float32)
    a = arr[..., 3:4]
    arr[..., :3] = np.where(a > 0, np.minimum(arr[..., :3] * 255.0 / np.maximum(a, 1.0), 255.0), 0)
    return arr.astype(np.uint8)


def to_cell(
    frame: np.ndarray,
    scale: float,
    label: str,
    out_cell: int,
    feet_row: int,
    body_feet: bool = False,
    clamp_cell: int | None = None,
) -> Image.Image:
    """Scale `frame`, put its lowest sole on `feet_row` and its feet centre on the
    cell centre. `body_feet` measures the feet on the largest component only.

    `clamp_cell` is the cell width a frame that does not fit is nudged against
    (default `out_cell`). Artemis passes her 256 px value for the 384 px stag sheet
    to keep her shipped sheets byte-identical."""
    arr = scale_rgba(frame, scale)
    h, w = arr.shape[:2]
    if body_feet:
        bottom, cx = body_mask_bottom(arr.astype(np.float32))
    else:
        bottom = sole_bottom(arr.astype(np.float32))
        cx = feet_center_x(arr.astype(np.float32), bottom)
    left = round(out_cell / 2 - cx)
    top = feet_row - bottom
    cell = Image.new("RGBA", (out_cell, out_cell), (0, 0, 0, 0))
    if left < 0 or top < 0 or left + w > out_cell:
        # nudge to keep inside the cell rather than crop
        left = min(max(left, 0), (clamp_cell or out_cell) - w)
        top = max(top, 0)
        print(f"  note: {label} nudged to fit the cell ({w}x{h})")
    cell.alpha_composite(Image.fromarray(arr, "RGBA"), (left, top))
    return cell


def place_fixed(frames: list[np.ndarray], scale: float, out_cell: int, anchor_of, anchor_dst: tuple[float, float], label: str, anchor_idx: int = 0) -> list[Image.Image]:
    """Scale full raw cells and paste them with ONE offset, chosen so the anchor of
    frame `anchor_idx` lands on `anchor_dst`. Reports art that falls outside the cell."""
    scaled = [scale_rgba(f, scale) for f in frames]
    ax, ay = anchor_of(scaled[anchor_idx])
    left, top = round(anchor_dst[0] - ax), round(anchor_dst[1] - ay)
    out = []
    for index, arr in enumerate(scaled):
        full = Image.new("RGBA", (max(out_cell, arr.shape[1] + abs(left)) + out_cell, max(out_cell, arr.shape[0] + abs(top)) + out_cell), (0, 0, 0, 0))
        full.alpha_composite(Image.fromarray(arr, "RGBA"), (left + out_cell, top + out_cell))
        cell = full.crop((out_cell, out_cell, 2 * out_cell, 2 * out_cell))
        lost = int((arr[..., 3] > 20).sum()) - int((np.asarray(cell)[..., 3] > 20).sum())
        if lost > 30:
            print(f"  note: {label}[{index}] loses {lost} px outside the cell")
        out.append(cell)
    return out


def centered_cell(frame: np.ndarray, scale: float, out_cell: int, label: str) -> Image.Image:
    """A prop frame (not a figure): scaled and centred in the cell, no feet row."""
    arr = scale_rgba(frame, scale)
    h, w = arr.shape[:2]
    if w > out_cell or h > out_cell:
        raise ValueError(f"{label} is {w}x{h}, larger than its {out_cell} px cell")
    cell = Image.new("RGBA", (out_cell, out_cell), (0, 0, 0, 0))
    cell.alpha_composite(Image.fromarray(arr, "RGBA"), ((out_cell - w) // 2, (out_cell - h) // 2))
    return cell


def assemble_sheet(cells: list[Image.Image], out_cell: int, columns: int = COLUMNS) -> Image.Image:
    """Lay the cells out left to right, top to bottom on one transparent sheet."""
    rows = (len(cells) + columns - 1) // columns
    sheet = Image.new("RGBA", (columns * out_cell, rows * out_cell), (0, 0, 0, 0))
    for index, cell in enumerate(cells):
        sheet.alpha_composite(cell, ((index % columns) * out_cell, (index // columns) * out_cell))
    return sheet


def compact_clips(clips: dict[str, list[int]]) -> tuple[list[int], dict[str, list[int]]]:
    """Raw cell indices actually used (sorted) and the clips re-indexed to the
    compacted sheet, so unused raw cells never take space in the game sheet."""
    used = sorted({i for idx in clips.values() for i in idx})
    remap = {src: dst for dst, src in enumerate(used)}
    return used, {clip: [remap[i] for i in idx] for clip, idx in clips.items()}


def clip_contents(image: Image.Image, cell: int, clips: dict[str, list[int]]) -> dict[str, list[int]]:
    """Per clip, the [width, height] in sheet px of the box that holds its art in every frame
    of a sheet laid out by `assemble_sheet` (clips with no drawn pixel are left out)."""
    sheet = np.asarray(image).astype(np.float32)
    columns = image.width // cell
    contents = {}
    for clip, indices in clips.items():
        frames = []
        for i in indices:
            row, col = divmod(i, columns)
            frames.append(sheet[row * cell : (row + 1) * cell, col * cell : (col + 1) * cell])
        box = union_box(frames)
        if box is not None:
            contents[clip] = [box[2] - box[0], box[3] - box[1]]
    return contents


def manifest_entry(sheet: Image.Image, out_cell: int, clips: dict[str, list[int]], events: dict[str, int]) -> dict:
    """The manifest block of one sheet: grid, clips (compacted indices) and events."""
    columns = sheet.width // out_cell
    rows = sheet.height // out_cell
    return {
        "grid": {"columns": columns, "rows": rows, "cell_width": out_cell, "cell_height": out_cell},
        "clips": clips,
        "events": events,
    }


def write_manifest(path: Path, manifest: dict) -> None:
    path.write_text(json.dumps(manifest, indent=2) + "\n")


def write_preview(sheet: Image.Image, path: Path, out_cell: int, feet_row: int, sprite_scale: float, reference_heights: dict[str, float], label: str = "") -> None:
    """Sheet on a dark background with each cell's feet row and one reference line per
    entry of `reference_heights` (label -> on-screen px: Luz 48, Artemis 56...), drawn
    above the feet at that height divided by `sprite_scale`, so the scale can be judged."""
    bg = Image.new("RGBA", sheet.size, (24, 32, 56, 255))
    bg.alpha_composite(sheet)
    draw = ImageDraw.Draw(bg)
    colors = [(80, 220, 120, 255), (240, 200, 60, 255), (240, 90, 90, 255)]
    for row in range(sheet.height // out_cell):
        for col in range(sheet.width // out_cell):
            x0, y0 = col * out_cell, row * out_cell
            draw.rectangle([x0, y0, x0 + out_cell - 1, y0 + out_cell - 1], outline=(70, 80, 110, 255))
            y_feet = y0 + feet_row
            draw.line([x0, y_feet, x0 + out_cell, y_feet], fill=(255, 255, 255, 255))
            for color, (label, px) in zip(colors, reference_heights.items()):
                y_ref = y_feet - round(px / sprite_scale)
                draw.line([x0, y_ref, x0 + out_cell // 4, y_ref], fill=color, width=2)
                if col == 0 and row == 0:
                    draw.text((x0 + out_cell // 4 + 4, y_ref - 5), f"{label} {px:.0f}px", fill=color)
    if label:
        draw.text((6, sheet.height - 14), label, fill=(255, 255, 255, 255))
    bg.save(path)


def block_size(frame: np.ndarray, max_saturation: float = 0.15, min_value: int = 50, max_value: int = 225, closing: int = 15, min_fraction: float = 0.25) -> float:
    """sqrt(area) of the highest large grey block of a frame: a size reference that
    exists in every pose (standing, crouched, lying), unlike the standing height.

    Grey = low saturation and mid brightness (the boombox of El Profesor; shirt, trousers
    and shoes are warm or near black). The mask is closed (bridges the dark outlines
    between buttons and speakers), holes are filled, thin links (gloves, antenna) are
    cut by an opening, and among the components of at least `min_fraction` of the
    largest one the topmost is the block. sqrt(area) barely changes when it tilts."""
    rgb = frame[..., :3]
    solid = frame[..., 3] > 128
    top, low = rgb.max(-1), rgb.min(-1)
    saturation = (top - low) / np.maximum(top, 1)
    grey = solid & (saturation < max_saturation) & (top >= min_value) & (top <= max_value)
    mask = ndimage.binary_closing(grey, structure=np.ones((closing, closing)))
    mask = ndimage.binary_fill_holes(mask)
    mask = ndimage.binary_opening(mask, structure=np.ones((9, 9)))
    labels, count = ndimage.label(mask)
    if count == 0:
        return 0.0
    sizes = ndimage.sum(mask, labels, range(1, count + 1))
    boxes = ndimage.find_objects(labels)
    candidates = [i for i in range(count) if sizes[i] >= min_fraction * sizes.max()]
    best = min(candidates, key=lambda i: boxes[i][0].start)
    return float(np.sqrt(sizes[best]))


def color_block_size(
    frame: np.ndarray,
    targets: list[tuple[int, int, int]],
    tolerance: float = 55.0,
    opening: int = 5,
    min_fraction: float = 0.25,
) -> float:
    """sqrt(area) of the highest large block of a frame painted in one of `targets` (RGB):
    a size reference for a distinctive colour (El Topo's pink nose), as `block_size` is
    for a grey one. A pixel belongs to the block when it is solid and within `tolerance`
    (euclidean RGB distance) of a target; an opening drops specks and thin links; among
    the components of at least `min_fraction` of the largest one the topmost wins. 0.0
    when the colour is absent (the nose is hidden or not drawn yet)."""
    rgb = frame[..., :3].astype(np.float32)
    near = np.zeros(frame.shape[:2], dtype=bool)
    for target in targets:
        near |= np.sqrt(((rgb - np.array(target, dtype=np.float32)) ** 2).sum(-1)) <= tolerance
    mask = ndimage.binary_opening(near & (frame[..., 3] > 128), structure=np.ones((opening, opening)))
    labels, count = ndimage.label(mask)
    if count == 0:
        return 0.0
    sizes = ndimage.sum(mask, labels, range(1, count + 1))
    boxes = ndimage.find_objects(labels)
    candidates = [i for i in range(count) if sizes[i] >= min_fraction * sizes.max()]
    best = min(candidates, key=lambda i: boxes[i][0].start)
    return float(np.sqrt(sizes[best]))


def drop_specks(frame: np.ndarray, min_px: int) -> np.ndarray:
    """Frame with every connected component smaller than `min_px` made transparent
    (stray sparkle marks the art agent left near a figure)."""
    labels, count = ndimage.label(frame[..., 3] > 20, structure=np.ones((3, 3)))
    if count == 0:
        return frame
    sizes = ndimage.sum(np.ones_like(labels), labels, range(1, count + 1))
    keep = np.isin(labels, [i + 1 for i in range(count) if sizes[i] >= min_px])
    out = frame.copy()
    out[..., 3] = np.where(keep, out[..., 3], 0)
    return out

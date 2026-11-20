#!/usr/bin/env python3
"""Build La Hidra's sprite sheets from the raw Codex sheets.

Raw sheets live in tools/art_sources/hydra/raw/hydra_<sheet>_raw.png (magenta background,
1536 x 1024; the contract is docs/bosses/HYDRA_ANIMATIONS.md). Sheets arrive in batches: a
missing raw sheet is skipped with a message (exit 0) and an already processed sheet stays in
the manifest. Nothing is written when no raw sheet exists, and nothing is written unless every
requested sheet was built (the textures and the manifest never disagree after an error).

Sheets
  body, defeat   The figure (3 x 2 raw cells of 512 x 512). Scale: the content height of the
                 first cell (`idle[0]` of `body`, cell 0 of `defeat`) becomes BODY_HEIGHT on
                 screen. Every frame goes in a BODY_CELL px cell with the lowest coil on
                 BODY_FEET_ROW and the feet centre on the cell centre. The defeat sheet is
                 colour-matched to the body sheet so the Hydra keeps its colour when it dies.
  head_<kind>    One head (4 x 2 raw cells of 384 x 512). Scale: the content width of the
                 first cell (`idle[0]`) becomes HEAD_WIDTH on screen. Every frame goes in a
                 HEAD_CELL px cell and is aligned on a stable anchor, the centre of the eye (the
                 upper back of the skull when no eye shows), not on the bounding box: an open
                 jaw or a taller crest changes the box and would make the head jitter. The
                 first idle frame is centred on the cell, so the head sits on its origin.
  props          Six clips (stump, venom glob, venom pool, venom splash, two platforms), each
                 cropped with one shared box and centred in a 256 px cell at one factor, as
                 El Topo's props. The game rescales each one from the `content` box. The
                 `neck` cell (a straight horizontal neck piece) becomes a separate seamless
                 horizontal tile, `hydra_neck.png`: the centre of the piece followed by its
                 mirror image, padded with NECK_PAD transparent rows on each side. The
                 manifest records its on-screen thickness.

Keying (`key_background`): the magenta is removed only where it is background, that is
connected to the sheet border or an enclosed pocket of near-pure #FF00FF. Everything else stays
opaque, so a violet crest or a pink tongue never loses its colour. The antialiased silhouette
edge is un-mixed from the magenta against the outline colour, so no pink halo is left.

Margins: `shaders/sprite_glow.gdshader` samples up to 7 texels around every texel, so a cell
whose art comes closer than GLOW_MARGIN px to its edge would glow into the next cell of the
atlas. Every figure sheet is checked and the script stops when a cell is too tight.

Usage: python tools/process_hydra_sheets.py [--raw-dir DIR] [--out-dir DIR] [--preview DIR]
Needs Pillow, numpy and scipy (see the contract for the exact command).
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

import boss_sheet_pipeline as pipeline

ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = ROOT / "tools" / "art_sources" / "hydra" / "raw"
OUT_DIR = ROOT / "assets" / "enemies" / "hydra"

SPRITE_SCALE = pipeline.sprite_scale_for(256)  # the other bosses' on-screen pixel density, 0.2896
BODY_CELL = 640
BODY_FEET_ROW = 608
BODY_HEIGHT = 152.0  # on-screen px, lowest coil to the top of the body
BODY_STAND = BODY_HEIGHT / SPRITE_SCALE
HEAD_CELL = 288
HEAD_WIDTH = 56.0  # on-screen px, snout to the back of the skull
HEAD_STAND = HEAD_WIDTH / SPRITE_SCALE
HEAD_HEIGHT = 42.0  # on-screen px, only drawn in the preview
# Fallback anchor of a head frame without a visible eye: the left-most solid column within this
# many rows (processed px) below the first wide row; thin crest spikes above it are skipped.
ANCHOR_ROWS = 40
ANCHOR_TOP_FRACTION = 0.15
EYE_MIN_RED, EYE_MIN_GREEN, EYE_MAX_BLUE = 200, 160, 70  # the yellow of the eyes
EYE_MIN_PX = 5  # processed px; a squinting eye is still bigger than this
MIN_COMPONENT_PX = 150  # raw px; drops stray marks the art agent left near a figure
EFFECT_CELL = 256
EFFECT_SCALE = 0.5  # raw 384 x 512 cells fit a 256 px cell at this factor
EFFECT_MIN_COMPONENT_PX = 40
NECK_THICKNESS = 18.0  # on-screen px, outline included (the placeholder neck is 16)
NECK_OVERSAMPLE = 2  # tile texels per on-screen px across the neck: a 2x downscale stays smooth
NECK_PAD = 2  # transparent rows above and below the tile, so a repeat never bleeds
NECK_FILE = "hydra_neck.png"
NECK_CELL = 0
# Neck roots: the three rounded stumps on the body's right side. Each one is the right-most
# point of the silhouette in its band of rows; the root sits STUB_INSET px inside it, in the
# middle of the stump, where the game starts the neck (behind the body).
STUB_ROWS_BELOW_FEET = 160  # rows above this distance from the feet row are searched
STUB_WINDOW = 40  # a stump tip is the profile maximum within this many rows
STUB_MIN_GAP = 25
STUB_INSET = 35
GLOW_MARGIN = 8  # texels of empty border a cell needs (the glow shader reaches 7)
GLOW_ALPHA = 8  # alpha above which a pixel counts as art for the margin check

# Keying. The background is #FF00FF with a little noise (distance below 25 in the raw sheets).
MAGENTA = np.array([255.0, 0.0, 255.0], dtype=np.float32)
OUTLINE = np.array([27.0, 15.0, 21.0], dtype=np.float32)  # measured median of the dark outline
PURE_DISTANCE = 70.0  # RGB distance to MAGENTA below which a pixel is certainly background
POCKET_MIN_PX = 6  # an enclosed pure pocket at least this big is background (not noise)
FRINGE_PX = 3  # width of the antialiased edge, from the background outwards
UNMIX_RESIDUAL = 70.0  # an edge pixel off the outline-magenta line by more is real art colour
DEFRINGE_ALPHA = 128  # after the resize, pixels fainter than this take the outline colour

# Colour match of the defeat sheet to the body sheet (CIE Lab, scale greens only).
GREEN_MAX_A = -5.0  # greens have a negative a*
GREEN_MIN_L = 15.0  # the dark outline is not scale green
GREEN_SOFT = 4.0  # a* range over which the match fades in
MATCH_GAIN = (0.7, 1.6)  # limits of the per-channel contrast change

BODY_SHEETS = {
    "body": {"grid": (3, 2), "clips": {"idle": [0, 1, 2, 3], "roar": [4, 5]}},
    "defeat": {"grid": (3, 2), "clips": {"defeat": [0, 1, 2, 3, 4, 5]}},
}
HEAD_CLIPS = {"idle": [0, 1, 2], "telegraph": [3], "attack": [4, 5], "roar": [6], "dazed": [7]}
HEAD_SHEETS = {f"head_{kind}": {"grid": (4, 2), "clips": HEAD_CLIPS} for kind in ("biter", "sweeper", "spitter")}
PROPS = {
    "grid": (4, 2),
    "clips": {"stump": [1], "venom_glob": [2], "venom_pool": [3, 4], "venom_splash": [5], "platform": [6], "platform_alt": [7]},
}
NECK_ROOT_SHEET = "body"  # the sheet whose stumps the necks grow from
# Outline: every piece is brought to one outer-contour thickness (game px, the 640 x 360 unit), the
# value of El Topo and El Profesor. Codex draws each sheet at its own size, so the same prompt gave
# a body 2x bolder than the heads. A piece within OUTLINE_TOLERANCE of the target is left alone.
OUTLINE_TARGET = 1.15
OUTLINE_TOLERANCE = 0.2
OUTLINE_BAND = 4.0  # game px of silhouette depth the thickness is measured in
OUTLINE_DISTANCE = 40.0  # RGB distance to OUTLINE below which a pixel is outline (dark scale shading is not)
OUTLINE_ITERATIONS = 4
OUTLINE_MAX_SHARE = 0.85  # an erosion never takes more than this share of the measured outline
# How the game scales each prop: (fit, px). WIDTH fits the width, CONTAIN the larger side.
PROP_FIT = {
    "stump": ("width", 38.0), "venom_glob": ("contain", 19.0), "venom_pool": ("width", 88.0),
    "venom_splash": ("width", 88.0), "platform": ("width", 160.0), "platform_alt": ("width", 160.0),
}
NECK_LINE = 1.2  # game px of outline along each edge of the neck tile
REFERENCE_CELL = 0  # the cell whose content size sets the scale of a figure sheet
COLOUR_REFERENCE = {"defeat": "body"}  # sheet -> the sheet whose greens it must match


def raw_path(sheet: str) -> Path:
    return RAW_DIR / f"hydra_{sheet}_raw.png"


def sheet_file(sheet: str) -> str:
    return f"hydra_{sheet}_sheet.png"


# -- Keying and colour ----------------------------------------------------------------------------

def key_background(raw: Image.Image) -> np.ndarray:
    """Float RGBA with the magenta background removed and nothing else.

    Background = pixels near pure #FF00FF that are connected to the border of the sheet, plus
    enclosed pockets of them (between the loops of a tail, the spikes of a crest). Every other
    pixel is opaque, whatever its hue, so violet and pink art survives. Within FRINGE_PX of the
    background the silhouette edge is a mix of the outline colour and magenta: the share of
    magenta becomes transparency and the colour becomes the outline's again (no pink halo)."""
    rgb = np.asarray(raw.convert("RGB")).astype(np.float32)
    pure = np.linalg.norm(rgb - MAGENTA, axis=-1) < PURE_DISTANCE
    labels, count = ndimage.label(pure)
    background = np.zeros(pure.shape, dtype=bool)
    if count:
        sizes = ndimage.sum(pure, labels, range(1, count + 1))
        on_border = set(np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]])).tolist())
        keep = [i + 1 for i in range(count) if (i + 1) in on_border or sizes[i] >= POCKET_MIN_PX]
        background = np.isin(labels, keep)
    share_alpha, out, unmixed = pipeline.unmix_fringe(rgb, background, OUTLINE, FRINGE_PX, UNMIX_RESIDUAL)
    alpha = np.ones(pure.shape, dtype=np.float32)
    alpha[background] = 0.0
    alpha[unmixed] = share_alpha[unmixed]
    return np.dstack([out, alpha * 255.0]).astype(np.float32)


def rgb_to_lab(rgb: np.ndarray) -> np.ndarray:
    linear = rgb / 255.0
    linear = np.where(linear > 0.04045, ((linear + 0.055) / 1.055) ** 2.4, linear / 12.92)
    xyz = linear @ np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]]).T
    xyz = xyz / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16.0 / 116.0)
    return np.stack([116.0 * f[..., 1] - 16.0, 500.0 * (f[..., 0] - f[..., 1]), 200.0 * (f[..., 1] - f[..., 2])], axis=-1)


def lab_to_rgb(lab: np.ndarray) -> np.ndarray:
    fy = (lab[..., 0] + 16.0) / 116.0
    f = np.stack([fy + lab[..., 1] / 500.0, fy, fy - lab[..., 2] / 200.0], axis=-1)
    xyz = np.where(f**3 > 0.008856, f**3, (f - 16.0 / 116.0) / 7.787) * np.array([0.95047, 1.0, 1.08883])
    linear = xyz @ np.linalg.inv(np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])).T
    linear = np.clip(linear, 0.0, 1.0)
    srgb = np.where(linear > 0.0031308, 1.055 * linear ** (1.0 / 2.4) - 0.055, 12.92 * linear)
    return np.clip(srgb * 255.0, 0.0, 255.0)


def green_weight(lab: np.ndarray) -> np.ndarray:
    """1 on the scale greens, fading to 0 on the ochre, the outline and the tongue."""
    fade = np.clip((GREEN_MAX_A - lab[..., 1]) / GREEN_SOFT, 0.0, 1.0)
    return fade * (lab[..., 0] > GREEN_MIN_L)


def green_stats(rgba: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    solid = rgba[..., 3] > 250
    lab = rgb_to_lab(rgba[..., :3][solid])
    greens = lab[green_weight(lab) >= 1.0]
    if len(greens) == 0:
        raise ValueError("no scale green found to match")
    return greens.mean(axis=0), greens.std(axis=0)


def match_greens(rgba: np.ndarray, reference: np.ndarray) -> np.ndarray:
    """`rgba` with its scale greens moved to the mean and spread (per Lab channel) of the
    greens of `reference`. The ochre belly, the outline and the tongue are left alone: the
    change fades in with how green a pixel is."""
    mean, spread = green_stats(rgba)
    ref_mean, ref_spread = green_stats(reference)
    gain = np.clip(ref_spread / np.maximum(spread, 1e-3), *MATCH_GAIN)
    lab = rgb_to_lab(rgba[..., :3])
    matched = ref_mean + (lab - mean) * gain
    weight = green_weight(lab)[..., None]
    out = rgba.copy()
    out[..., :3] = lab_to_rgb(lab + (matched - lab) * weight)
    return out


def keyed_sheet(sheet: str) -> np.ndarray:
    """The keyed raw sheet, colour-matched when the sheet has a colour reference."""
    keyed = key_background(Image.open(raw_path(sheet)))
    reference = COLOUR_REFERENCE.get(sheet)
    if reference is None:
        return keyed
    if not raw_path(reference).exists():
        print(f"  note: {sheet} not colour-matched, {raw_path(reference).name} not found")
        return keyed
    return match_greens(keyed, key_background(Image.open(raw_path(reference))))


def load_frames(sheet: str, grid: tuple[int, int], clips: dict[str, list[int]]) -> dict[int, np.ndarray]:
    """The cropped RGBA frame of every raw cell a clip uses, by raw cell number, stray specks
    removed. A cell that holds nothing after that is an error, never a silent gap."""
    cols, rows = grid
    needed = {i for clip in clips.values() for i in clip}
    frames = pipeline.split_frames(keyed_sheet(sheet), cols, rows, sheet, needed)
    cleaned = {}
    for cell in sorted(needed):
        frame = pipeline.drop_specks(frames[cell], MIN_COMPONENT_PX)
        if pipeline.alpha_box(frame) is None:
            raise ValueError(f"{sheet}: cell {cell} is empty once specks under {MIN_COMPONENT_PX} px are removed")
        cleaned[cell] = frame
    return cleaned


def defringe(image: Image.Image) -> Image.Image:
    """The resize leaves a few very faint edge pixels whose colour is quantisation noise (some
    pink). The art is outlined all round, so a faint edge pixel is outline colour."""
    arr = np.array(image)
    faint = (arr[..., 3] > 0) & (arr[..., 3] < DEFRINGE_ALPHA)
    arr[faint, :3] = OUTLINE.astype(np.uint8)
    return Image.fromarray(arr, "RGBA")


def outline_thickness(frame: np.ndarray, game_per_px: float) -> float:
    """Outer outline thickness of a figure, in game px: the dark pixels within OUTLINE_BAND game px
    of the silhouette, divided by the length of the silhouette. `game_per_px` is how many game px
    one pixel of `frame` becomes."""
    frame = np.pad(frame, ((1, 1), (1, 1), (0, 0)))  # a tight crop touches its own border
    solid = frame[..., 3] > 128
    depth = ndimage.distance_transform_edt(solid)
    edge = (solid & (depth <= 1.0)).sum()
    dark = solid & (np.linalg.norm(frame[..., :3] - OUTLINE, axis=-1) < OUTLINE_DISTANCE) & (depth <= OUTLINE_BAND / game_per_px)
    return float(dark.sum()) / max(int(edge), 1) * game_per_px


def restyle_outline(frame: np.ndarray, radius: float, keep_padding: bool) -> np.ndarray:
    """`frame` with its silhouette grown (radius > 0: a stroke in the outline colour) or eroded
    (radius < 0: outline pixels removed) by |radius| px, the edge antialiased. The resize that
    follows keeps it smooth. Padded by the growth so nothing is cut; `keep_padding` False crops back
    to the original shape (full cells), True crops to the art (cropped figure frames)."""
    pad = int(np.ceil(abs(radius))) + 2
    arr = np.pad(frame, ((pad, pad), (pad, pad), (0, 0)))
    alpha = arr[..., 3] / 255.0
    solid = alpha > 0.5
    if radius > 0:
        reach = ndimage.distance_transform_edt(~solid)
        grown = np.maximum(alpha, np.clip(radius - reach + 0.5, 0.0, 1.0))
        stroke = grown > alpha
        arr[stroke, :3] = OUTLINE
        arr[..., 3] = grown * 255.0
    else:
        inside = ndimage.distance_transform_edt(solid)
        arr[..., 3] = alpha * np.clip(inside + radius + 0.5, 0.0, 1.0) * 255.0
    if not keep_padding:
        return arr[pad:-pad, pad:-pad]
    box = pipeline.alpha_box(arr)
    return arr[box[1] : box[3], box[0] : box[2]] if box else arr


def solve_radius(frame: np.ndarray, game_per_px: float, keep_padding: bool, label: str) -> tuple[float, float]:
    """(radius, measured) that bring the outline of `frame` to OUTLINE_TARGET. The thickness does
    not fall one-to-one with the erosion (the silhouette shrinks too), so the radius is refined by
    measuring the restyled frame again. radius 0 when the outline is within OUTLINE_TOLERANCE."""
    measured = outline_thickness(frame, game_per_px)
    radius = 0.0
    current = measured
    for _ in range(OUTLINE_ITERATIONS):
        if abs(OUTLINE_TARGET - current) < OUTLINE_TOLERANCE / 2:
            break
        radius += (OUTLINE_TARGET - current) / game_per_px
        if radius < 0 and -radius > OUTLINE_MAX_SHARE * measured / game_per_px:
            raise ValueError(f"{label}: the outline would need an erosion of {-radius:.1f} px, too much of its {measured / game_per_px:.1f} px to remove without eating colour")
        current = outline_thickness(restyle_outline(frame, radius, keep_padding), game_per_px)
    if abs(OUTLINE_TARGET - measured) < OUTLINE_TOLERANCE:
        return 0.0, measured
    return radius, measured


def retarget_outline(frames: dict[int, np.ndarray], game_per_px: float, label: str) -> dict[int, np.ndarray]:
    """Brings the outline of a figure sheet to OUTLINE_TARGET: solved on the reference cell, the
    same radius applied to every frame (so the frames stay consistent with each other)."""
    radius, measured = solve_radius(frames[REFERENCE_CELL], game_per_px, True, label)
    if radius == 0.0:
        print(f"  {label}: outline {measured:.2f} game px, kept")
        return frames
    print(f"  {label}: outline {measured:.2f} game px -> {OUTLINE_TARGET} ({'grown' if radius > 0 else 'eroded'} {abs(radius):.1f} px)")
    return {cell: restyle_outline(frame, radius, True) for cell, frame in frames.items()}


def check_margins(image: Image.Image, cell: int, label: str) -> None:
    """Stops when the art of a cell comes closer than GLOW_MARGIN px to the cell edge."""
    alpha = np.asarray(image)[..., 3] > GLOW_ALPHA
    tight = []
    for row in range(image.height // cell):
        for col in range(image.width // cell):
            block = alpha[row * cell : (row + 1) * cell, col * cell : (col + 1) * cell]
            ys, xs = np.where(block)
            if len(xs) == 0:
                continue
            gap = min(xs.min(), ys.min(), cell - 1 - xs.max(), cell - 1 - ys.max())
            if gap < GLOW_MARGIN:
                tight.append(f"cell {row * (image.width // cell) + col} ({gap} px)")
    if tight:
        raise ValueError(f"{label}: art closer than {GLOW_MARGIN} px to the cell edge, the glow would bleed: {', '.join(tight)}")


# -- Body ---------------------------------------------------------------------------------------

def build_body(sheet: str, spec: dict, preview: Path | None) -> tuple[dict, dict[str, Image.Image]]:
    frames = load_frames(sheet, spec["grid"], spec["clips"])
    raw_height = pipeline.standing_height(frames[REFERENCE_CELL])
    frames = retarget_outline(frames, BODY_STAND / raw_height * SPRITE_SCALE, sheet)
    raw_height = pipeline.standing_height(frames[REFERENCE_CELL])
    scale = BODY_STAND / raw_height
    print(f"  {sheet}: cell {REFERENCE_CELL} is {raw_height:.0f} raw px tall -> scale {scale:.4f}, {BODY_STAND:.0f} px in the cell")
    used, clips = pipeline.compact_clips(spec["clips"])
    cells = [pipeline.to_cell(frames[src], scale, f"{sheet}[{src}]", BODY_CELL, BODY_FEET_ROW, True) for src in used]
    image = defringe(pipeline.assemble_sheet(cells, BODY_CELL))
    check_margins(image, BODY_CELL, sheet)
    extra = {"neck_roots": neck_roots(cells, clips, sheet)} if sheet == NECK_ROOT_SHEET else {}
    if preview is not None:
        references = {"Luz": pipeline.LUZ_HEIGHT, "Artemis": pipeline.ARTEMIS_HEIGHT, "Hydra": BODY_HEIGHT}
        preview.mkdir(parents=True, exist_ok=True)
        pipeline.write_preview(image, preview / sheet_file(sheet), BODY_CELL, BODY_FEET_ROW, SPRITE_SCALE, references, f"{sheet} scale {scale:.3f}")
    return {**pipeline.manifest_entry(image, BODY_CELL, clips, {}), **extra}, {sheet_file(sheet): image}


def stump_tips(cell: Image.Image, label: str) -> list[tuple[float, float]]:
    """The three stump tips (x, y in cell px) of a body frame, lowest first (the tier order of
    the heads: low, mid, high). The right-most silhouette point of each stump."""
    alpha = np.asarray(cell)[: BODY_FEET_ROW - STUB_ROWS_BELOW_FEET, :, 3] > 128
    right = np.array([np.where(row)[0].max() if row.any() else -1 for row in alpha], dtype=np.float64)
    smooth = np.convolve(right, np.ones(9) / 9.0, mode="same")
    peaks: list[int] = []
    for y in range(STUB_WINDOW // 2, len(smooth) - 1):
        if smooth[y] > 0 and smooth[y] >= smooth[max(0, y - STUB_WINDOW) : y + STUB_WINDOW + 1].max() and (not peaks or y - peaks[-1] > STUB_MIN_GAP):
            peaks.append(y)
    if len(peaks) != 3:
        raise ValueError(f"{label}: found {len(peaks)} neck stumps on the right side of the body, expected 3 (rows {peaks})")
    return [(float(right[y]), float(y)) for y in reversed(peaks)]


def neck_roots(cells: list[Image.Image], clips: dict[str, list[int]], label: str) -> dict[str, list[list[list[float]]]]:
    """Per clip and frame, the three neck roots in on-screen px of the right-facing art,
    relative to the feet centre (the sprite origin): x to the right, y down."""
    roots = {}
    for clip, indices in clips.items():
        frames = []
        for index in indices:
            tips = stump_tips(cells[index], f"{label}[{index}]")
            frames.append([[round((x - STUB_INSET - BODY_CELL / 2) * SPRITE_SCALE, 2), round((y - BODY_FEET_ROW) * SPRITE_SCALE, 2)] for x, y in tips])
        roots[clip] = frames
    return roots


# -- Heads --------------------------------------------------------------------------------------

def eye_centre(frame: np.ndarray) -> tuple[float, float] | None:
    """Centre of the yellow eye (the largest connected patch of pure yellow), or None when the
    frame shows no eye. The belly ochre is darker and less saturated, the tongue pink."""
    r, g, b = frame[..., 0], frame[..., 1], frame[..., 2]
    yellow = (r > EYE_MIN_RED) & (g > EYE_MIN_GREEN) & (b < EYE_MAX_BLUE) & (frame[..., 3] > 200)
    labels, count = ndimage.label(yellow)
    if count == 0:
        return None
    sizes = ndimage.sum(yellow, labels, range(1, count + 1))
    if sizes.max() < EYE_MIN_PX:
        return None
    ys, xs = np.where(labels == int(np.argmax(sizes)) + 1)
    return float(xs.mean()), float(ys.mean())


def head_anchor(frame: np.ndarray) -> tuple[float, float]:
    """The point of a right-facing head that must not move between frames. The eye: it stays on
    the skull in every pose, while the crest and the jaw change the silhouette (a taller crest
    in the telegraph moved the top-based anchor by 12 screen px). A frame without a visible eye
    falls back to the upper back of the skull: the top of its massive part (thin crest spikes
    skipped) and the left-most solid column in the rows just below it."""
    eye = eye_centre(frame)
    if eye is not None:
        return eye
    top = pipeline.solid_top(frame, ANCHOR_TOP_FRACTION)
    band = frame[top : top + ANCHOR_ROWS, :, 3] > 128
    columns = np.where(band.sum(axis=0) >= 2)[0]
    left = int(columns.min()) if len(columns) else 0
    return float(left), float(top)


def place_on_anchor(arr: np.ndarray, anchor: tuple[float, float], target: tuple[float, float], label: str) -> Image.Image:
    """`arr` in a HEAD_CELL px cell with its anchor on `target`; art that leaves the cell is
    cut and reported."""
    left, top = round(target[0] - anchor[0]), round(target[1] - anchor[1])
    canvas = Image.new("RGBA", (HEAD_CELL * 3, HEAD_CELL * 3), (0, 0, 0, 0))
    canvas.alpha_composite(Image.fromarray(arr, "RGBA"), (left + HEAD_CELL, top + HEAD_CELL))
    cell = canvas.crop((HEAD_CELL, HEAD_CELL, 2 * HEAD_CELL, 2 * HEAD_CELL))
    lost = int((arr[..., 3] > 20).sum()) - int((np.asarray(cell)[..., 3] > 20).sum())
    if lost > 30:
        print(f"  note: {label} loses {lost} px outside the cell")
    return cell


def head_cells(frames: dict[int, np.ndarray], used: list[int], scale: float, sheet: str) -> list[Image.Image]:
    """Every frame scaled by `scale` and put on one anchor point. The first idle frame is
    centred on the cell and fixes that point."""
    scaled = {src: pipeline.scale_rgba(frames[src], scale) for src in used}
    anchors = {src: head_anchor(scaled[src].astype(np.float32)) for src in used}
    first = scaled[REFERENCE_CELL]
    ax, ay = anchors[REFERENCE_CELL]
    target = (HEAD_CELL / 2 - first.shape[1] / 2 + ax, HEAD_CELL / 2 - first.shape[0] / 2 + ay)
    return [place_on_anchor(scaled[src], anchors[src], target, f"{sheet}[{src}]") for src in used]


def build_head(sheet: str, spec: dict, preview: Path | None) -> tuple[dict, dict[str, Image.Image]]:
    frames = load_frames(sheet, spec["grid"], spec["clips"])
    raw_width = float(frames[REFERENCE_CELL].shape[1])
    frames = retarget_outline(frames, HEAD_STAND / raw_width * SPRITE_SCALE, sheet)
    raw_width = float(frames[REFERENCE_CELL].shape[1])
    scale = HEAD_STAND / raw_width
    print(f"  {sheet}: cell {REFERENCE_CELL} is {raw_width:.0f} raw px wide -> scale {scale:.4f}, {HEAD_STAND:.0f} px in the cell")
    used, clips = pipeline.compact_clips(spec["clips"])
    image = defringe(pipeline.assemble_sheet(head_cells(frames, used, scale, sheet), HEAD_CELL))
    check_margins(image, HEAD_CELL, sheet)
    write_head_preview(image, sheet, preview, f"{sheet} scale {scale:.3f}")
    entry = pipeline.manifest_entry(image, HEAD_CELL, clips, {})
    manifest = {
        "sheet": sheet_file(sheet),
        "sprite_scale": round(SPRITE_SCALE, 4),
        "grid": entry["grid"],
        "clips": entry["clips"],
        "content": pipeline.clip_contents(image, HEAD_CELL, entry["clips"]),
    }
    return manifest, {sheet_file(sheet): image}


def write_head_preview(image: Image.Image, sheet: str, preview: Path | None, label: str) -> None:
    """Cells on a dark background with the origin cross and the 56 x 42 px box of the placeholder."""
    if preview is None:
        return
    preview.mkdir(parents=True, exist_ok=True)
    bg = Image.new("RGBA", image.size, (24, 32, 56, 255))
    bg.alpha_composite(image)
    draw = ImageDraw.Draw(bg)
    half_w, half_h = HEAD_STAND / 2, HEAD_HEIGHT / SPRITE_SCALE / 2
    for row in range(image.height // HEAD_CELL):
        for col in range(image.width // HEAD_CELL):
            x0, y0 = col * HEAD_CELL, row * HEAD_CELL
            cx, cy = x0 + HEAD_CELL / 2, y0 + HEAD_CELL / 2
            draw.rectangle([x0, y0, x0 + HEAD_CELL - 1, y0 + HEAD_CELL - 1], outline=(70, 80, 110, 255))
            draw.rectangle([cx - half_w, cy - half_h, cx + half_w, cy + half_h], outline=(80, 220, 120, 255))
            draw.line([cx - 8, cy, cx + 8, cy], fill=(255, 255, 255, 255))
            draw.line([cx, cy - 8, cx, cy + 8], fill=(255, 255, 255, 255))
    draw.text((6, image.height - 14), label, fill=(255, 255, 255, 255))
    bg.save(preview / sheet_file(sheet))


# -- Props and neck -----------------------------------------------------------------------------

def neck_tile(piece: np.ndarray) -> np.ndarray:
    """A seamless horizontal tile from a straight neck piece: its centre half followed by the
    mirror image of that half, so the left and right edges are the same column. Cut to the
    drawn rows, flipped vertically (the game's neck runs from the right shoulder to a head on its
    left, and a Line2D that runs left draws its texture upside down, so the belly would end up on
    top), scaled to NECK_THICKNESS on screen and padded with NECK_PAD transparent rows on each side."""
    width = piece.shape[1]
    centre = piece[:, width // 4 : width - width // 4]
    tile = np.concatenate([centre, centre[:, ::-1]], axis=1)
    box = pipeline.alpha_box(tile)
    if box is None:
        raise ValueError("props: the neck cell has no drawn pixels")
    tile = tile[box[1] : box[3]][::-1]  # a Line2D running left draws its texture upside down
    scale = (NECK_THICKNESS * NECK_OVERSAMPLE - 2 * NECK_PAD) / tile.shape[0]
    scaled = pipeline.scale_rgba(tile, scale)
    lines = max(1, round(NECK_LINE * NECK_OVERSAMPLE))
    scaled[:lines, :, :3] = OUTLINE.astype(np.uint8)  # the same outline along both edges, seamless
    scaled[-lines:, :, :3] = OUTLINE.astype(np.uint8)
    scaled[:lines, :, 3] = 255
    scaled[-lines:, :, 3] = 255
    return np.pad(scaled, ((NECK_PAD, NECK_PAD), (0, 0), (0, 0)))


def write_neck(piece: np.ndarray, preview: Path | None) -> tuple[dict, dict[str, Image.Image]]:
    image = defringe(Image.fromarray(neck_tile(piece), "RGBA"))
    if preview is not None:
        preview.mkdir(parents=True, exist_ok=True)
        strip = Image.new("RGBA", (image.width * 6, image.height), (24, 32, 56, 255))
        for i in range(6):
            strip.alpha_composite(image, (i * image.width, 0))
        strip.save(preview / NECK_FILE)
    entry = {
        "texture": NECK_FILE,
        "thickness": round(image.height / NECK_OVERSAMPLE, 2),
        "tile": [image.width, image.height],
    }
    return entry, {NECK_FILE: image}


def retarget_prop(cells: list[np.ndarray], clip: str, indices: list[int]) -> list[np.ndarray]:
    """Brings the outline of one prop clip to OUTLINE_TARGET as it is drawn in game: the game
    scales the clip's content box to its hazard (PROP_FIT), which sets the game px per raw px."""
    fit, size = PROP_FIT[clip]
    box = pipeline.require_box([cells[i] for i in indices], f"props clip '{clip}' (cells {indices})")
    extent = (box[2] - box[0]) if fit == "width" else max(box[2] - box[0], box[3] - box[1])
    game_per_px = size / extent
    radius, measured = solve_radius(cells[indices[0]][box[1] : box[3], box[0] : box[2]], game_per_px, True, f"props {clip}")
    if radius == 0.0:
        print(f"  props {clip}: outline {measured:.2f} game px, kept")
        return cells
    print(f"  props {clip}: outline {measured:.2f} game px -> {OUTLINE_TARGET} ({'grown' if radius > 0 else 'eroded'} {abs(radius):.1f} px)")
    out = list(cells)
    for i in indices:
        out[i] = restyle_outline(cells[i], radius, False)
    return out


def build_props(spec: dict, preview: Path | None) -> tuple[dict, dict, dict[str, Image.Image]]:
    """The props entry (every clip cropped with one shared box, centred in a 256 px cell), the
    neck entry and the images to write."""
    cols, rows = spec["grid"]
    cells = pipeline.split_cells(key_background(Image.open(raw_path("props"))), cols, rows, "props", EFFECT_MIN_COMPONENT_PX)
    neck_box = pipeline.require_box([cells[NECK_CELL]], f"props neck (cell {NECK_CELL})")
    neck, images = write_neck(cells[NECK_CELL][neck_box[1] : neck_box[3], neck_box[0] : neck_box[2]], preview)
    placed: dict[int, Image.Image] = {}
    for clip, indices in spec["clips"].items():
        cells = retarget_prop(cells, clip, indices)
        left, top, right, bottom = pipeline.require_box([cells[i] for i in indices], f"props clip '{clip}' (cells {indices})")
        for i in indices:
            placed[i] = pipeline.centered_cell(cells[i][top:bottom, left:right], EFFECT_SCALE, EFFECT_CELL, f"props[{i}]")
    used, clips = pipeline.compact_clips(spec["clips"])
    image = defringe(pipeline.assemble_sheet([placed[i] for i in used], EFFECT_CELL))
    if preview is not None:
        pipeline.write_preview(image, preview / sheet_file("props"), EFFECT_CELL, EFFECT_CELL // 2, SPRITE_SCALE, {}, f"props scale {EFFECT_SCALE}")
    entry = pipeline.manifest_entry(image, EFFECT_CELL, clips, {})
    props = {
        "sheet": sheet_file("props"),
        "sprite_scale": round(SPRITE_SCALE, 4),
        "grid": entry["grid"],
        "clips": entry["clips"],
        "content": pipeline.clip_contents(image, EFFECT_CELL, entry["clips"]),
    }
    images[sheet_file("props")] = image
    return props, neck, images


def load_manifest() -> dict:
    path = OUT_DIR / "animation_manifest.json"
    return json.loads(path.read_text()) if path.exists() else {}


def write_outputs(images: dict[str, Image.Image], manifest: dict) -> None:
    """Every texture first, the manifest last and through a temporary file, so a crash never
    leaves a manifest that describes textures that were not written."""
    for name, image in images.items():
        image.save(OUT_DIR / name, optimize=True)
    target = OUT_DIR / "animation_manifest.json"
    temporary = target.with_suffix(".json.tmp")
    pipeline.write_manifest(temporary, manifest)
    os.replace(temporary, target)


def main() -> None:
    global RAW_DIR, OUT_DIR
    parser = argparse.ArgumentParser()
    parser.add_argument("--raw-dir", type=Path, default=RAW_DIR, help="folder with the raw sheets")
    parser.add_argument("--out-dir", type=Path, default=OUT_DIR, help="folder for the game sheets and the manifest")
    parser.add_argument("--preview", type=Path, default=None, help="write per-sheet previews (feet row and height lines, head origin box, neck strip)")
    args = parser.parse_args()
    RAW_DIR, OUT_DIR = args.raw_dir.resolve(), args.out_dir.resolve()

    names = [*BODY_SHEETS, *HEAD_SHEETS, "props"]
    present = [name for name in names if raw_path(name).exists()]
    for name in names:
        if name not in present:
            print(f"skip {name}: {raw_path(name)} not found")
    if not present:
        print("nothing to process")
        return

    manifest = load_manifest()
    manifest.update({"cell": BODY_CELL, "feet_row": BODY_FEET_ROW, "sprite_scale": round(SPRITE_SCALE, 4)})
    manifest.setdefault("sheets", {})
    images: dict[str, Image.Image] = {}
    for name in present:
        if name in BODY_SHEETS:
            manifest["sheets"][sheet_file(name)], built = build_body(name, BODY_SHEETS[name], args.preview)
        elif name in HEAD_SHEETS:
            manifest[name], built = build_head(name, HEAD_SHEETS[name], args.preview)
        else:
            manifest["props"], manifest["neck"], built = build_props(PROPS, args.preview)
        images.update(built)
        print(f"  {name}: done")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    write_outputs(images, manifest)
    print("wrote", OUT_DIR)


if __name__ == "__main__":
    main()

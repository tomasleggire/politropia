#!/usr/bin/env python3
"""Ingest new Codex-generated ground-combo hit art (fixed 4x2 grid, 8 frames
per raw sheet) and repack the ground combat sheet around it.

Unlike ``process_luz_sheet.py`` (which segments a *nominal* grid seeded from
legacy hand-picked cut lines because those source sheets bleed across cell
boundaries), the new raw art already guarantees every frame's opaque pixels
stay >= 12px inside its own fixed 384x512 cell (see the Codex prompts under
``tools/art_sources/luz/prompts/``). So per-cell processing here only needs:
  1. per-cell 8-connected alpha-component labeling, to find and drop stray
     specks (small components far from the character's own silhouette);
  2. a per-clip rescale so the new art's body height matches the existing
     (already-committed) sheets' character height at the same 0.175 display
     scale, AND matches across the three hits themselves (hit 3's raw art
     draws Luz ~14.6% larger than hits 1/2 -- see
     RAW_CLIP_READY_HEIGHT_PX/_scale_factor_for_clip below for the
     measurement and per-clip correction);
  3. feet-baseline + horizontal placement into the shared 512x512 output
     cell convention (frame_anchor (256, 413), same as every other clip).

Also measures the wooden ruler's tip/grip/axis per output frame (by its
light-brown/tan hue) and writes assets/player/luz/luz_ruler_track.json --
the single source of truth for hitbox placement (this tool only prints
suggested hitbox values; player.gd's @export values are edited by hand,
keeping gameplay authority there) and for the crescent smear generator
(tools/generate_luz_slash_smears.py reads this track for ground_1/2/3).

Data-driven: add a new clip to RAW_CLIPS (raw file + target cell range) to
process further hits with this same tool -- no code changes needed.
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont

REPO_ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = REPO_ROOT / "tools" / "art_sources" / "luz" / "raw"
OUTPUT_DIR = REPO_ROOT / "assets" / "player" / "luz"
PREVIEW_DIR = REPO_ROOT / "tools" / "art_sources" / "luz" / "preview"
MANIFEST_PATH = OUTPUT_DIR / "animation_manifest.json"
TRACK_PATH = OUTPUT_DIR / "luz_ruler_track.json"
GROUND_SHEET_NAME = "luz_ground_combat_sheet.png"

sys.path.insert(0, str(Path(__file__).resolve().parent))
import process_luz_sheet as legacy  # noqa: E402  (reuses the old sheet's segmentation config)

ALPHA_THRESHOLD = 8
# A component smaller than this AND farther than this from the character's
# own silhouette bbox is a stray speck (compression/generation artifact),
# not part of the art -- dropped (alpha zeroed). Kept otherwise (a component
# could legitimately be disjoint from the main body blob, e.g. a ruler tip
# separated from the hand by a few transparent pixels).
SPECK_SIZE_THRESHOLD = 25  # px (component pixel count)
SPECK_DISTANCE_THRESHOLD = 15  # px (component bbox to body bbox, rect distance)

OUT_CELL_SIZE = 512
CANVAS_PADDING = 100
FEET_ROW = 413
FRAME_ANCHOR = (256, 413)
DISPLAY_SCALE = 0.175
DESIGN_SCALE = 1.0 / DISPLAY_SCALE

# Base scale factor (see odd/tasks/luz-blasphemous-animation.md T4 progress
# entry): tuned so hit 1/2's shared "ready stance" raw bbox height (240px,
# frame 0 of ground_attack_1_raw.png / ground_attack_2_raw.png -- both
# measure identically) lands close to the OLD (pre-T4, currently-committed)
# raw ground_attack_1 art's own ready-stance bbox height (292px under its
# legacy seed cuts): 240*1.17 = 280.8, within ~4% (the two art generations
# aren't expected to match exactly, only to be *consistent with each other*,
# which per-clip correction below now guarantees).
NEW_ART_SCALE_FACTOR_BASE = 1.17

# T4d item 1 fix (iPhone playtest: "in the 3rd hit Luz gets bigger and so
# does the attack hitbox; that must not happen"). Measured directly (frame 0
# of each raw sheet, same planted "ready/guard" stance in all three, alpha
# bbox height after the speck filter, BEFORE any rescale):
#   ground_attack_1 frame 0: 240px   ground_attack_2 frame 0: 240px
#   ground_attack_3 frame 0: 275px  (~14.6% taller than hits 1/2)
# Cross-checked against each clip's own contact frame (index 3, a different
# pose but comparable in silhouette height): 223 / 217 / 248px -- hit 3 is
# 248/220(avg of 1,2) = 1.127x taller there too, agreeing with the frame-0
# ratio (1.146x) within ~1.7%. This confirms hit 3's raw art draws Luz's body
# itself larger, not just a taller pose. Fix: hit 3 gets an additional
# per-clip correction on top of the shared base factor so all three clips'
# body height matches hits 1/2 exactly (240px reference); hits 1/2 keep
# factor 1.0 (already agree).
RAW_CLIP_READY_HEIGHT_PX = {
    "ground_attack_1": 240.0,
    "ground_attack_2": 240.0,
    "ground_attack_3": 275.0,
}
SCALE_REFERENCE_HEIGHT_PX = 240.0  # hits 1/2's own measured ready height.
RESAMPLE = Image.LANCZOS


def _scale_factor_for_clip(clip_name: str) -> float:
    ready_height = RAW_CLIP_READY_HEIGHT_PX.get(clip_name, SCALE_REFERENCE_HEIGHT_PX)
    per_clip_correction = SCALE_REFERENCE_HEIGHT_PX / ready_height
    return NEW_ART_SCALE_FACTOR_BASE * per_clip_correction

RAW_GRID = {"columns": 4, "rows": 2, "cell_width": 384, "cell_height": 512}
RAW_FEET_LOCAL_Y = 472  # measured identically across all 3 new raw sheets

# Ruler wood-tone detection (sampled directly from the contact frame of
# ground_attack_1_raw.png): fill ~ (220-241, 150-180, 94-120), outline/tick
# marks ~ (90-150, 55-95, 30-65). Both are warm brown with R > G > B.
def _is_ruler_pixel(r: int, g: int, b: int) -> bool:
    if not (r > g > b):
        return False
    if not (10 <= (r - g) <= 95 and 8 <= (g - b) <= 85):
        return False
    fill = 195 <= r <= 250 and 125 <= g <= 195 and 75 <= b <= 145
    outline = 70 <= r <= 165 and 45 <= g <= 105 and 20 <= b <= 75
    return fill or outline


RAW_CLIPS = {
    "ground_attack_1": {
        "raw_file": "ground_attack_1_raw.png",
        # Deterministically reuse the approved poses as one forehand action:
        # cocked behind -> raised through the backswing -> one contact ->
        # short follow-through -> settle. Repeated indices are deliberate
        # holds, not extra movement or additional contact poses.
        "source_frames": [1, 1, 1, 3, 3, 7, 7, 7],
        "contact_frame": 3,
    },
    "ground_attack_2": {
        "raw_file": "ground_attack_2_raw.png",
        # Backhand: hold the distinct across-body guard through anticipation,
        # commit once to contact, then drop through into a brief recovery.
        "source_frames": [0, 0, 0, 2, 2, 4, 4, 4],
        "contact_frame": 3,  # runtime contact remains the 4th output frame
    },
    "ground_attack_3": {
        "raw_file": "ground_attack_3_raw.png",
        # Finisher: compact high preparation, one deep planted contact, then
        # a brief downward follow-through held without a second swing.
        "source_frames": [1, 1, 1, 3, 3, 6, 6, 6],
        "contact_frame": 3,
    },
}

NEW_FRAME_COUNT = 8  # every new raw sheet is an 8-frame 4x2 grid
LEGACY_FRAME_COUNT = 4  # every not-yet-replaced clip is still a 4-frame cell

# Ground combat sheet clip order (fixed -- this is the row-major cell layout
# convention) and each clip's OLD cell start in the pristine 4x4 legacy
# sheet, used only when that clip still needs its cells recomputed fresh
# from tools/art_sources/luz/source/ (never copied from a possibly-already-
# migrated assets file). Cell counts/positions in the OUTPUT sheet are
# computed below from RAW_CLIPS, not hardcoded, so a clip's cell range grows
# automatically the moment its raw art is added to RAW_CLIPS -- no manual
# renumbering of the clips that come after it.
CLIP_ORDER = ["ground_attack_1", "ground_attack_2", "ground_attack_3", "crouch_attack"]
LEGACY_OLD_CELL_START = {
    "ground_attack_2": 4,
    "ground_attack_3": 8,
    "crouch_attack": 12,
}


class SegmentationError(RuntimeError):
    pass


def label_components(alpha: bytes, w: int, h: int):
    labels = [0] * (w * h)
    sizes: dict[int, int] = {}
    bboxes: dict[int, tuple[int, int, int, int]] = {}
    next_label = 0
    for start in range(w * h):
        if alpha[start] <= ALPHA_THRESHOLD or labels[start] != 0:
            continue
        next_label += 1
        lbl = next_label
        labels[start] = lbl
        stack = [start]
        size = 0
        minx = miny = 10**9
        maxx = maxy = -1
        while stack:
            idx = stack.pop()
            size += 1
            y, x = divmod(idx, w)
            if x < minx:
                minx = x
            if x > maxx:
                maxx = x
            if y < miny:
                miny = y
            if y > maxy:
                maxy = y
            x0 = x - 1 if x > 0 else 0
            x1 = x + 1 if x < w - 1 else w - 1
            y0 = y - 1 if y > 0 else 0
            y1 = y + 1 if y < h - 1 else h - 1
            for ny in range(y0, y1 + 1):
                base = ny * w
                for nx in range(x0, x1 + 1):
                    nidx = base + nx
                    if nidx == idx:
                        continue
                    if alpha[nidx] > ALPHA_THRESHOLD and labels[nidx] == 0:
                        labels[nidx] = lbl
                        stack.append(nidx)
        sizes[lbl] = size
        bboxes[lbl] = (minx, miny, maxx, maxy)
    return labels, sizes, bboxes


def _rect_distance(a: tuple[int, int, int, int], b: tuple[int, int, int, int]) -> float:
    ax0, ay0, ax1, ay1 = a
    bx0, by0, bx1, by1 = b
    dx = max(bx0 - ax1, ax0 - bx1, 0)
    dy = max(by0 - ay1, ay0 - by1, 0)
    return math.hypot(dx, dy)


def speck_filter(cell_img: Image.Image) -> tuple[Image.Image, int]:
    """Drops small-and-far components. Returns (filtered_image, dropped_count)."""
    w, h = cell_img.size
    alpha = cell_img.split()[-1].tobytes()
    labels, sizes, bboxes = label_components(alpha, w, h)
    if not sizes:
        raise SegmentationError("cell has no opaque pixels at all")
    body_label = max(sizes, key=lambda l: sizes[l])
    body_bbox = bboxes[body_label]

    dropped_labels = set()
    for lbl, size in sizes.items():
        if lbl == body_label:
            continue
        if size < SPECK_SIZE_THRESHOLD and _rect_distance(bboxes[lbl], body_bbox) > SPECK_DISTANCE_THRESHOLD:
            dropped_labels.add(lbl)

    if not dropped_labels:
        return cell_img.copy(), 0

    out = cell_img.copy()
    r, g, b, a = out.split()
    a_bytes = bytearray(a.tobytes())
    for i, lbl in enumerate(labels):
        if lbl in dropped_labels:
            a_bytes[i] = 0
    a2 = Image.frombytes("L", (w, h), bytes(a_bytes))
    out = Image.merge("RGBA", (r, g, b, a2))
    return out, len(dropped_labels)


def premultiply(im: Image.Image) -> Image.Image:
    r, g, b, a = im.split()
    return Image.merge("RGBA", (ImageChops.multiply(r, a), ImageChops.multiply(g, a), ImageChops.multiply(b, a), a))


def unpremultiply(im: Image.Image) -> Image.Image:
    data = im.getdata()
    out = []
    for r, g, b, a in data:
        if a == 0:
            out.append((0, 0, 0, 0))
        else:
            out.append((min(255, r * 255 // a), min(255, g * 255 // a), min(255, b * 255 // a), a))
    result = Image.new("RGBA", im.size)
    result.putdata(out)
    return result


def process_raw_frame(raw_sheet: Image.Image, cell_index: int, report: list[str], scale_factor: float) -> Image.Image:
    """Returns a fresh 512x512 output cell for one frame of new raw art."""
    col = cell_index % RAW_GRID["columns"]
    row = cell_index // RAW_GRID["columns"]
    cw, ch = RAW_GRID["cell_width"], RAW_GRID["cell_height"]
    cell_img = raw_sheet.crop((col * cw, row * ch, (col + 1) * cw, (row + 1) * ch))

    filtered, dropped = speck_filter(cell_img)
    if dropped:
        report.append(f"    frame {cell_index}: dropped {dropped} stray speck component(s)")

    bbox = filtered.getbbox()
    if bbox is None:
        raise SegmentationError(f"frame {cell_index}: empty after speck filter")
    region = filtered.crop(bbox)
    region_w, region_h = region.size

    scaled_w = max(1, round(region_w * scale_factor))
    scaled_h = max(1, round(region_h * scale_factor))
    scaled = unpremultiply(premultiply(region).resize((scaled_w, scaled_h), RESAMPLE))

    leading_x = CANVAS_PADDING + round(bbox[0] * scale_factor)
    leading_y = FEET_ROW - (scaled_h - 1)

    # The finisher's widest contact frame can be wider than CANVAS_PADDING +
    # scaled_w leaves room for (by design -- it must reach farther than hits
    # 1/2). Clamp to the cell's right edge rather than failing: this only
    # reduces that frame's own left padding, it does not touch feet-baseline
    # alignment or any other frame's placement.
    if leading_x + scaled_w > OUT_CELL_SIZE:
        report.append(
            f"    frame {cell_index}: reach clamps left padding from {leading_x} "
            f"to {OUT_CELL_SIZE - scaled_w} to fit the 512px cell"
        )
        leading_x = OUT_CELL_SIZE - scaled_w

    if leading_y < 0:
        # A tall pose (e.g. the finisher's raised follow-through) is taller
        # than the feet-baseline convention leaves headroom for. Trim the
        # excess off the TOP instead of shifting the whole frame down: the
        # feet-on-row-413 baseline is the invariant every clip and the
        # catalog's frame_anchor rely on, so it must stay exact; losing a
        # few px of hair/ruler tip above the canvas is the lesser cost.
        crop_top = -leading_y
        report.append(f"    frame {cell_index}: trims {crop_top}px off the top to keep the feet baseline exact")
        scaled = scaled.crop((0, crop_top, scaled_w, scaled_h))
        scaled_h -= crop_top
        leading_y = 0

    if leading_x < 0 or leading_y < 0 or leading_x + scaled_w > OUT_CELL_SIZE or leading_y + scaled_h > OUT_CELL_SIZE:
        raise SegmentationError(
            f"frame {cell_index}: scaled placement out of bounds "
            f"(leading=({leading_x},{leading_y}), size=({scaled_w}x{scaled_h}))"
        )

    # T4d fix: Image.paste(im, box, mask=im) blends ALL FOUR channels
    # (including alpha itself) by the mask weight against a destination that
    # starts fully transparent -- for a translucent antialiased edge pixel
    # (alpha=128, say) this computes result_alpha = 128*(128/255) = 64.3, not
    # 128: alpha gets silently squared/eroded at every frame's silhouette
    # edge. alpha_composite performs correct over-compositing (equivalent to
    # a plain copy here, since the destination region is always fully
    # transparent first) and was found while chasing a foreshortened-frame
    # ruler-detection bug (T4d item 2) whose axis measurement was sensitive
    # to this edge erosion.
    out = Image.new("RGBA", (OUT_CELL_SIZE, OUT_CELL_SIZE), (0, 0, 0, 0))
    out.alpha_composite(scaled, (leading_x, leading_y))
    return out


RULER_MIN_COMPONENT_SIZE = 300  # px; drop small color-matched noise
RULER_MIN_ELONGATION = 15.0  # major/minor eigenvalue ratio; the ruler is a
# long thin bar (elongation 30-100+ measured), while hair/skin regions that
# happen to fall in the same warm-tan color range are blobby (elongation
# 2-6) -- this is what actually isolates the ruler, not color alone.

# Some frames legitimately FORESHORTEN the ruler (it points toward/away from
# the camera during a horizontal swing and projects as a short, sometimes
# almost-square blob) -- its elongation can then fall under
# RULER_MIN_ELONGATION even though it is the ruler, not hair/skin. Rather
# than failing the whole pipeline on those frames (they are not used to
# drive smear/hitbox geometry -- only the contact frame is, and the contact
# frame is by design fully horizontal/unforeshortened), fall back to the
# single largest ruler-colored component past a relaxed size floor and mark
# the measurement "low_confidence" instead of raising.
RULER_FALLBACK_MIN_COMPONENT_SIZE = 120  # px
RULER_FALLBACK_MIN_ELONGATION = 2.5  # just enough to reject near-circular noise


def _pca(pts: list[tuple[int, int]]) -> tuple[float, float, float, float, float, float]:
    """2x2 PCA closed form. Returns (mx, my, lam1, lam2, vx, vy): centroid,
    major/minor eigenvalues, and the (unit) principal eigenvector."""
    n = len(pts)
    mx = sum(p[0] for p in pts) / n
    my = sum(p[1] for p in pts) / n
    sxx = sum((p[0] - mx) ** 2 for p in pts) / n
    syy = sum((p[1] - my) ** 2 for p in pts) / n
    sxy = sum((p[0] - mx) * (p[1] - my) for p in pts) / n
    trace = sxx + syy
    det = sxx * syy - sxy * sxy
    disc = max(trace * trace / 4.0 - det, 0.0)
    lam1 = trace / 2.0 + math.sqrt(disc)
    lam2 = trace / 2.0 - math.sqrt(disc)
    if abs(sxy) > 1e-9:
        vx, vy = lam1 - syy, sxy
    elif sxx >= syy:
        vx, vy = 1.0, 0.0
    else:
        vx, vy = 0.0, 1.0
    norm = math.hypot(vx, vy) or 1.0
    return mx, my, lam1, lam2, vx / norm, vy / norm


def _connected_components(mask: bytearray, w: int, h: int) -> list[list[tuple[int, int]]]:
    labels = [0] * (w * h)
    comps: list[list[tuple[int, int]]] = []
    for start in range(w * h):
        if mask[start] == 0 or labels[start] != 0:
            continue
        lbl = len(comps) + 1
        labels[start] = lbl
        stack = [start]
        pts: list[tuple[int, int]] = []
        while stack:
            idx = stack.pop()
            y, x = divmod(idx, w)
            pts.append((x, y))
            x0 = x - 1 if x > 0 else 0
            x1 = x + 1 if x < w - 1 else w - 1
            y0 = y - 1 if y > 0 else 0
            y1 = y + 1 if y < h - 1 else h - 1
            for ny in range(y0, y1 + 1):
                base = ny * w
                for nx in range(x0, x1 + 1):
                    nidx = base + nx
                    if nidx == idx:
                        continue
                    if mask[nidx] and labels[nidx] == 0:
                        labels[nidx] = lbl
                        stack.append(nidx)
        comps.append(pts)
    return comps


def measure_ruler(frame_img: Image.Image) -> dict:
    """Ruler tip/grip/axis for one already-placed 512x512 output frame.

    Color alone (light-brown/tan) also matches blonde hair and skin tones,
    so candidate color pixels are further split into 8-connected components
    and only components that are both large enough and highly elongated
    (major/minor eigenvalue ratio) are kept as "the ruler" -- hair/skin
    blobs are round/compact (elongation ~2-6), the ruler is a long thin bar
    (elongation 30-100+ measured across all 8 frames of ground_attack_1).
    """
    rgba = frame_img.convert("RGBA")
    w, h = rgba.size
    px = rgba.load()

    color_mask = bytearray(w * h)
    body_sx = body_sy = body_n = 0
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a <= ALPHA_THRESHOLD:
                continue
            body_sx += x
            body_sy += y
            body_n += 1
            if _is_ruler_pixel(r, g, b):
                color_mask[y * w + x] = 1

    if body_n == 0:
        raise SegmentationError("measure_ruler: empty frame")

    body_cx = body_sx / body_n
    body_cy = body_sy / body_n

    components = _connected_components(color_mask, w, h)
    ruler_pts: list[tuple[int, int]] = []
    low_confidence = False
    for comp in components:
        if len(comp) < RULER_MIN_COMPONENT_SIZE:
            continue
        _, _, lam1, lam2, _, _ = _pca(comp)
        elongation = lam1 / max(lam2, 1e-6)
        if elongation >= RULER_MIN_ELONGATION:
            ruler_pts.extend(comp)

    if len(ruler_pts) < 8:
        # Strict pass found nothing (likely a foreshortened ruler this
        # frame) -- fall back to the single largest relaxed-threshold
        # ruler-colored component instead of failing the whole clip.
        low_confidence = True
        fallback_candidates = []
        for comp in components:
            if len(comp) < RULER_FALLBACK_MIN_COMPONENT_SIZE:
                continue
            _, _, lam1, lam2, _, _ = _pca(comp)
            elongation = lam1 / max(lam2, 1e-6)
            if elongation >= RULER_FALLBACK_MIN_ELONGATION:
                fallback_candidates.append(comp)
        if not fallback_candidates:
            return {
                "low_confidence": True,
                "tip": None,
                "grip": None,
                "tip_px": None,
                "grip_px": None,
                "axis_angle_deg": None,
                "ruler_pixel_count": 0,
                "note": "no ruler-colored component found even at the relaxed fallback threshold (foreshortened/occluded frame)",
            }
        ruler_pts = max(fallback_candidates, key=len)

    n = len(ruler_pts)
    mx, my, _, _, vx, vy = _pca(ruler_pts)

    projections = [((p[0] - mx) * vx + (p[1] - my) * vy, p) for p in ruler_pts]
    proj_min = min(projections, key=lambda t: t[0])
    proj_max = max(projections, key=lambda t: t[0])
    end_a, end_b = proj_min[1], proj_max[1]

    def dist_to_body(p: tuple[int, int]) -> float:
        return math.hypot(p[0] - body_cx, p[1] - body_cy)

    if dist_to_body(end_a) >= dist_to_body(end_b):
        tip, grip = end_a, end_b
    else:
        tip, grip = end_b, end_a

    axis_deg = math.degrees(math.atan2(tip[1] - grip[1], tip[0] - grip[0]))

    def to_world(p: tuple[int, int]) -> dict:
        return {
            "x": round((p[0] - FRAME_ANCHOR[0]) * DISPLAY_SCALE, 2),
            "y": round((p[1] - FRAME_ANCHOR[1]) * DISPLAY_SCALE, 2),
        }

    return {
        "tip_px": {"x": tip[0], "y": tip[1]},
        "grip_px": {"x": grip[0], "y": grip[1]},
        "tip": to_world(tip),
        "grip": to_world(grip),
        "axis_angle_deg": round(axis_deg, 2),
        "ruler_pixel_count": n,
        "low_confidence": low_confidence,
    }


def _load_font():
    try:
        return ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 20)
    except OSError:
        return ImageFont.load_default()


def render_contact_sheet(out_sheet: Image.Image, dest: Path, ground_grid: dict) -> None:
    contact = out_sheet.convert("RGBA").copy()
    draw = ImageDraw.Draw(contact)
    font = _load_font()
    cols, rows = ground_grid["columns"], ground_grid["rows"]
    for cell in range(cols * rows):
        col = cell % cols
        row = cell // cols
        x0, y0 = col * OUT_CELL_SIZE, row * OUT_CELL_SIZE
        x1, y1 = x0 + OUT_CELL_SIZE - 1, y0 + OUT_CELL_SIZE - 1
        draw.rectangle([x0, y0, x1, y1], outline=(255, 0, 255, 255), width=2)
        draw.line([(x0, y0 + FEET_ROW), (x1, y0 + FEET_ROW)], fill=(0, 200, 255, 180), width=1)
        draw.text((x0 + 6, y0 + 6), str(cell), fill=(255, 255, 0, 255), font=font)
    contact.save(dest)


def render_onion_skin(out_sheet: Image.Image, indices: list[int], clip_name: str, dest_dir: Path, ground_grid: dict) -> None:
    cols = ground_grid["columns"]
    canvas = Image.new("RGBA", (OUT_CELL_SIZE, OUT_CELL_SIZE), (30, 30, 34, 255))
    n = len(indices)
    for i, cell in enumerate(indices):
        col = cell % cols
        row = cell // cols
        cell_img = out_sheet.crop((col * OUT_CELL_SIZE, row * OUT_CELL_SIZE, (col + 1) * OUT_CELL_SIZE, (row + 1) * OUT_CELL_SIZE))
        alpha_scale = 1.0 if i == n - 1 else 0.35
        r, g, b, a = cell_img.split()
        a = a.point(lambda v, s=alpha_scale: int(v * s))
        canvas.alpha_composite(Image.merge("RGBA", (r, g, b, a)))
    draw = ImageDraw.Draw(canvas)
    draw.line([(0, FEET_ROW), (OUT_CELL_SIZE, FEET_ROW)], fill=(255, 0, 255, 200), width=1)
    draw.text((6, 6), clip_name, fill=(255, 255, 0, 255), font=_load_font())
    canvas.save(dest_dir / f"{GROUND_SHEET_NAME.replace('.png', '')}__{clip_name}.png")


def build_legacy_ground_sheet() -> Image.Image:
    """Re-derives the pristine legacy 4x4 ground combat sheet straight from
    tools/art_sources/luz/source/ (never from the possibly-already-migrated
    assets file), for clips not yet reprocessed from new raw art."""
    config = legacy.SHEETS[GROUND_SHEET_NAME]
    result = legacy.process_sheet(GROUND_SHEET_NAME, config, verbose=False)
    return result["out_sheet"]


def _resolve_layout() -> tuple[dict[str, int], dict[str, int], dict]:
    """Cell layout for CLIP_ORDER, computed from RAW_CLIPS (not hardcoded):
    a clip gets NEW_FRAME_COUNT(8) cells if it has an existing raw file
    configured in RAW_CLIPS, else LEGACY_FRAME_COUNT(4). Returns
    (cell_start_by_clip, frame_count_by_clip, ground_grid)."""
    frame_counts: dict[str, int] = {}
    for clip_name in CLIP_ORDER:
        cfg = RAW_CLIPS.get(clip_name)
        has_raw = cfg is not None and (RAW_DIR / cfg["raw_file"]).exists()
        frame_counts[clip_name] = NEW_FRAME_COUNT if has_raw else LEGACY_FRAME_COUNT

    cell_starts: dict[str, int] = {}
    cursor = 0
    for clip_name in CLIP_ORDER:
        cell_starts[clip_name] = cursor
        cursor += frame_counts[clip_name]

    total_cells = cursor
    columns = 4
    rows = -(-total_cells // columns)  # ceil division
    grid = {"columns": columns, "rows": rows, "cell_width": OUT_CELL_SIZE, "cell_height": OUT_CELL_SIZE}
    return cell_starts, frame_counts, grid


def main() -> int:
    report: list[str] = []
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    (PREVIEW_DIR / ".gitignore").write_text("*\n")

    manifest = json.loads(MANIFEST_PATH.read_text())
    ground_sheet_manifest = manifest["sheets"][GROUND_SHEET_NAME]

    cell_starts, frame_counts, ground_grid = _resolve_layout()
    print(f"Ground combat sheet layout: {ground_grid}; cell starts: {cell_starts}")
    out_sheet = Image.new("RGBA", (ground_grid["columns"] * OUT_CELL_SIZE, ground_grid["rows"] * OUT_CELL_SIZE), (0, 0, 0, 0))

    clips: dict[str, list[int]] = {}
    contact_frames: dict[str, int] = {}
    track: dict[str, dict] = {}
    legacy_sheet = None

    for clip_name in CLIP_ORDER:
        frame_count = frame_counts[clip_name]
        new_indices = list(range(cell_starts[clip_name], cell_starts[clip_name] + frame_count))
        clips[clip_name] = new_indices

        if frame_count == NEW_FRAME_COUNT:
            cfg = RAW_CLIPS[clip_name]
            print(f"Processing {clip_name} from {cfg['raw_file']}...")
            raw_sheet = Image.open(RAW_DIR / cfg["raw_file"]).convert("RGBA")
            assert raw_sheet.size == (
                RAW_GRID["columns"] * RAW_GRID["cell_width"],
                RAW_GRID["rows"] * RAW_GRID["cell_height"],
            ), f"{clip_name}: unexpected raw sheet size {raw_sheet.size}"
            contact_frames[clip_name] = cfg["contact_frame"]
            scale_factor = _scale_factor_for_clip(clip_name)
            print(f"  scale factor for {clip_name}: {scale_factor:.4f} (base {NEW_ART_SCALE_FACTOR_BASE} x per-clip correction {scale_factor / NEW_ART_SCALE_FACTOR_BASE:.4f})")

            frame_records = []
            source_frames = cfg.get("source_frames", list(range(frame_count)))
            if len(source_frames) != frame_count:
                raise SegmentationError(
                    f"{clip_name}: source_frames has {len(source_frames)} entries, expected {frame_count}"
                )
            if cfg["contact_frame"] != 3 or source_frames[cfg["contact_frame"]] not in (2, 3):
                raise SegmentationError(
                    f"{clip_name}: contact_frame must select an approved horizontal raw contact pose"
                )
            for local_i, source_i in enumerate(source_frames):
                frame_img = process_raw_frame(raw_sheet, source_i, report, scale_factor)
                dest_cell = new_indices[local_i]
                col = dest_cell % ground_grid["columns"]
                row = dest_cell // ground_grid["columns"]
                out_sheet.alpha_composite(frame_img, (col * OUT_CELL_SIZE, row * OUT_CELL_SIZE))
                ruler = measure_ruler(frame_img)
                frame_records.append({"frame": local_i, **ruler})
                conf_tag = " [LOW CONFIDENCE, foreshortened/occluded]" if ruler.get("low_confidence") else ""
                print(f"  frame {local_i} -> cell {dest_cell}: tip={ruler['tip']} grip={ruler['grip']} axis={ruler['axis_angle_deg']}deg{conf_tag}")

            track[clip_name] = {"contact_frame": cfg["contact_frame"], "frames": frame_records}
        else:
            # Not (yet) reprocessed from new raw art: recompute fresh from the
            # pristine legacy source sheet (never from a possibly-already-
            # migrated assets file) and copy into the new cell positions.
            if legacy_sheet is None:
                print("Recomputing unchanged clip(s) from pristine legacy source...")
                legacy_sheet = build_legacy_ground_sheet()
            old_start = LEGACY_OLD_CELL_START[clip_name]
            legacy_manifest_contact = ground_sheet_manifest.get("contact_frames", {}).get(clip_name, -1)
            if legacy_manifest_contact >= 0:
                contact_frames[clip_name] = legacy_manifest_contact
            for local_i in range(frame_count):
                old_cell = old_start + local_i
                old_col, old_row = old_cell % 4, old_cell // 4
                cell_img = legacy_sheet.crop((old_col * OUT_CELL_SIZE, old_row * OUT_CELL_SIZE, (old_col + 1) * OUT_CELL_SIZE, (old_row + 1) * OUT_CELL_SIZE))
                dest_cell = new_indices[local_i]
                col, row = dest_cell % ground_grid["columns"], dest_cell // ground_grid["columns"]
                out_sheet.alpha_composite(cell_img, (col * OUT_CELL_SIZE, row * OUT_CELL_SIZE))

        render_onion_skin(out_sheet, new_indices, clip_name, PREVIEW_DIR, ground_grid)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    out_path = OUTPUT_DIR / GROUND_SHEET_NAME
    out_sheet.save(out_path)
    print(f"Wrote {out_path} ({out_sheet.size[0]}x{out_sheet.size[1]})")

    contact_dest = PREVIEW_DIR / f"{GROUND_SHEET_NAME.replace('.png', '')}__contact_sheet.png"
    render_contact_sheet(out_sheet, contact_dest, ground_grid)

    # Update manifest (ground combat sheet section only).
    ground_sheet_manifest["grid"] = ground_grid
    ground_sheet_manifest["clips"] = clips
    ground_sheet_manifest["contact_frames"] = contact_frames
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Updated {MANIFEST_PATH}")

    # Update / merge the ruler track (only touches processed clips' entries).
    existing_track = {}
    if TRACK_PATH.exists():
        existing_track = json.loads(TRACK_PATH.read_text())
    existing_track.setdefault("display_scale", DISPLAY_SCALE)
    existing_track.setdefault("frame_anchor", {"x": FRAME_ANCHOR[0], "y": FRAME_ANCHOR[1]})
    existing_track.setdefault("clips", {})
    existing_track["clips"].update(track)
    TRACK_PATH.write_text(json.dumps(existing_track, indent=2) + "\n")
    print(f"Updated {TRACK_PATH}")

    print("\n".join(report))
    print("\nDone.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

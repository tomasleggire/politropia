#!/usr/bin/env python3
"""Erase the drawn wooden ruler from Luz's attack body frames.

Luz's weapon is now rendered at runtime by scripts/player/ruler_weapon.gd as a
procedural sprite following assets/player/luz/luz_attack_swings.json, so the
body art must never show its own baked-in ruler (that would draw two rulers).

Detection: the ruler is a long, thin, warm-tan wood-colored blob. Empirically
(see tools/art_sources/luz/preview/*_contact_sheet.png and per-frame visual
inspection during T3b) it is reliably the only wood-colored connected
component whose elongation ratio (major/minor eigenvalue of its pixel PCA) is
>= ELONG_THRESHOLD; hair/skin/clothing components in every inspected frame of
ground_attack_1/2/3, crouch_attack, up_attack and air_horizontal_attack stay
below ~10. This holds even for the small fragments a finger/sleeve sometimes
splits the ruler into (tip glare, the segment behind the gripping hand) --
those fragments are *also* elongated, so unioning every component that clears
the threshold recovers the whole ruler including its tip.

Removal: masked pixels are cleared to fully transparent, then any remaining
hole against a mostly-opaque neighborhood (i.e. where the ruler overlapped a
hand/sleeve, not empty background) is inpainted by iterative nearest-neighbor
fill from the mask boundary inward, so no floating body fragments or holes
are left. This is deliberately simple (no generative inpainting available in
this environment) -- see the feature doc for the visual QA that validated it
frame-by-frame.

Also emits, per erased frame, the ruler's *grip end* (the extreme point of
its principal axis closest to the body centroid) and its *tip end* (the far
extreme) in native sprite pixels, written to
assets/player/luz/luz_ruler_anchors.json (and, after conversion to world
units, folded into luz_attack_swings.json's "measured_frame_grips_native_px"
per kind) -- informational calibration data, not literally interpolated at
runtime; see ruler_weapon.gd's module comment for why.

Usage: tools/erase_luz_ruler.py [--dry-run] [--sheet NAME ...]
Writes cleaned sheets back to assets/player/luz/*.png (in place) and preview
before/after/mask composites to tools/art_sources/luz/preview/.
"""

from __future__ import annotations

import argparse
import json
import math
from collections import deque
from pathlib import Path

from PIL import Image

REPO_ROOT = Path(__file__).resolve().parent.parent
ASSET_ROOT = REPO_ROOT / "assets" / "player" / "luz"
PREVIEW_DIR = REPO_ROOT / "tools" / "art_sources" / "luz" / "preview"
MANIFEST_PATH = ASSET_ROOT / "animation_manifest.json"

ELONG_THRESHOLD = 15.0
MIN_COMPONENT_PIXELS = 15
DILATE_PASSES = 2

# sheet_name -> list of clip names that carry a hand-held ruler needing erasure.
RULER_CLIPS = {
    "luz_ground_combat_sheet.png": ["ground_attack_1", "ground_attack_2", "ground_attack_3", "crouch_attack"],
    "luz_air_combat_sheet.png": ["up_attack", "air_horizontal_attack"],
}


def is_wood(r: int, g: int, b: int, a: int) -> bool:
    if a < 20:
        return False
    mx, mn = max(r, g, b), min(r, g, b)
    sat = (mx - mn) / mx if mx > 0 else 0.0
    if not (r >= g >= b or (r >= g and g >= b - 6)):
        return False
    if r < 120 or r > 245:
        return False
    if sat < 0.10:
        return False
    if b > 190:
        return False
    return True


def connected_components(mask: list[list[bool]], w: int, h: int) -> list[list[tuple[int, int]]]:
    seen = [[False] * w for _ in range(h)]
    comps = []
    for y in range(h):
        for x in range(w):
            if mask[y][x] and not seen[y][x]:
                q = deque([(x, y)])
                seen[y][x] = True
                pts = []
                while q:
                    cx, cy = q.popleft()
                    pts.append((cx, cy))
                    for dx in (-1, 0, 1):
                        for dy in (-1, 0, 1):
                            nx, ny = cx + dx, cy + dy
                            if 0 <= nx < w and 0 <= ny < h and mask[ny][nx] and not seen[ny][nx]:
                                seen[ny][nx] = True
                                q.append((nx, ny))
                comps.append(pts)
    return comps


def pca_elongation(pts: list[tuple[int, int]]) -> tuple[float, float, tuple[float, float]]:
    n = len(pts)
    mx = sum(p[0] for p in pts) / n
    my = sum(p[1] for p in pts) / n
    sxx = sum((p[0] - mx) ** 2 for p in pts) / n
    syy = sum((p[1] - my) ** 2 for p in pts) / n
    sxy = sum((p[0] - mx) * (p[1] - my) for p in pts) / n
    tr = sxx + syy
    det = sxx * syy - sxy * sxy
    disc = max(0.0, tr * tr / 4 - det)
    l1 = tr / 2 + math.sqrt(disc)
    l2 = tr / 2 - math.sqrt(disc)
    elong = l1 / max(l2, 1e-6)
    angle = 0.5 * math.atan2(2 * sxy, sxx - syy)
    return elong, angle, (mx, my)


def dilate(mask_pts: set[tuple[int, int]], w: int, h: int, passes: int) -> set[tuple[int, int]]:
    cur = set(mask_pts)
    for _ in range(passes):
        nxt = set(cur)
        for (x, y) in cur:
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h:
                        nxt.add((nx, ny))
        cur = nxt
    return cur


OUTLINE_MAX_BRIGHTNESS = 95
OUTLINE_GROW_PASSES = 6


def grow_dark_outline(mask_pts: set[tuple[int, int]], im: Image.Image) -> set[tuple[int, int]]:
    """The ruler's dark stroke outline (near-black brown, e.g. rgb ~45,22,12)
    falls outside the is_wood() color test and can survive plain dilation as
    a thin floating trail (seen on up_attack after the first detection pass).
    Grow the mask through directly-adjacent dark, opaque pixels for a few
    iterations so the whole outline gets pulled in without spreading into
    unrelated dark clothing/hair regions further away."""
    w, h = im.size
    px = im.load()
    cur = set(mask_pts)
    for _ in range(OUTLINE_GROW_PASSES):
        frontier = set()
        for (x, y) in cur:
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    nx, ny = x + dx, y + dy
                    if (nx, ny) in cur or not (0 <= nx < w and 0 <= ny < h):
                        continue
                    r, g, b, a = px[nx, ny]
                    if a > 40 and max(r, g, b) < OUTLINE_MAX_BRIGHTNESS:
                        frontier.add((nx, ny))
        if not frontier:
            break
        cur |= frontier
    return cur


def inpaint(im: Image.Image, mask_pts: set[tuple[int, int]]) -> Image.Image:
    """Clear mask_pts to transparent, then fill any resulting hole (a masked
    pixel whose un-masked neighborhood was mostly opaque, i.e. body/clothing
    the ruler occluded) by nearest-neighbor color from outside the mask."""
    w, h = im.size
    px = im.load()

    # First pass: does this masked pixel sit over background (transparent
    # neighbors) or over body (opaque neighbors)? Only the latter needs fill.
    needs_fill = []
    for (x, y) in mask_pts:
        opaque_neighbors = 0
        total = 0
        for dx in (-2, -1, 0, 1, 2):
            for dy in (-2, -1, 0, 1, 2):
                nx, ny = x + dx, y + dy
                if (nx, ny) in mask_pts:
                    continue
                if 0 <= nx < w and 0 <= ny < h:
                    total += 1
                    if px[nx, ny][3] > 40:
                        opaque_neighbors += 1
        if total > 0 and opaque_neighbors / total > 0.35:
            needs_fill.append((x, y))

    # Clear every masked pixel to transparent first.
    for (x, y) in mask_pts:
        px[x, y] = (0, 0, 0, 0)

    if not needs_fill:
        return im

    # BFS fill from the mask boundary inward: each fill pixel takes the color
    # of the first already-resolved (original opaque or already-filled)
    # neighbor reached, propagating inward like a distance-ordered fill.
    fill_set = set(needs_fill)
    resolved: dict[tuple[int, int], tuple[int, int, int, int]] = {}
    frontier: deque[tuple[int, int]] = deque()
    for (x, y) in fill_set:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                nx, ny = x + dx, y + dy
                if (nx, ny) not in fill_set and 0 <= nx < w and 0 <= ny < h:
                    color = px[nx, ny]
                    if color[3] > 40:
                        frontier.append((x, y))
                        break
            else:
                continue
            break

    visited = set()
    queue = deque(frontier)
    seed_colors = {}
    for (x, y) in list(queue):
        best = None
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in fill_set:
                    c = px[nx, ny]
                    if c[3] > 40:
                        best = c
        if best is not None:
            seed_colors[(x, y)] = best

    order = deque(seed_colors.keys())
    while order:
        x, y = order.popleft()
        if (x, y) in visited:
            continue
        visited.add((x, y))
        resolved[(x, y)] = seed_colors[(x, y)]
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                nx, ny = x + dx, y + dy
                if (nx, ny) in fill_set and (nx, ny) not in visited and (nx, ny) not in seed_colors:
                    seed_colors[(nx, ny)] = resolved[(x, y)]
                    order.append((nx, ny))

    for (x, y) in fill_set:
        if (x, y) in resolved:
            px[x, y] = resolved[(x, y)]
        else:
            px[x, y] = (0, 0, 0, 0)

    return im


def process_frame(im: Image.Image, label: str) -> tuple[Image.Image, dict]:
    w, h = im.size
    px = im.load()
    wood_mask = [[False] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if is_wood(r, g, b, a):
                wood_mask[y][x] = True

    comps = connected_components(wood_mask, w, h)
    ruler_pts: list[tuple[int, int]] = []
    ruler_components = []
    for pts in comps:
        if len(pts) < MIN_COMPONENT_PIXELS:
            continue
        elong, angle, center = pca_elongation(pts)
        if elong >= ELONG_THRESHOLD:
            ruler_components.append((pts, elong, angle, center))
            ruler_pts.extend(pts)

    if not ruler_pts:
        print(f"  WARNING: no ruler component found for {label}")
        return im, {"found": False}

    # Body centroid: everything opaque that is NOT a ruler component,
    # to tell which principal-axis extreme of the ruler is the grip end.
    ruler_set = set(ruler_pts)
    body_x = body_y = body_n = 0
    for y in range(h):
        for x in range(w):
            if px[x, y][3] > 40 and (x, y) not in ruler_set:
                body_x += x
                body_y += y
                body_n += 1
    body_cx = body_x / body_n if body_n else w / 2
    body_cy = body_y / body_n if body_n else h / 2

    all_elong, all_angle, all_center = pca_elongation(ruler_pts)
    direction = (math.cos(all_angle), math.sin(all_angle))
    projections = [
        ((x - all_center[0]) * direction[0] + (y - all_center[1]) * direction[1], x, y)
        for (x, y) in ruler_pts
    ]
    projections.sort()
    t_min, x_min, y_min = projections[0]
    t_max, x_max, y_max = projections[-1]
    end_a = (float(x_min), float(y_min))
    end_b = (float(x_max), float(y_max))
    dist_a = math.hypot(end_a[0] - body_cx, end_a[1] - body_cy)
    dist_b = math.hypot(end_b[0] - body_cx, end_b[1] - body_cy)
    grip_end, tip_end = (end_a, end_b) if dist_a < dist_b else (end_b, end_a)

    dilated = dilate(ruler_set, w, h, DILATE_PASSES)
    grown = grow_dark_outline(dilated, im)
    out = inpaint(im.copy(), grown)

    info = {
        "found": True,
        "grip": [round(grip_end[0], 1), round(grip_end[1], 1)],
        "tip": [round(tip_end[0], 1), round(tip_end[1], 1)],
        "component_count": len(ruler_components),
        "mask_pixels": len(grown),
    }
    return out, info


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", help="Detect and preview only, do not overwrite sheets.")
    parser.add_argument("--sheet", action="append", help="Limit to this sheet filename (repeatable).")
    args = parser.parse_args()

    manifest = json.loads(MANIFEST_PATH.read_text())
    sheets = manifest["sheets"]
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)

    frame_anchors: dict[str, list[dict]] = {}

    for sheet_name, clip_names in RULER_CLIPS.items():
        if args.sheet and sheet_name not in args.sheet:
            continue
        sheet_path = ASSET_ROOT / sheet_name
        im = Image.open(sheet_path).convert("RGBA")
        grid = sheets[sheet_name]["grid"]
        cw, ch, cols = grid["cell_width"], grid["cell_height"], grid["columns"]

        for clip_name in clip_names:
            idxs = sheets[sheet_name]["clips"][clip_name]
            clip_anchors = []
            before_frames = []
            after_frames = []
            for i, idx in enumerate(idxs):
                col = idx % cols
                row = idx // cols
                box = (col * cw, row * ch, (col + 1) * cw, (row + 1) * ch)
                frame = im.crop(box)
                before_frames.append(frame.copy())
                cleaned, info = process_frame(frame, f"{clip_name}[{i}]")
                after_frames.append(cleaned)
                clip_anchors.append(info)
                if not args.dry_run:
                    im.paste(cleaned, box)
                print(f"{sheet_name}:{clip_name}[{i}] -> {info}")

            frame_anchors[clip_name] = clip_anchors

            # Before/after strip preview.
            strip = Image.new("RGBA", (cw * len(idxs), ch * 2), (30, 30, 34, 255))
            for i, f in enumerate(before_frames):
                strip.alpha_composite(f, (i * cw, 0))
            for i, f in enumerate(after_frames):
                strip.alpha_composite(f, (i * cw, ch))
            strip.save(PREVIEW_DIR / f"erase_ruler__{clip_name}.png")

        if not args.dry_run:
            sheet_path.parent.mkdir(parents=True, exist_ok=True)
            im.save(sheet_path)
            print(f"wrote {sheet_path}")

    anchors_path = ASSET_ROOT / "luz_ruler_anchors.json"
    if not args.dry_run:
        anchors_path.write_text(json.dumps(frame_anchors, indent=2) + "\n")
        print(f"wrote {anchors_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

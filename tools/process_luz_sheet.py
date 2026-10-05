#!/usr/bin/env python3
"""Repack Luz's raw 4x4 combat/locomotion sheets into gutter-safe, uniform
512x512-cell sheets.

Problem this solves: the original generated sheets are hand-cut with
per-sheet ``safe_cuts`` pixel boundaries (see the previous
``animation_manifest.json``), and those boundaries slice extended ruler tips
into the neighboring cell, so a struck ruler shows truncated in its own frame
and a floating fragment of it shows behind Luz in the next frame.

Approach: segment each *full* source sheet into 8-connected alpha components
(ignoring the nominal grid), then decide which component is the "body" of
each nominal cell (the component with the most pixels inside that cell) and
reassign every other component -- including bleeding ruler-tip fragments --
to whichever cell's body it is geometrically nearest to. A component that
turns out to be the body of two different cells indicates the segmentation
genuinely straddles two poses and is reported as a hard failure rather than
silently merged or split.

Only Pillow is required (no numpy/scipy in this environment).
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

REPO_ROOT = Path(__file__).resolve().parent.parent
SOURCE_DIR = REPO_ROOT / "tools" / "art_sources" / "luz" / "source"
OUTPUT_DIR = REPO_ROOT / "assets" / "player" / "luz"
PREVIEW_DIR = REPO_ROOT / "tools" / "art_sources" / "luz" / "preview"

ALPHA_THRESHOLD = 8
BORDER_MARGIN = 60  # px; how close to a seed cut a pixel must be to count
                     # as border-adjacent for nearest-body distance checks.
COLUMNS = 4
ROWS = 4
OLD_CELL_SIZE = 313  # nominal pre-repack cell size, used only to reproduce
                      # the exact horizontal placement the old catalog used.
OUT_CELL_SIZE = 512
CANVAS_PADDING = 100
FEET_ROW = 413  # canvas row every frame's opaque bottom must land on.

# Seed grids: the *old* per-sheet safe_cuts, used only to seed which
# component is the "body" of each nominal cell. Copied from the previous
# animation_manifest.json (git history, commit 11a7592).
SHEETS: dict[str, dict] = {
    "luz_locomotion_sheet.png": {
        "vertical": [319, 614, 919],
        "horizontal": [339, 656, 966],
        "clips": {
            "idle_breathing": [0, 1, 2, 3],
            "run": [4, 5, 6, 7],
            "jump_ascent": [8, 9],
            "fall": [10, 11],
            "crouch": [12, 13],
            "land": [14, 15],
        },
    },
    "luz_mobility_sheet.png": {
        "vertical": [293, 612, 964],
        "horizontal": [310, 618, 920],
        "clips": {
            "ground_dash": [0, 1, 2, 3],
            "air_dash": [4, 5, 6, 7],
            "wall_cling": [8, 9],
            "wall_jump": [10, 11],
            "ledge_hang": [12, 13],
            "ledge_climb": [14, 15],
        },
    },
    "luz_ground_combat_sheet.png": {
        "vertical": [282, 606, 951],
        "horizontal": [325, 639, 953],
        "clips": {
            "ground_attack_1": [0, 1, 2, 3],
            "ground_attack_2": [4, 5, 6, 7],
            "ground_attack_3": [8, 9, 10, 11],
            "crouch_attack": [12, 13, 14, 15],
        },
    },
    "luz_air_combat_sheet.png": {
        "vertical": [307, 642, 956],
        "horizontal": [321, 620, 917],
        "clips": {
            "up_attack": [0, 1, 2, 3],
            "air_horizontal_attack": [4, 5, 6, 7],
            "plunge": [8, 9, 10, 11],
            "plunge_land": [12, 13, 14, 15],
        },
    },
}


class SegmentationError(RuntimeError):
    pass


def edge_index_table(cuts: list[int], length: int) -> list[int]:
    """Per-pixel-coordinate lookup of which of the 4 grid bands it falls in."""
    edges = [0, cuts[0], cuts[1], cuts[2], length]
    table = [0] * length
    band = 0
    for coordinate in range(length):
        while coordinate >= edges[band + 1] and band < 3:
            band += 1
        table[coordinate] = band
    return table


def label_components(im: Image.Image, vcuts: list[int], hcuts: list[int]):
    """8-connected flood fill over alpha > ALPHA_THRESHOLD across the WHOLE
    sheet (not per cell). Returns:
      labels: flat list[int], 0 = background, 1..N = component id
      cell_counts: dict[label][cell_index] -> pixel count within that cell
      border_pixels: dict[label] -> list[(x, y)] restricted to pixels within
        BORDER_MARGIN of a seed cut (small for big "body" components, full
        for slivers, since bleeding only happens near a cut by definition)
      sizes: dict[label] -> total pixel count
    """
    w, h = im.size
    alpha = im.split()[-1].tobytes()
    col_of = edge_index_table(vcuts, w)
    row_of = edge_index_table(hcuts, h)

    labels = [0] * (w * h)
    sizes: dict[int, int] = {}
    cell_counts: dict[int, dict[int, int]] = {}
    border_pixels: dict[int, list[tuple[int, int]]] = {}
    next_label = 0

    def is_border(x: int, y: int) -> bool:
        for c in vcuts:
            if abs(x - c) <= BORDER_MARGIN:
                return True
        for c in hcuts:
            if abs(y - c) <= BORDER_MARGIN:
                return True
        return False

    for start in range(w * h):
        if alpha[start] <= ALPHA_THRESHOLD or labels[start] != 0:
            continue
        next_label += 1
        lbl = next_label
        labels[start] = lbl
        stack = [start]
        size = 0
        counts: dict[int, int] = {}
        borders: list[tuple[int, int]] = []
        while stack:
            idx = stack.pop()
            size += 1
            y, x = divmod(idx, w)
            cell = row_of[y] * COLUMNS + col_of[x]
            counts[cell] = counts.get(cell, 0) + 1
            if is_border(x, y):
                borders.append((x, y))
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
        cell_counts[lbl] = counts
        border_pixels[lbl] = borders

    return labels, cell_counts, border_pixels, sizes, w, h


def assign_owners(cell_counts: dict[int, dict[int, int]], border_pixels: dict[int, list[tuple[int, int]]], sheet_name: str) -> dict[int, int]:
    """Decide which nominal cell (0..15) owns each component label."""
    body_of_cell: dict[int, int] = {}
    for cell in range(COLUMNS * ROWS):
        best_label = None
        best_count = -1
        for label, counts in cell_counts.items():
            count = counts.get(cell, 0)
            if count > best_count:
                best_count = count
                best_label = label
        if best_label is not None:
            body_of_cell[cell] = best_label

    bodies_by_label: dict[int, list[int]] = {}
    for cell, label in body_of_cell.items():
        bodies_by_label.setdefault(label, []).append(cell)

    spanning = {label: cells for label, cells in bodies_by_label.items() if len(cells) > 1}
    if spanning:
        details = "; ".join(
            f"label {label} is the body of cells {cells} (counts={cell_counts[label]})"
            for label, cells in spanning.items()
        )
        raise SegmentationError(
            f"{sheet_name}: component(s) genuinely span two cells' bodies -- {details}. "
            "Refusing to silently merge; adjust the seed grid or inspect the source art."
        )

    label_is_body_cell = {label: cells[0] for label, cells in bodies_by_label.items()}

    owner: dict[int, int] = {}
    for label, counts in cell_counts.items():
        if label in label_is_body_cell:
            owner[label] = label_is_body_cell[label]
            continue
        candidates = list(counts.keys())
        if len(candidates) == 1:
            owner[label] = candidates[0]
            continue
        # Fragment touching multiple cells' rects: assign to whichever
        # cell's body is nearest (min squared distance between the
        # fragment's border-adjacent pixels and that body's).
        frag_pixels = border_pixels.get(label, [])
        best_cell = None
        best_dist = None
        for cell in candidates:
            body_label = body_of_cell.get(cell)
            if body_label is None:
                continue
            body_pixels = border_pixels.get(body_label, [])
            dist = _min_sq_distance(frag_pixels, body_pixels)
            if dist is None:
                continue
            if best_dist is None or dist < best_dist:
                best_dist = dist
                best_cell = cell
        if best_cell is None:
            # No distance could be computed (degenerate); fall back to the
            # cell where it has the most pixels -- a tiny speck keeps
            # nearest-body ownership by construction here too.
            best_cell = max(candidates, key=lambda c: counts[c])
        owner[label] = best_cell

    return owner


def _min_sq_distance(a: list[tuple[int, int]], b: list[tuple[int, int]]):
    if not a or not b:
        return None
    best = None
    # Both lists are border-restricted (small), so brute force is fine.
    for ax, ay in a:
        for bx, by in b:
            d = (ax - bx) ** 2 + (ay - by) ** 2
            if best is None or d < best:
                best = d
    return best


def build_owner_image(labels: list[int], owner: dict[int, int], w: int, h: int) -> Image.Image:
    lut = {0: 0}
    for label, cell in owner.items():
        lut[label] = cell + 1
    owner_bytes = bytearray(w * h)
    for i, lbl in enumerate(labels):
        owner_bytes[i] = lut.get(lbl, 0)
    return Image.frombytes("L", (w, h), bytes(owner_bytes))


def process_sheet(sheet_name: str, config: dict, verbose: bool = True) -> dict:
    src_path = SOURCE_DIR / sheet_name
    im = Image.open(src_path).convert("RGBA")
    vcuts, hcuts = config["vertical"], config["horizontal"]

    labels, cell_counts, border_pixels, sizes, w, h = label_components(im, vcuts, hcuts)
    owner = assign_owners(cell_counts, border_pixels, sheet_name)
    owner_img = build_owner_image(labels, owner, w, h)

    transparent = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out_sheet = Image.new("RGBA", (COLUMNS * OUT_CELL_SIZE, ROWS * OUT_CELL_SIZE), (0, 0, 0, 0))

    frame_reports = []
    for cell in range(COLUMNS * ROWS):
        col = cell % COLUMNS
        row = cell // COLUMNS
        lut = [0] * 256
        lut[cell + 1] = 255
        mask = owner_img.point(lut)
        bbox = mask.getbbox()
        if bbox is None:
            raise SegmentationError(f"{sheet_name}: cell {cell} has no owned pixels at all")
        frame_rgba = Image.composite(im, transparent, mask)
        region = frame_rgba.crop(bbox)
        region_w, region_h = region.size

        leading_x = CANVAS_PADDING + (bbox[0] - col * OLD_CELL_SIZE)
        leading_y = FEET_ROW - (region_h - 1)

        if leading_x < 0 or leading_y < 0:
            raise SegmentationError(
                f"{sheet_name}: frame {cell} placement out of bounds "
                f"(leading=({leading_x},{leading_y}), region={bbox})"
            )
        if leading_x + region_w > OUT_CELL_SIZE or leading_y + region_h > OUT_CELL_SIZE:
            raise SegmentationError(
                f"{sheet_name}: frame {cell} region {region_w}x{region_h} at "
                f"({leading_x},{leading_y}) overflows the {OUT_CELL_SIZE}px cell"
            )

        dest_x = col * OUT_CELL_SIZE + leading_x
        dest_y = row * OUT_CELL_SIZE + leading_y
        out_sheet.paste(region, (dest_x, dest_y), region)

        frame_reports.append({
            "cell": cell,
            "source_bbox": bbox,
            "leading": (leading_x, leading_y),
            "size": (region_w, region_h),
        })
        if verbose:
            print(f"  frame {cell:2d}: source_bbox={bbox} leading=({leading_x},{leading_y}) size=({region_w}x{region_h})")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    out_path = OUTPUT_DIR / sheet_name
    out_sheet.save(out_path)
    if verbose:
        print(f"  wrote {out_path} ({out_sheet.size[0]}x{out_sheet.size[1]})")

    return {
        "sheet": sheet_name,
        "component_count": len(sizes),
        "frames": frame_reports,
        "out_sheet": out_sheet,
    }


def _load_font():
    try:
        return ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 20)
    except OSError:
        return ImageFont.load_default()


def render_contact_sheet(sheet_name: str, out_sheet: Image.Image, dest: Path) -> None:
    contact = out_sheet.convert("RGBA").copy()
    draw = ImageDraw.Draw(contact)
    font = _load_font()
    for cell in range(COLUMNS * ROWS):
        col = cell % COLUMNS
        row = cell // COLUMNS
        x0, y0 = col * OUT_CELL_SIZE, row * OUT_CELL_SIZE
        x1, y1 = x0 + OUT_CELL_SIZE - 1, y0 + OUT_CELL_SIZE - 1
        draw.rectangle([x0, y0, x1, y1], outline=(255, 0, 255, 255), width=2)
        draw.line([(x0, y0 + FEET_ROW), (x1, y0 + FEET_ROW)], fill=(0, 200, 255, 180), width=1)
        draw.text((x0 + 6, y0 + 6), str(cell), fill=(255, 255, 0, 255), font=font)
    contact.save(dest)


def render_onion_skins(sheet_name: str, out_sheet: Image.Image, clips: dict, dest_dir: Path) -> None:
    for clip_name, indices in clips.items():
        canvas = Image.new("RGBA", (OUT_CELL_SIZE, OUT_CELL_SIZE), (30, 30, 34, 255))
        n = len(indices)
        for i, frame_index in enumerate(indices):
            col = frame_index % COLUMNS
            row = frame_index // COLUMNS
            cell_img = out_sheet.crop((
                col * OUT_CELL_SIZE, row * OUT_CELL_SIZE,
                (col + 1) * OUT_CELL_SIZE, (row + 1) * OUT_CELL_SIZE,
            ))
            alpha_scale = 1.0 if i == n - 1 else 0.35
            r, g, b, a = cell_img.split()
            a = a.point(lambda v, s=alpha_scale: int(v * s))
            faded = Image.merge("RGBA", (r, g, b, a))
            canvas.alpha_composite(faded)
        draw = ImageDraw.Draw(canvas)
        draw.line([(0, FEET_ROW), (OUT_CELL_SIZE, FEET_ROW)], fill=(255, 0, 255, 200), width=1)
        draw.text((6, 6), f"{sheet_name}:{clip_name}", fill=(255, 255, 0, 255), font=_load_font())
        canvas.save(dest_dir / f"{sheet_name.replace('.png', '')}__{clip_name}.png")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sheet", action="append", help="Only process this sheet (repeatable); default: all")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()

    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    gitignore = PREVIEW_DIR / ".gitignore"
    gitignore.write_text("*\n")

    targets = args.sheet if args.sheet else list(SHEETS.keys())
    failures = []
    for sheet_name in targets:
        config = SHEETS[sheet_name]
        print(f"Processing {sheet_name}...")
        try:
            result = process_sheet(sheet_name, config, verbose=not args.quiet)
        except SegmentationError as exc:
            print(f"  FAILED: {exc}", file=sys.stderr)
            failures.append(str(exc))
            continue
        contact_dest = PREVIEW_DIR / f"{sheet_name.replace('.png', '')}__contact_sheet.png"
        render_contact_sheet(sheet_name, result["out_sheet"], contact_dest)
        render_onion_skins(sheet_name, result["out_sheet"], config["clips"], PREVIEW_DIR)
        print(f"  {result['component_count']} components; preview -> {contact_dest}")

    if failures:
        print(f"\n{len(failures)} sheet(s) failed segmentation:", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1
    print("\nAll sheets processed successfully.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

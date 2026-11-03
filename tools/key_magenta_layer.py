#!/usr/bin/env python3
"""Key a flat magenta (#FF00FF) region out of a generated layer into alpha.

Used for the main menu architecture layer: the arch opening is painted solid
magenta by the generator and becomes transparent here, so the far vista layer
shows through it in-engine.

Usage:
    python3.13 tools/key_magenta_layer.py <input.png> <output.png>
"""
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageFilter

# Magenta score = min(red, blue) - green. Pure magenta scores 255; stone,
# shadows and warm gold light score near zero or below. Scores between the two
# thresholds become partially transparent (anti-aliased edges).
KEY_SOFT_START = 70
KEY_HARD_END = 170
# How much of the remaining magenta tint is removed from edge pixels.
DESPILL_STRENGTH = 1.0


def magenta_score(red: int, green: int, blue: int) -> int:
    return min(red, blue) - green


def key_alpha(score: int) -> int:
    if score <= KEY_SOFT_START:
        return 255
    if score >= KEY_HARD_END:
        return 0
    t = (score - KEY_SOFT_START) / (KEY_HARD_END - KEY_SOFT_START)
    return round(255 * (1.0 - t))


def despill(red: int, green: int, blue: int) -> tuple[int, int, int]:
    spill = magenta_score(red, green, blue)
    if spill <= 0:
        return red, green, blue
    cut = round(spill * DESPILL_STRENGTH)
    return max(red - cut, 0), green, max(blue - cut, 0)


def key_layer(source: Image.Image) -> Image.Image:
    rgba = source.convert("RGBA")
    pixels = rgba.load()
    width, height = rgba.size
    for y in range(height):
        for x in range(width):
            red, green, blue, alpha = pixels[x, y]
            keyed = min(alpha, key_alpha(magenta_score(red, green, blue)))
            if keyed == 0:
                pixels[x, y] = (0, 0, 0, 0)
                continue
            red, green, blue = despill(red, green, blue)
            pixels[x, y] = (red, green, blue, keyed)

    # Remove isolated speckles the generator left inside the key region and
    # pull the edge in by one pixel so no magenta fringe survives.
    alpha = rgba.getchannel("A").filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(3))
    alpha = alpha.filter(ImageFilter.MinFilter(3))
    rgba.putalpha(alpha)
    return rgba


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    keyed = key_layer(Image.open(args.input))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    keyed.save(args.output)
    transparent = keyed.getchannel("A").histogram()[0]
    total = keyed.width * keyed.height
    print(f"{args.output} {keyed.width}x{keyed.height} transparent={transparent / total:.1%}")


if __name__ == "__main__":
    main()

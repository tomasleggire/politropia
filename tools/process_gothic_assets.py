#!/usr/bin/env python3
"""Prepare generated gothic artwork for the in-game mobile asset budget."""

from pathlib import Path

from PIL import Image, ImageEnhance


ROOT = Path(__file__).resolve().parents[1]


def prepare_background() -> None:
    source = ROOT / "tools/art_sources/library_background_source.png"
    output = ROOT / "assets/art/gothic/library_background.png"
    image = Image.open(source).convert("RGB")

    target_ratio = 16 / 9
    current_ratio = image.width / image.height
    if current_ratio > target_ratio:
        width = round(image.height * target_ratio)
        left = (image.width - width) // 2
        image = image.crop((left, 0, left + width, image.height))
    else:
        height = round(image.width / target_ratio)
        top = (image.height - height) // 2
        image = image.crop((0, top, image.width, top + height))

    image = image.resize((1280, 720), Image.Resampling.LANCZOS)
    image = ImageEnhance.Contrast(image).enhance(1.06)
    image.save(output, optimize=True)


def prepare_stone() -> None:
    source = ROOT / "tools/art_sources/stone_tile_source.png"
    output = ROOT / "assets/art/gothic/stone_tile.png"
    image = Image.open(source).convert("RGB")
    image = image.resize((256, 256), Image.Resampling.LANCZOS)
    image = ImageEnhance.Contrast(image).enhance(1.08)
    image.save(output, optimize=True)


def prepare_wanderer() -> None:
    source = ROOT / "tools/art_sources/wanderer_sheet_source.png"
    output = ROOT / "assets/player/gothic/wanderer_sheet.png"
    image = Image.open(source).convert("RGBA")
    # Keep the exact 4x2 grid while reducing memory and retaining hard pixel edges.
    image = image.resize((768, 512), Image.Resampling.NEAREST)
    image.save(output, optimize=True)


if __name__ == "__main__":
    prepare_background()
    prepare_stone()
    prepare_wanderer()

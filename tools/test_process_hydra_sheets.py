#!/usr/bin/env python3
"""Synthetic checks of the behaviours of tools/process_hydra_sheets.py that the real sheets only
show indirectly. No game assets are read or written.

Run: python tools/test_process_hydra_sheets.py   (needs Pillow, numpy and scipy)
"""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

import process_hydra_sheets as hydra

MAGENTA = (255, 0, 255)


def sheet(width=120, height=120) -> np.ndarray:
    arr = np.zeros((height, width, 3), dtype=np.uint8)
    arr[:] = MAGENTA
    return arr


def paint(arr: np.ndarray, box: tuple[int, int, int, int], colour: tuple[int, int, int]) -> None:
    x0, y0, x1, y1 = box
    arr[y0:y1, x0:x1] = colour


def outlined_figure(arr: np.ndarray, box: tuple[int, int, int, int], fill: tuple[int, int, int], outline_px=4) -> None:
    paint(arr, box, tuple(int(v) for v in hydra.OUTLINE))
    x0, y0, x1, y1 = box
    paint(arr, (x0 + outline_px, y0 + outline_px, x1 - outline_px, y1 - outline_px), fill)


class KeyBackgroundTest(unittest.TestCase):
    def test_violet_inside_an_outline_stays_opaque(self):
        arr = sheet()
        outlined_figure(arr, (20, 20, 100, 100), (150, 60, 190))  # a violet crest: min(r, b) - g = 90
        keyed = hydra.key_background(Image.fromarray(arr))
        self.assertEqual(keyed[60, 60, 3], 255.0)
        self.assertEqual(tuple(keyed[60, 60, :3]), (150, 60, 190))
        self.assertEqual(keyed[5, 5, 3], 0.0)

    def test_enclosed_magenta_pocket_is_background(self):
        arr = sheet()
        outlined_figure(arr, (10, 10, 110, 110), (40, 120, 90), outline_px=4)
        paint(arr, (50, 50, 62, 62), MAGENTA)  # a pocket between two loops
        keyed = hydra.key_background(Image.fromarray(arr))
        self.assertEqual(keyed[55, 55, 3], 0.0)

    def test_edge_pixel_loses_its_pink_tint(self):
        arr = sheet()
        outlined_figure(arr, (20, 20, 100, 100), (40, 120, 90))
        arr[19, 50] = [(a + b) // 2 for a, b in zip(hydra.OUTLINE, MAGENTA)]  # half outline, half magenta
        keyed = hydra.key_background(Image.fromarray(arr))
        self.assertAlmostEqual(keyed[19, 50, 3], 127.0, delta=6.0)
        self.assertEqual(tuple(keyed[19, 50, :3]), tuple(hydra.OUTLINE))


class ColourMatchTest(unittest.TestCase):
    def test_defeat_greens_move_to_the_body_greens_and_the_ochre_stays(self):
        body = np.zeros((40, 40, 4), dtype=np.float32)
        body[..., :3] = (45, 110, 85)
        body[..., 3] = 255
        defeat = body.copy()
        defeat[..., :3] = (85, 120, 105)  # lighter and greyer
        defeat[:10, :, :3] = (232, 184, 96)  # ochre belly
        matched = hydra.match_greens(defeat, body)
        self.assertTrue(np.allclose(matched[20, 20, :3], body[20, 20, :3], atol=3.0))
        self.assertTrue(np.allclose(matched[2, 2, :3], (232, 184, 96), atol=1.0))


class FramesTest(unittest.TestCase):
    def test_an_emptied_cell_is_an_error_naming_the_cell(self):
        with tempfile.TemporaryDirectory() as directory:
            arr = sheet(120, 60)
            outlined_figure(arr, (5, 5, 55, 55), (40, 120, 90))
            speck = (80, 20, 84, 24)  # smaller than MIN_COMPONENT_PX: removed, the cell is empty
            outlined_figure(arr, speck, (40, 120, 90), outline_px=1)
            Image.fromarray(arr).save(Path(directory) / "hydra_toy_raw.png")
            old = hydra.RAW_DIR
            hydra.RAW_DIR = Path(directory)
            try:
                with self.assertRaisesRegex(ValueError, r"toy: cell 1"):
                    hydra.load_frames("toy", (2, 1), {"idle": [0, 1]})
            finally:
                hydra.RAW_DIR = old

    def test_cells_are_indexed_by_raw_cell_number(self):
        with tempfile.TemporaryDirectory() as directory:
            arr = sheet(180, 60)
            outlined_figure(arr, (5, 5, 55, 55), (40, 120, 90))
            outlined_figure(arr, (125, 5, 175, 55), (40, 120, 90))  # cell 2; cell 1 is unused
            Image.fromarray(arr).save(Path(directory) / "hydra_toy_raw.png")
            old = hydra.RAW_DIR
            hydra.RAW_DIR = Path(directory)
            try:
                frames = hydra.load_frames("toy", (3, 1), {"idle": [0, 2]})
            finally:
                hydra.RAW_DIR = old
        self.assertEqual(sorted(frames), [0, 2])


class OutlineTest(unittest.TestCase):
    def figure(self, outline_px: int) -> np.ndarray:
        arr = sheet(120, 120)
        outlined_figure(arr, (20, 20, 100, 100), (40, 150, 120), outline_px=outline_px)
        keyed = hydra.key_background(Image.fromarray(arr))
        ys, xs = np.where(keyed[..., 3] > 20)
        return keyed[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1]

    def test_thickness_follows_the_drawn_outline(self):
        thin = hydra.outline_thickness(self.figure(2), 0.3)
        thick = hydra.outline_thickness(self.figure(8), 0.3)
        self.assertAlmostEqual(thin, 0.6, delta=0.15)
        self.assertGreater(thick, 2.0)

    def test_erosion_only_removes_outline_and_growth_adds_outline_colour(self):
        figure = self.figure(8)
        eroded = hydra.restyle_outline(figure, -4.0, True)
        self.assertAlmostEqual(hydra.outline_thickness(eroded, 0.3), 0.3 * 4, delta=0.3)
        centre = eroded[eroded.shape[0] // 2, eroded.shape[1] // 2]
        self.assertEqual(tuple(centre[:3]), (40, 150, 120))  # the colour area is untouched
        grown = hydra.restyle_outline(figure, 3.0, True)
        self.assertEqual(grown.shape[0], figure.shape[0] + 6)
        self.assertEqual(tuple(grown[1, grown.shape[1] // 2, :3]), tuple(hydra.OUTLINE.astype(int)))

    def test_an_erosion_that_would_eat_colour_is_refused(self):
        with self.assertRaisesRegex(ValueError, "eating colour"):
            self._force(self.figure(3))

    def _force(self, thin):
        old = hydra.OUTLINE_TARGET
        hydra.OUTLINE_TARGET = 0.01
        try:
            return hydra.solve_radius(thin, 1.0, True, "toy")
        finally:
            hydra.OUTLINE_TARGET = old


class MarginTest(unittest.TestCase):
    def test_art_near_a_cell_edge_stops_the_script(self):
        cell = 64
        image = Image.new("RGBA", (cell * 2, cell), (0, 0, 0, 0))
        image.paste((255, 255, 255, 255), (cell + 3, 20, cell + 30, 40))  # 3 px from the left edge of cell 1
        with self.assertRaisesRegex(ValueError, r"cell 1 \(3 px\)"):
            hydra.check_margins(image, cell, "toy")
        roomy = Image.new("RGBA", (cell * 2, cell), (0, 0, 0, 0))
        roomy.paste((255, 255, 255, 255), (cell + 20, 20, cell + 40, 40))
        hydra.check_margins(roomy, cell, "toy")


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Synthetic checks of the shared boss pipeline helpers and of El Topo's processing that the real
sheets only show indirectly. No game assets are read or written.

Run: python tools/test_process_boss_sheets.py   (needs Pillow, numpy and scipy)
"""

from __future__ import annotations

import unittest

import numpy as np
from PIL import Image
from scipy import ndimage

import boss_sheet_pipeline as pipeline
import process_blind_beast_sheets as topo


def solid(width: int, height: int, rgb: tuple[int, int, int]) -> np.ndarray:
    frame = np.zeros((height, width, 4), dtype=np.float32)
    frame[..., :3] = rgb
    frame[..., 3] = 255.0
    return frame


def lab_of(rgb: tuple[int, int, int]) -> np.ndarray:
    return pipeline.rgb_to_lab(np.array(rgb, dtype=np.float64))


class LabTest(unittest.TestCase):
    def test_round_trip(self):
        rgb = np.array([[200.0, 90.0, 40.0], [20.0, 30.0, 200.0]])
        back = pipeline.lab_to_rgb(pipeline.rgb_to_lab(rgb))
        self.assertTrue(np.allclose(back, rgb, atol=1.0))

    def test_hue_arc_and_complement_sum_to_one(self):
        lab = np.array([[50.0, 20.0 * np.cos(np.radians(h)), 20.0 * np.sin(np.radians(h))] for h in range(0, 360, 7)])
        cool = pipeline.hue_class_weight(lab, 255.0, 350.0, 15.0)
        warm = pipeline.hue_class_weight(lab, 350.0, 255.0, 15.0)
        self.assertTrue(np.allclose(cool + warm, 1.0))
        self.assertEqual(float(pipeline.hue_class_weight(lab[[43]], 255.0, 350.0, 15.0)[0]), 1.0)  # hue 301


class MatchTonesTest(unittest.TestCase):
    centres = np.arange(10.0, 90.0, 4.0)
    tone = {"fade_start": 28.0, "fade_width": 12.0}

    def stats(self, frames):
        return pipeline.tone_band_means(frames, self.tone, self.centres, 4.0, 50.0)

    def test_muted_tone_moves_to_the_reference_and_the_accent_stays(self):
        reference = [solid(40, 40, (120, 90, 80))]
        sheet = solid(40, 40, (110, 90, 100))  # same lightness, more purple
        sheet[:6, :6, :3] = (200, 30, 50)  # a saturated accent (a tie)
        accent = sheet[0, 0].copy()
        out = pipeline.match_tones([sheet], [self.stats(reference)], [self.tone], self.centres, 4.0, 50.0)[0]
        before = lab_of((110, 90, 100))
        after = pipeline.rgb_to_lab(out[20, 20, :3].astype(np.float64))
        target = lab_of((120, 90, 80))
        self.assertLess(abs(after[1] - target[1]) + abs(after[2] - target[2]), abs(before[1] - target[1]) + abs(before[2] - target[2]))
        self.assertTrue(np.array_equal(out[0, 0], accent))

    def test_alpha_and_none_frames_survive_and_the_result_is_deterministic(self):
        reference = [self.stats([solid(30, 30, (120, 90, 80))])]
        frame = solid(30, 30, (110, 90, 100))
        frame[:5] = (0, 0, 0, 0)
        a = pipeline.match_tones([frame, None], reference, [self.tone], self.centres, 4.0, 50.0)
        b = pipeline.match_tones([frame, None], reference, [self.tone], self.centres, 4.0, 50.0)
        self.assertIsNone(a[1])
        self.assertTrue(np.array_equal(a[0][..., 3], frame[..., 3]))
        self.assertTrue(np.array_equal(a[0], b[0]))


class UnmixFringeTest(unittest.TestCase):
    outline = np.array([27.0, 15.0, 21.0], dtype=np.float32)

    def test_half_magenta_edge_becomes_half_transparent_outline(self):
        rgb = np.zeros((9, 9, 3), dtype=np.float32)
        rgb[:] = pipeline.MAGENTA
        rgb[:, 4:] = self.outline
        rgb[4, 3] = (self.outline + pipeline.MAGENTA) / 2.0
        background = np.zeros((9, 9), dtype=bool)
        background[:, :3] = True
        alpha, colour, unmixed = pipeline.unmix_fringe(rgb, background, self.outline)
        self.assertTrue(unmixed[4, 3])
        self.assertAlmostEqual(float(alpha[4, 3]), 0.5, delta=0.02)
        self.assertTrue(np.array_equal(colour[4, 3], self.outline))

    def test_art_colour_next_to_the_background_is_left_alone(self):
        rgb = np.zeros((9, 9, 3), dtype=np.float32)
        rgb[:] = pipeline.MAGENTA
        rgb[:, 3:] = (40, 160, 70)  # green art touching the background with no outline
        background = np.zeros((9, 9), dtype=bool)
        background[:, :3] = True
        _, _, unmixed = pipeline.unmix_fringe(rgb, background, self.outline)
        self.assertFalse(unmixed.any())

    def test_dark_purple_brown_edge_pixel_is_read_as_a_blend_today(self):
        # Pins today's behaviour, not a wish: a dark purple-brown art pixel on the silhouette edge
        # (here 64, 40, 56) lies within UNMIX_RESIDUAL of the outline-magenta line, so it is taken
        # for about 15 percent magenta: it becomes the outline colour and loses about 15 percent of
        # its alpha. Real art that dark, right at the edge, is therefore darkened.
        rgb = np.zeros((9, 9, 3), dtype=np.float32)
        rgb[:] = pipeline.MAGENTA
        rgb[:, 4:] = self.outline
        rgb[4, 3] = (64, 40, 56)
        background = np.zeros((9, 9), dtype=bool)
        background[:, :3] = True
        alpha, colour, unmixed = pipeline.unmix_fringe(rgb, background, self.outline)
        self.assertTrue(unmixed[4, 3])
        self.assertAlmostEqual(float(alpha[4, 3]), 0.85, delta=0.03)
        self.assertTrue(np.array_equal(colour[4, 3], self.outline))

    def test_despill_edges_changes_only_the_fringe(self):
        outline = np.array([27.0, 15.0, 21.0], dtype=np.float32)
        raw = np.zeros((20, 20, 3), dtype=np.uint8)
        raw[:] = (255, 0, 255)
        raw[5:15, 5:15] = (27, 15, 21)
        raw[6:14, 6:14] = (150, 110, 60)
        raw[10, 4] = (50, 13, 44)  # 10 percent magenta over the outline: keyed almost opaque, tinted
        image = Image.fromarray(raw)
        keyed = pipeline.key_magenta(image)
        out = pipeline.despill_edges(image, keyed, outline)
        self.assertGreater(keyed[10, 4, 3], 200.0)
        self.assertLess(out[10, 4, 3], keyed[10, 4, 3] - 10.0)  # strictly more transparent
        self.assertTrue(np.array_equal(out[10, 4, :3], outline))  # and the outline colour again
        background = keyed[..., 3] <= 0.0
        band = ndimage.binary_dilation(background, structure=np.ones((3, 3)), iterations=pipeline.FRINGE_PX) & ~background
        self.assertTrue(np.array_equal(out[~band], keyed[~band]))

    def test_estimate_outline_reads_the_contour(self):
        frame = solid(30, 30, (150, 110, 60))
        frame[:3] = frame[-3:] = (30, 20, 25, 255)
        frame[:, :3] = frame[:, -3:] = (30, 20, 25, 255)
        self.assertTrue(np.allclose(pipeline.estimate_outline(frame), (30, 20, 25), atol=1.0))

    def test_estimate_outline_without_a_solid_pixel_names_the_problem(self):
        frame = solid(30, 30, (150, 110, 60))
        frame[..., 3] = 200.0  # nothing above the solid threshold
        with self.assertRaisesRegex(ValueError, "no solid pixel"):
            pipeline.estimate_outline(frame)
        raw = Image.fromarray(np.full((8, 8, 3), (255, 0, 255), dtype=np.uint8))
        with self.assertRaisesRegex(ValueError, "no solid pixel"):
            pipeline.despill_edges(raw, pipeline.key_magenta(raw))


class StagHelpersTest(unittest.TestCase):
    def test_distant_speck_goes_and_a_near_wisp_stays(self):
        frame = np.zeros((60, 200, 4), dtype=np.float32)
        frame[20:40, 20:100, 3] = 255.0  # body
        frame[25:30, 105:112, 3] = 255.0  # a wisp 5 px away
        frame[25:30, 180:187, 3] = 255.0  # a speck 80 px away
        out = pipeline.drop_distant_specks(frame, 24.0, 150)
        self.assertGreater(out[27, 108, 3], 0.0)
        self.assertEqual(out[27, 183, 3], 0.0)
        self.assertTrue(np.array_equal(out[20:40, 20:100], frame[20:40, 20:100]))

    def test_wide_cell_keeps_a_frame_whole_with_feet_on_the_centre(self):
        frame = solid(300, 100, (200, 200, 220))
        cell = pipeline.to_cell(frame, 1.0, "wide", 512, 340, False, 384)
        self.assertEqual(cell.size, (512, 384))
        box = cell.getchannel("A").getbbox()
        self.assertEqual(box[2] - box[0], 300)
        self.assertEqual(box[3], 341)


class EffectClipSheetTest(unittest.TestCase):
    def cells(self) -> list[np.ndarray]:
        out = []
        for width in (200, 150, 120, 60):  # one effect, a shared start on the left and a shared floor
            cell = np.zeros((100, 300, 4), dtype=np.float32)
            cell[40:90, 20 : 20 + width, :3] = (240, 200, 120)
            cell[40:90, 20 : 20 + width, 3] = 255.0
            out.append(cell)
        return out

    def test_one_row_of_non_square_cells_with_a_shared_box(self):
        image, clips = pipeline.effect_clip_sheet(self.cells(), {"swipe": [0, 1, 2, 3]}, 0.5, 130, 44, "test")
        self.assertEqual(image.size, (4 * 130, 44))
        self.assertEqual(clips, {"swipe": [0, 1, 2, 3]})
        entry = pipeline.manifest_entry(image, 130, clips, {}, 44)
        self.assertEqual(entry["grid"], {"columns": 4, "rows": 1, "cell_width": 130, "cell_height": 44})
        self.assertEqual(pipeline.clip_contents(image, 130, clips, 44), {"swipe": [100, 25]})
        # the frames keep their left edge and floor: the narrower ones end earlier
        boxes = [image.crop((i * 130, 0, (i + 1) * 130, 44)).getchannel("A").getbbox() for i in range(4)]
        self.assertEqual({box[0] for box in boxes}, {boxes[0][0]})
        self.assertEqual({box[3] for box in boxes}, {boxes[0][3]})

    def test_an_effect_without_the_margin_stops_with_the_cell_named(self):
        with self.assertRaisesRegex(ValueError, "margin"):
            pipeline.effect_clip_sheet(self.cells(), {"swipe": [0, 1, 2, 3]}, 0.5, 108, 44, "test")

    def test_an_empty_clip_is_named(self):
        cells = self.cells()
        cells[2][...] = 0.0
        with self.assertRaisesRegex(ValueError, "test clip 'swipe'"):
            pipeline.effect_clip_sheet([cells[2]] * 4, {"swipe": [0, 1, 2, 3]}, 0.5, 130, 44, "test")


class PinkLeakTest(unittest.TestCase):
    def sheet(self) -> np.ndarray:
        rgba = np.zeros((120, 160, 4), dtype=np.float32)
        rgba[40:100, 20:60, :3] = (110, 75, 40)  # brown column
        rgba[40:100, 20:60, 3] = 255.0
        rgba[60:84, 60:72, :3] = (228, 180, 195)  # pale pink pocket beside it, open to the background
        rgba[60:84, 60:72, 3] = 255.0
        rgba[30:100, 100:150, :3] = (30, 20, 25)  # dust puff with a dark outline ...
        rgba[30:100, 100:150, 3] = 255.0
        rgba[34:96, 104:146, :3] = (232, 200, 215)  # ... painted pale pink
        return rgba

    def test_open_pink_pocket_is_cleared(self):
        out = topo.clear_pink_leaks(self.sheet())
        self.assertEqual(float(out[72, 66, 3]), 0.0)
        self.assertEqual(float(out[70, 40, 3]), 255.0)  # the column stays

    def test_enclosed_pink_puff_turns_beige_and_stays(self):
        out = topo.clear_pink_leaks(self.sheet())
        r, g, b = (float(v) for v in out[60, 125, :3])
        self.assertEqual(float(out[60, 125, 3]), 255.0)
        self.assertGreaterEqual(g - b, topo.LEAK_BEIGE_GAP - 1)  # beige: green well above blue
        self.assertLessEqual(r - g, topo.LEAK_PUFF_RED_OVER_GREEN)

    def test_docstring_names_the_cases_it_handles(self):
        for word in ("magenta", "bled", "beige"):
            self.assertIn(word, topo.clear_pink_leaks.__doc__)


class ClawSpeckTest(unittest.TestCase):
    def sheet(self) -> np.ndarray:
        rgba = np.zeros((90, 160, 4), dtype=np.float32)
        rgba[50:80, 10:120, :3] = (185, 172, 156)  # dust
        rgba[50:80, 10:120, 3] = 255.0
        rgba[40:50, 50:70, :3] = (154, 127, 99)  # earth pebble on the dust
        rgba[40:50, 50:70, 3] = 255.0
        rgba[10:20, 130:140, :3] = (26, 20, 16)  # a floating pebble: outline ...
        rgba[10:20, 130:140, 3] = 255.0
        rgba[12:18, 132:138, :3] = (195, 109, 109)  # ... around a pink core
        rgba[22:30, 20:28, :3] = (201, 166, 120)  # a floating bone chip
        rgba[22:30, 20:28, 3] = 255.0
        rgba[44, 52, :3] = (195, 109, 109)  # one pink pixel on the earth pebble
        return rgba

    def test_floating_pink_speck_is_removed_with_its_outline(self):
        out = topo.clear_claw_pink_specks(self.sheet())
        self.assertEqual(float(out[15, 135, 3]), 0.0)
        self.assertEqual(float(out[10, 130, 3]), 0.0)

    def test_palette_pieces_are_untouched(self):
        sheet = self.sheet()
        out = topo.clear_claw_pink_specks(sheet)
        for y, x in ((60, 60), (45, 60), (25, 24)):
            self.assertEqual(tuple(out[y, x]), tuple(sheet[y, x]))

    def test_pink_on_an_attached_piece_stays(self):
        out = topo.clear_claw_pink_specks(self.sheet())
        self.assertEqual(float(out[44, 52, 3]), 255.0)

    def test_only_alpha_changes(self):
        sheet = self.sheet()
        out = topo.clear_claw_pink_specks(sheet)
        self.assertTrue(np.array_equal(out[..., :3], sheet[..., :3]))

    def test_palette_colours_are_not_pink(self):
        for rgb in ((242, 226, 192), (255, 246, 224), (201, 166, 120), (74, 58, 48), (110, 86, 68), (154, 127, 99), (185, 172, 156), (26, 20, 16)):
            sheet = solid(8, 8, rgb)
            self.assertTrue(np.array_equal(topo.clear_claw_pink_specks(sheet), sheet), rgb)


class HeldFramesTest(unittest.TestCase):
    def test_a_clip_that_repeats_a_cell_keeps_one_cell_on_the_sheet(self):
        used, clips = pipeline.compact_clips({"intro": [0, 0, 1, 1, 2]})
        self.assertEqual(used, [0, 1, 2])
        self.assertEqual(clips["intro"], [0, 0, 1, 1, 2])

    def test_clip_contents_ignores_the_repeats(self):
        image = Image.new("RGBA", (40, 20), (0, 0, 0, 0))
        image.paste((255, 255, 255, 255), (2, 4, 8, 12))
        image.paste((255, 255, 255, 255), (22, 2, 30, 10))
        self.assertEqual(pipeline.clip_contents(image, 20, {"c": [0, 0, 0, 1]}), pipeline.clip_contents(image, 20, {"c": [0, 1]}))

    def test_the_topo_intro_holds_the_old_man(self):
        clip = topo.SHEETS["intro"]["clips"]["intro"]
        self.assertEqual(sorted(set(clip)), list(range(8)))
        self.assertAlmostEqual(clip.count(0) / len(clip), 1 / 3, delta=0.01)
        self.assertAlmostEqual(clip.count(1) / len(clip), 1 / 6, delta=0.01)
        self.assertEqual(clip[6:], [2, 3, 4, 5, 6, 7])


if __name__ == "__main__":
    unittest.main()

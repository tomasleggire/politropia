#!/usr/bin/env python3
"""Procedural SFX generator for politropia (stdlib only)."""

import math
import random
import struct
import wave
from pathlib import Path

SAMPLE_RATE = 22050
OUTPUT_DIR = Path(__file__).resolve().parent


def clamp(x: float, lo: float = -1.0, hi: float = 1.0) -> float:
    return max(lo, min(hi, x))


def write_wav(path: Path, samples: list[float]) -> None:
    with wave.open(str(path), "w") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        frames = b"".join(
            struct.pack("<h", int(clamp(s) * 32767)) for s in samples
        )
        wf.writeframes(frames)


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def exp_decay(t: float, rate: float) -> float:
    return math.exp(-rate * t)


def smoothstep(edge0: float, edge1: float, x: float) -> float:
    if edge0 == edge1:
        return 0.0 if x <= edge0 else 1.0
    t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def make_wall_bonk() -> list[float]:
    duration = 0.18
    n = int(SAMPLE_RATE * duration)
    rng = random.Random(42)
    samples: list[float] = []

    for i in range(n):
        t = i / SAMPLE_RATE
        progress = t / duration

        # Descending chirp: quick drop from ~520 Hz to ~180 Hz
        freq = lerp(520.0, 180.0, progress**0.55)
        phase = 2.0 * math.pi * freq * t
        tone = math.sin(phase)

        # Hollow body: slightly detuned second partial
        tone += 0.35 * math.sin(phase * 1.012 + 0.4)
        tone += 0.12 * math.sin(phase * 2.03)

        # Soft noise burst at impact, fades fast
        noise_env = exp_decay(t, 38.0) * smoothstep(0.0, 0.008, t)
        noise = (rng.random() * 2.0 - 1.0) * noise_env

        # Cartoon "bonk" envelope: instant hit, quick decay
        env = exp_decay(t, 22.0) * (1.0 - 0.25 * progress)
        env *= smoothstep(0.0, 0.003, t)

        sample = (tone * 0.62 + noise * 0.38) * env * 0.85
        samples.append(sample)

    return samples


def make_land_hup() -> list[float]:
    duration = 0.22
    n = int(SAMPLE_RATE * duration)
    rng = random.Random(77)
    samples: list[float] = []

    for i in range(n):
        t = i / SAMPLE_RATE

        # Muffled low thump (~90 Hz with fast pitch drop)
        thump_freq = lerp(95.0, 55.0, smoothstep(0.0, 0.06, t))
        thump_phase = 2.0 * math.pi * thump_freq * t
        thump = math.sin(thump_phase)
        thump += 0.25 * math.sin(thump_phase * 0.5)
        thump_env = exp_decay(t, 16.0) * smoothstep(0.0, 0.004, t)

        # Tiny "hap" click: short higher blip around 6–18 ms
        hap_t = t - 0.006
        hap = 0.0
        if 0.0 <= hap_t <= 0.035:
            hap_freq = lerp(680.0, 420.0, hap_t / 0.035)
            hap = math.sin(2.0 * math.pi * hap_freq * hap_t)
            hap *= exp_decay(hap_t, 55.0) * smoothstep(0.0, 0.002, hap_t)

        # Subtle soft noise for fabric/body feel
        noise = (rng.random() * 2.0 - 1.0) * exp_decay(t, 30.0) * 0.08

        sample = thump * thump_env * 0.55 + hap * 0.42 + noise
        sample *= exp_decay(t, 8.0)  # gentle overall tail
        samples.append(clamp(sample * 0.9))

    return samples


def normalize_peak(samples: list[float], target_peak: float = 0.85) -> list[float]:
    peak = max(abs(s) for s in samples) or 1.0
    scale = target_peak / peak
    return [clamp(s * scale) for s in samples]


def make_ambient_curious() -> list[float]:
    duration = 8.0
    n = int(SAMPLE_RATE * duration)

    # Integer cycles over the loop length → phase-continuous wrap (no clicks)
    pad_voices = [
        {"cycles": 440, "phase": 0.0, "amp": 0.30},   # 55 Hz — dark root
        {"cycles": 495, "phase": 1.2, "amp": 0.24},   # ~62 Hz
        {"cycles": 528, "phase": 2.4, "amp": 0.20},   # 66 Hz
        {"cycles": 560, "phase": 0.6, "amp": 0.18},   # 70 Hz
        {"cycles": 600, "phase": 3.0, "amp": 0.16},   # 75 Hz
        {"cycles": 660, "phase": 1.7, "amp": 0.14},   # 82.5 Hz
        {"cycles": 720, "phase": 2.9, "amp": 0.11},   # 90 Hz
        {"cycles": 880, "phase": 0.4, "amp": 0.09},   # 110 Hz — warmth
        {"cycles": 1040, "phase": 1.5, "amp": 0.06},  # 130 Hz
    ]

    # Subtle magical shimmer — pure sines only, very quiet
    shimmer_voices = [
        {"cycles": 1760, "phase": 0.3, "amp": 0.022},
        {"cycles": 1980, "phase": 1.8, "amp": 0.016},
        {"cycles": 2200, "phase": 2.5, "amp": 0.011},
    ]

    samples: list[float] = []

    for i in range(n):
        loop_phase = i / n

        mix = 0.0
        for v in pad_voices:
            angle = 2.0 * math.pi * v["cycles"] * loop_phase + v["phase"]
            mix += v["amp"] * math.sin(angle)

        # Slow dark swell (integer-cycle LFOs)
        swell = 0.84 + 0.16 * math.sin(2.0 * math.pi * loop_phase + 0.4)
        swell *= 0.91 + 0.09 * math.sin(4.0 * math.pi * loop_phase + 1.1)

        shimmer = 0.0
        for v in shimmer_voices:
            angle = 2.0 * math.pi * v["cycles"] * loop_phase + v["phase"]
            shimmer += v["amp"] * math.sin(angle)
        shimmer *= 0.86 + 0.14 * math.sin(6.0 * math.pi * loop_phase + 0.6)

        sample = mix * swell + shimmer
        samples.append(clamp(sample))

    # Gentle crossfade at loop boundary for extra safety
    crossfade = min(int(0.04 * n), n // 8)
    if crossfade > 1:
        for i in range(crossfade):
            t = smoothstep(0.0, 1.0, i / (crossfade - 1))
            tail_idx = n - crossfade + i
            blended = lerp(samples[tail_idx], samples[i], t)
            samples[i] = blended
            samples[tail_idx] = blended

    result = normalize_peak(samples, target_peak=0.18)
    result[-1] = result[0]  # click-free wrap
    return result


def make_footstep() -> list[float]:
    duration = 0.09
    n = int(SAMPLE_RATE * duration)
    rng = random.Random(13)
    samples: list[float] = []

    for i in range(n):
        t = i / SAMPLE_RATE
        progress = t / duration

        # Soft curious tap: light mid thump with quick pitch drop
        thump_freq = lerp(240.0, 160.0, progress**0.7)
        thump_phase = 2.0 * math.pi * thump_freq * t
        thump = math.sin(thump_phase)
        thump += 0.18 * math.sin(thump_phase * 2.01)
        thump_env = exp_decay(t, 42.0) * smoothstep(0.0, 0.003, t)

        # Tiny curious sparkle blip (magical hint)
        sparkle_t = t - 0.008
        sparkle = 0.0
        if 0.0 <= sparkle_t <= 0.028:
            sparkle_freq = lerp(920.0, 640.0, sparkle_t / 0.028)
            sparkle = math.sin(2.0 * math.pi * sparkle_freq * sparkle_t)
            sparkle *= exp_decay(sparkle_t, 70.0) * smoothstep(0.0, 0.001, sparkle_t)

        # Soft fabric/noise tap
        noise = (rng.random() * 2.0 - 1.0) * exp_decay(t, 55.0) * 0.06
        noise *= smoothstep(0.0, 0.004, t)

        sample = thump * thump_env * 0.48 + sparkle * 0.22 + noise
        sample *= exp_decay(t, 12.0)
        samples.append(clamp(sample * 0.82))

    return samples


def make_charge_start() -> list[float]:
    duration = 0.25
    n = int(SAMPLE_RATE * duration)
    rng = random.Random(31)
    samples: list[float] = []

    for i in range(n):
        t = i / SAMPLE_RATE
        progress = t / duration

        # Rising wind-up: low hum climbs into tense mid tone
        base_freq = lerp(85.0, 320.0, progress**1.35)
        tremolo = 1.0 + 0.06 * math.sin(2.0 * math.pi * lerp(4.0, 14.0, progress) * t)
        phase = 2.0 * math.pi * base_freq * tremolo * t
        core = math.sin(phase)
        core += 0.32 * math.sin(phase * 1.005 + 0.5)
        core += 0.14 * math.sin(phase * 2.0)

        # Magical shimmer layer that brightens as charge builds
        shimmer_freq = lerp(440.0, 880.0, progress**0.9)
        shimmer = math.sin(2.0 * math.pi * shimmer_freq * t + math.sin(2.0 * math.pi * 6.0 * t))
        shimmer *= lerp(0.05, 0.28, progress**1.1)

        # Subtle filtered-noise tension (wind gathering)
        noise = (rng.random() * 2.0 - 1.0) * lerp(0.02, 0.12, progress**1.4)
        noise *= smoothstep(0.02, 0.08, t)

        # Envelope: slow curious build, no hard attack
        env = smoothstep(0.0, 0.04, t) * lerp(0.35, 1.0, progress**0.85)

        sample = (core * 0.58 + shimmer + noise) * env
        samples.append(clamp(sample * 0.78))

    return samples


def make_jump_launch() -> list[float]:
    duration = 0.2
    n = int(SAMPLE_RATE * duration)
    rng = random.Random(99)
    samples: list[float] = []

    for i in range(n):
        t = i / SAMPLE_RATE
        progress = t / duration

        # Springy boing: pitch drops fast then bounces (Jump King-ish)
        boing_freq = lerp(520.0, 140.0, progress**0.45)
        bounce = 1.0 + 0.18 * math.sin(2.0 * math.pi * 9.0 * t) * exp_decay(t, 18.0)
        boing_phase = 2.0 * math.pi * boing_freq * bounce * t
        boing = math.sin(boing_phase)
        boing += 0.4 * math.sin(boing_phase * 0.5 + 0.3)
        boing_env = exp_decay(t, 10.0) * smoothstep(0.0, 0.002, t)

        # Upward whoosh: bright sweep + noise burst
        whoosh_freq = lerp(180.0, 720.0, smoothstep(0.0, 0.12, t))
        whoosh = math.sin(2.0 * math.pi * whoosh_freq * t)
        whoosh += 0.25 * math.sin(2.0 * math.pi * whoosh_freq * 1.5 * t)
        whoosh_env = exp_decay(t, 14.0) * (1.0 - smoothstep(0.08, 0.18, t))
        whoosh_noise = (rng.random() * 2.0 - 1.0) * exp_decay(t, 22.0) * 0.35
        whoosh *= whoosh_env
        whoosh_noise *= whoosh_env

        sample = boing * boing_env * 0.62 + whoosh * 0.38 + whoosh_noise
        samples.append(sample)

    peak = max(abs(s) for s in samples) or 1.0
    target_peak = 0.85
    scale = target_peak / peak
    return [clamp(s * scale) for s in samples]


def main() -> None:
    files = {
        "wall_bonk.wav": make_wall_bonk(),
        "land_hup.wav": make_land_hup(),
        "footstep.wav": make_footstep(),
        "charge_start.wav": make_charge_start(),
        "jump_launch.wav": make_jump_launch(),
        "ambient_curious.wav": make_ambient_curious(),
    }

    for name, samples in files.items():
        path = OUTPUT_DIR / name
        write_wav(path, samples)
        size = path.stat().st_size
        peak = max(abs(s) for s in samples)
        line = f"{path}  ({size:,} bytes)"
        if name == "ambient_curious.wav":
            line += f"  peak={peak:.4f}"
        print(line)

    attribution = OUTPUT_DIR / "ATTRIBUTION.txt"
    attribution.write_text(
        "Audio assets in this folder (wall_bonk.wav, land_hup.wav, footstep.wav,\n"
        "charge_start.wav, jump_launch.wav, ambient_curious.wav)\n"
        "are original procedural sound effects created for the politropia project.\n"
        "Generated programmatically; no third-party samples were used.\n",
        encoding="utf-8",
    )
    print(f"{attribution}  ({attribution.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()

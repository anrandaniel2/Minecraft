"""Tiny dependency-free pixel-art + sound toolkit used to generate game assets.

Why this exists: the game ships with procedurally generated 16x16 textures and
synthesised sound effects so the repository has no binary art dependencies and
every asset is reproducible from source (run `python3 tools/gen_assets.py`).

Everything here is pure Python: PNG files are written by hand (zlib + CRC) and
WAV files use the stdlib `wave` module. No Pillow, no numpy, no ImageMagick.
"""

from __future__ import annotations

import math
import random
import struct
import wave
import zlib
from typing import Iterable, Sequence

# --------------------------------------------------------------------------
# PNG writing
# --------------------------------------------------------------------------

_PNG_SIG = b"\x89PNG\r\n\x1a\n"


def _chunk(tag: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + tag
        + data
        + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    )


def write_png(path: str, width: int, height: int, rgba: bytes) -> None:
    """Write raw RGBA bytes (row-major, 4 bytes/pixel) to a PNG file."""
    assert len(rgba) == width * height * 4, "pixel buffer size mismatch"
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)  # filter type: none
        raw += rgba[y * stride : (y + 1) * stride]
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    with open(path, "wb") as handle:
        handle.write(_PNG_SIG)
        handle.write(_chunk(b"IHDR", ihdr))
        handle.write(_chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        handle.write(_chunk(b"IEND", b""))


# --------------------------------------------------------------------------
# Colour helpers
# --------------------------------------------------------------------------

RGBA = tuple[int, int, int, int]


def rgba(color, alpha: int | None = None) -> RGBA:
    """Normalise a colour given as hex int, '#rrggbb', or (r,g,b[,a])."""
    if isinstance(color, int):
        out = ((color >> 16) & 0xFF, (color >> 8) & 0xFF, color & 0xFF, 255)
    elif isinstance(color, str):
        text = color.lstrip("#")
        out = (int(text[0:2], 16), int(text[2:4], 16), int(text[4:6], 16), 255)
    else:
        vals = tuple(int(c) for c in color)
        out = vals if len(vals) == 4 else (vals[0], vals[1], vals[2], 255)
    if alpha is not None:
        out = (out[0], out[1], out[2], alpha)
    return out


def shade(color, factor: float, alpha: int | None = None) -> RGBA:
    """Multiply a colour's brightness, clamping to 0..255."""
    r, g, b, a = rgba(color)
    if alpha is not None:
        a = alpha
    return (
        max(0, min(255, int(r * factor))),
        max(0, min(255, int(g * factor))),
        max(0, min(255, int(b * factor))),
        a,
    )


def mix(a, b, t: float) -> RGBA:
    ca, cb = rgba(a), rgba(b)
    return (
        int(ca[0] + (cb[0] - ca[0]) * t),
        int(ca[1] + (cb[1] - ca[1]) * t),
        int(ca[2] + (cb[2] - ca[2]) * t),
        int(ca[3] + (cb[3] - ca[3]) * t),
    )


# --------------------------------------------------------------------------
# Canvas
# --------------------------------------------------------------------------


class Canvas:
    """A small RGBA pixel canvas with the drawing helpers pixel art needs."""

    def __init__(self, size: int = 16, background=None):
        self.size = size
        self.w = size
        self.h = size
        if background is None:
            self.px = bytearray(size * size * 4)
        else:
            self.px = bytearray(rgba(background) * (size * size))

    # -- basics ---------------------------------------------------------
    def clone(self) -> "Canvas":
        out = Canvas(self.size)
        out.px = bytearray(self.px)
        return out

    def set(self, x: int, y: int, color, alpha: int | None = None) -> None:
        if not (0 <= x < self.w and 0 <= y < self.h):
            return
        r, g, b, a = rgba(color, alpha)
        if a <= 0:
            return
        i = (y * self.w + x) * 4
        if a < 255:  # alpha blend over what's there
            dr, dg, db, da = self.px[i], self.px[i + 1], self.px[i + 2], self.px[i + 3]
            t = a / 255.0
            if da == 0:
                self.px[i : i + 4] = bytes((r, g, b, a))
                return
            r = int(dr + (r - dr) * t)
            g = int(dg + (g - dg) * t)
            b = int(db + (b - db) * t)
        self.px[i : i + 4] = bytes((r, g, b, 255))

    def get(self, x: int, y: int) -> RGBA:
        if not (0 <= x < self.w and 0 <= y < self.h):
            return (0, 0, 0, 0)
        i = (y * self.w + x) * 4
        return (self.px[i], self.px[i + 1], self.px[i + 2], self.px[i + 3])

    def fill(self, color) -> "Canvas":
        for y in range(self.h):
            for x in range(self.w):
                self.set(x, y, color)
        return self

    def rect(self, x: int, y: int, w: int, h: int, color) -> "Canvas":
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.set(xx, yy, color)
        return self

    def frame(self, x: int, y: int, w: int, h: int, color) -> "Canvas":
        for xx in range(x, x + w):
            self.set(xx, y, color)
            self.set(xx, y + h - 1, color)
        for yy in range(y, y + h):
            self.set(x, yy, color)
            self.set(x + w - 1, yy, color)
        return self

    def line(self, x0: int, y0: int, x1: int, y1: int, color) -> "Canvas":
        dx, dy = abs(x1 - x0), abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx - dy
        while True:
            self.set(x0, y0, color)
            if x0 == x1 and y0 == y1:
                break
            e2 = err * 2
            if e2 > -dy:
                err -= dy
                x0 += sx
            if e2 < dx:
                err += dx
                y0 += sy
        return self

    def disc(self, cx: float, cy: float, r: float, color, soft: float = 0.0) -> "Canvas":
        for y in range(self.h):
            for x in range(self.w):
                d = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
                if d <= r - soft:
                    self.set(x, y, color)
                elif soft > 0.0 and d <= r:
                    a = int(255 * (1.0 - (d - (r - soft)) / soft) * 0.85)
                    self.set(x, y, color, alpha=max(0, min(255, a)))
        return self

    def poly(self, points: Sequence[tuple[float, float]], color) -> "Canvas":
        """Scanline-fill a convex/concave polygon."""
        if len(points) < 3:
            return self
        ys = [p[1] for p in points]
        y_min = max(0, int(math.floor(min(ys))))
        y_max = min(self.h - 1, int(math.ceil(max(ys))))
        for y in range(y_min, y_max + 1):
            yc = y + 0.5
            crossings = []
            for i in range(len(points)):
                x0, y0 = points[i]
                x1, y1 = points[(i + 1) % len(points)]
                if (y0 <= yc < y1) or (y1 <= yc < y0):
                    t = (yc - y0) / (y1 - y0)
                    crossings.append(x0 + (x1 - x0) * t)
            crossings.sort()
            for i in range(0, len(crossings) - 1, 2):
                xa = int(math.ceil(crossings[i] - 0.5))
                xb = int(math.floor(crossings[i + 1] - 0.5))
                for x in range(xa, xb + 1):
                    self.set(x, y, color)
        return self

    # -- texture helpers ------------------------------------------------
    def noise(
        self,
        seed: int,
        amount: float = 0.12,
        colors: Iterable | None = None,
        alpha: int = 255,
        region: tuple[int, int, int, int] | None = None,
    ) -> "Canvas":
        """Speckle existing pixels with per-pixel brightness variation."""
        rng = random.Random(seed)
        palette = [rgba(c) for c in colors] if colors else None
        x0, y0, x1, y1 = region or (0, 0, self.w, self.h)
        for y in range(y0, y1):
            for x in range(x0, x1):
                if palette is not None:
                    if rng.random() < amount * 3:
                        self.set(x, y, rng.choice(palette), alpha=alpha)
                    continue
                cur = self.get(x, y)
                if cur[3] == 0:
                    continue
                f = 1.0 + rng.uniform(-amount, amount)
                self.set(x, y, shade(cur, f), alpha=alpha)
        return self

    def speckle(self, seed: int, color, count: int, size: int = 1) -> "Canvas":
        """Scatter blobs of a colour (ore veins, gravel chunks, ...)."""
        rng = random.Random(seed)
        for _ in range(count):
            x = rng.randrange(self.w)
            y = rng.randrange(self.h)
            for dy in range(size):
                for dx in range(size):
                    self.set(x + dx, y + dy, color)
        return self

    def blobs(self, seed: int, color, count: int, radius: int = 2) -> "Canvas":
        rng = random.Random(seed)
        for _ in range(count):
            cx = rng.uniform(1, self.w - 1)
            cy = rng.uniform(1, self.h - 1)
            r = rng.uniform(radius * 0.6, radius)
            for y in range(self.h):
                for x in range(self.w):
                    if math.hypot(x + 0.5 - cx, y + 0.5 - cy) <= r:
                        self.set(x, y, color)
        return self

    def outline(self, color, diagonal: bool = False) -> "Canvas":
        """Add a 1px outline around every opaque pixel."""
        src = self.clone()
        offsets = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        if diagonal:
            offsets += [(-1, -1), (1, -1), (-1, 1), (1, 1)]
        for y in range(self.h):
            for x in range(self.w):
                if src.get(x, y)[3] != 0:
                    continue
                for dx, dy in offsets:
                    if src.get(x + dx, y + dy)[3] > 128:
                        self.set(x, y, color)
                        break
        return self

    def bevel(self, light: float = 1.18, dark: float = 0.78) -> "Canvas":
        """Top/left highlight, bottom/right shadow - the classic block look."""
        src = self.clone()
        for y in range(self.h):
            for x in range(self.w):
                if src.get(x, y)[3] == 0:
                    continue
                if src.get(x, y - 1)[3] == 0 or src.get(x - 1, y)[3] == 0:
                    self.set(x, y, shade(src.get(x, y), light))
                elif src.get(x, y + 1)[3] == 0 or src.get(x + 1, y)[3] == 0:
                    self.set(x, y, shade(src.get(x, y), dark))
        return self

    def scale(self, factor: int) -> "Canvas":
        out = Canvas(self.size * factor)
        for y in range(self.h):
            for x in range(self.w):
                c = self.get(x, y)
                for dy in range(factor):
                    for dx in range(factor):
                        out.set(x * factor + dx, y * factor + dy, c)
        return out

    def border(self, color, width: int = 1) -> "Canvas":
        for i in range(width):
            self.frame(i, i, self.w - 2 * i, self.h - 2 * i, color)
        return self

    def save(self, path: str) -> None:
        write_png(path, self.w, self.h, bytes(self.px))


# --------------------------------------------------------------------------
# Sound synthesis
# --------------------------------------------------------------------------

SAMPLE_RATE = 22050


class Sound:
    """Mono float sample buffer with simple DSP helpers."""

    def __init__(self, seconds: float = 0.25, sample_rate: int = SAMPLE_RATE):
        self.rate = sample_rate
        self.samples = [0.0] * int(seconds * sample_rate)

    def __len__(self) -> int:
        return len(self.samples)

    def add(self, index: int, value: float) -> None:
        if 0 <= index < len(self.samples):
            self.samples[index] += value

    def mix_into(self, other: "Sound", offset: float = 0.0, gain: float = 1.0) -> None:
        start = int(offset * self.rate)
        for i, value in enumerate(other.samples):
            self.add(start + i, value * gain)

    def envelope(self, attack: float, decay: float, curve: float = 2.0) -> "Sound":
        a = max(1, int(attack * self.rate))
        d = max(1, int(decay * self.rate))
        for i in range(len(self.samples)):
            if i < a:
                env = i / a
            else:
                t = (i - a) / d
                env = math.exp(-t * curve) if t < 6 else 0.0
            self.samples[i] *= env
        return self

    def fade_out(self, seconds: float) -> "Sound":
        n = max(1, int(seconds * self.rate))
        for i in range(len(self.samples)):
            remaining = len(self.samples) - i
            if remaining < n:
                self.samples[i] *= remaining / n
        return self

    def normalize(self, peak: float = 0.85) -> "Sound":
        current = max((abs(s) for s in self.samples), default=0.0)
        if current <= 0.0:
            return self
        gain = peak / current
        self.samples = [s * gain for s in self.samples]
        return self

    def lowpass(self, cutoff_hz: float, passes: int = 1) -> "Sound":
        # One-pole IIR, applied `passes` times for a steeper rolloff.
        alpha = 1.0 - math.exp(-2.0 * math.pi * cutoff_hz / self.rate)
        for _ in range(passes):
            prev = 0.0
            for i, value in enumerate(self.samples):
                prev += (value - prev) * alpha
                self.samples[i] = prev
        return self

    def highpass(self, cutoff_hz: float) -> "Sound":
        alpha = 1.0 - math.exp(-2.0 * math.pi * cutoff_hz / self.rate)
        prev_in = 0.0
        prev_out = 0.0
        for i, value in enumerate(self.samples):
            prev_out = alpha * (prev_out + value - prev_in)
            prev_in = value
            self.samples[i] = prev_out
        return self

    def save(self, path: str, volume: float = 0.9) -> None:
        self.normalize(0.95)
        frames = bytearray()
        for value in self.samples:
            v = max(-1.0, min(1.0, value * volume))
            frames += struct.pack("<h", int(v * 32767))
        with wave.open(path, "wb") as handle:
            handle.setnchannels(1)
            handle.setsampwidth(2)
            handle.setframerate(self.rate)
            handle.writeframes(bytes(frames))


def tone(
    freq: float,
    seconds: float,
    waveform: str = "sine",
    freq_end: float | None = None,
    sample_rate: int = SAMPLE_RATE,
) -> Sound:
    """A single oscillator sweep."""
    sound = Sound(seconds, sample_rate)
    n = len(sound.samples)
    phase = 0.0
    end = freq if freq_end is None else freq_end
    for i in range(n):
        t = i / max(1, n - 1)
        f = freq + (end - freq) * t
        phase += 2.0 * math.pi * f / sample_rate
        if waveform == "sine":
            value = math.sin(phase)
        elif waveform == "square":
            value = 1.0 if math.sin(phase) >= 0 else -1.0
        elif waveform == "saw":
            value = 2.0 * ((phase / (2.0 * math.pi)) % 1.0) - 1.0
        elif waveform == "triangle":
            value = 2.0 * abs(2.0 * ((phase / (2.0 * math.pi)) % 1.0) - 1.0) - 1.0
        else:
            value = math.sin(phase)
        sound.samples[i] = value
    return sound


def noise_burst(
    seconds: float, seed: int = 0, sample_rate: int = SAMPLE_RATE
) -> Sound:
    rng = random.Random(seed)
    sound = Sound(seconds, sample_rate)
    for i in range(len(sound.samples)):
        sound.samples[i] = rng.uniform(-1.0, 1.0)
    return sound


def chord(freqs: Sequence[float], seconds: float, waveform: str = "sine") -> Sound:
    out = Sound(seconds)
    for f in freqs:
        out.mix_into(tone(f, seconds, waveform), 0.0, 1.0 / len(freqs))
    return out


def sequence(steps: Sequence[tuple[float, float]], waveform: str = "square") -> Sound:
    """steps: [(freq, duration), ...] played back to back."""
    total = sum(d for _, d in steps) + 0.03
    out = Sound(total)
    offset = 0.0
    for freq, dur in steps:
        note = tone(freq, dur, waveform)
        note.envelope(0.004, dur, curve=4.0)
        out.mix_into(note, offset, 1.0)
        offset += dur
    return out

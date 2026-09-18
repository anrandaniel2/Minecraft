"""Procedurally generates every texture in the game (blocks, items, UI, mobs).

Run via `python3 tools/gen_assets.py textures`. Output goes to
`assets/generated/{blocks,items,ui,entities}` plus a stitched
`assets/generated/atlas.png` + `atlas.json` used by the terrain renderer.

The atlas exists so a whole chunk can be drawn in a handful of draw calls:
each 16x16 tile is padded with 4px of replicated edge pixels (prevents mipmap
bleeding) and the block shader samples `UV2 + fract(UV) * tile` into it.
"""

from __future__ import annotations

import json
import math
import os
import random
import zlib

from pixelart import Canvas, mix, rgba, shade

TILE = 16
PAD = 4

# ---------------------------------------------------------------------------
# Palettes
# ---------------------------------------------------------------------------

STONE = "#7d7d7d"
DIRT = "#79553a"
GRASS = "#5d9c3a"

WOOL_COLORS = {
    "white": "#e9ecec",
    "orange": "#f07613",
    "magenta": "#bd44b3",
    "light_blue": "#3aafd9",
    "yellow": "#f8c627",
    "lime": "#70b919",
    "pink": "#ed8dac",
    "gray": "#3e4447",
    "light_gray": "#8e8e86",
    "cyan": "#158991",
    "purple": "#792aac",
    "blue": "#35399d",
    "brown": "#724728",
    "green": "#546d1b",
    "red": "#a12722",
    "black": "#141519",
}

WOOD_TYPES = {
    # name: (bark, bark_dark, ring_light, ring_dark, leaf, leaf_alt)
    "oak": ("#6b5132", "#4c3a22", "#a0813f", "#6b5132", "#4a7a29", "#3d6820"),
    "birch": ("#d7d3c8", "#9c988b", "#c3bb9a", "#8f8a6f", "#6ba142", "#5b8c36"),
    "spruce": ("#4a3722", "#332615", "#7d5b34", "#4a3722", "#2f5f33", "#26502b"),
    "jungle": ("#5a4a2a", "#3f3319", "#9c7c46", "#5a4a2a", "#3f8a2d", "#337125"),
}

ORE_COLORS = {
    "coal": "#22221f",
    "iron": "#d8af93",
    "copper": "#e07f4a",
    "gold": "#fcee4b",
    "diamond": "#4aedd9",
    "emerald": "#17dd62",
    "redstone": "#d82b1f",
    "lapis": "#2f4bb0",
}


# ---------------------------------------------------------------------------
# Noise helpers
# ---------------------------------------------------------------------------



def _stable_seed(text) -> int:
    """Deterministic stand-in for _stable_seed() - Python salts _stable_seed() per process."""
    return zlib.crc32(str(text).encode("utf-8"))

def value_noise(seed: int, size: int = 16, scale: float = 4.0) -> list[list[float]]:
    """Cheap tiling value noise in 0..1, used for rock/soil textures."""
    rng = random.Random(seed)
    grid = max(2, int(round(size / scale)) + 1)
    points = [[rng.random() for _ in range(grid)] for _ in range(grid)]

    def sample(x: float, y: float) -> float:
        x0, y0 = int(x), int(y)
        fx, fy = x - x0, y - y0
        fx = fx * fx * (3 - 2 * fx)
        fy = fy * fy * (3 - 2 * fy)
        x1 = (x0 + 1) % grid
        y1 = (y0 + 1) % grid
        x0 %= grid
        y0 %= grid
        top = points[y0][x0] + (points[y0][x1] - points[y0][x0]) * fx
        bot = points[y1][x0] + (points[y1][x1] - points[y1][x0]) * fx
        return top + (bot - top) * fy

    out = []
    for y in range(size):
        row = []
        for x in range(size):
            v = 0.0
            amp = 1.0
            total = 0.0
            freq = 1.0 / scale
            for _ in range(3):
                row_v = sample(x * freq, y * freq)
                v += row_v * amp
                total += amp
                amp *= 0.5
                freq *= 2.0
            row.append(v / total)
        out.append(row)
    return out


def noise_canvas(
    seed: int,
    color: str,
    contrast: float = 0.22,
    scale: float = 4.0,
    alpha: int = 255,
) -> Canvas:
    """Base texture: value noise mapped to brightness variation."""
    canvas = Canvas(TILE)
    grid = value_noise(seed, TILE, scale)
    base = rgba(color)
    for y in range(TILE):
        for x in range(TILE):
            f = 1.0 + (grid[y][x] - 0.5) * 2.0 * contrast
            canvas.set(x, y, shade(base, f), alpha=alpha)
    return canvas


# ---------------------------------------------------------------------------
# Block materials
# ---------------------------------------------------------------------------


def tex_grass_top(seed: int = 1) -> Canvas:
    canvas = noise_canvas(seed, GRASS, contrast=0.28, scale=3.0)
    rng = random.Random(seed + 7)
    for _ in range(26):  # little blades
        x, y = rng.randrange(TILE), rng.randrange(TILE)
        canvas.set(x, y, shade(GRASS, rng.uniform(0.78, 1.25)))
        canvas.set((x + 1) % TILE, y, shade(GRASS, rng.uniform(0.8, 1.2)))
    return canvas


def tex_grass_side(seed: int = 2, grass_color: str = GRASS, soil: str = DIRT) -> Canvas:
    canvas = noise_canvas(seed, soil, contrast=0.24, scale=3.5)
    rng = random.Random(seed + 11)
    for x in range(TILE):
        depth = rng.choice([3, 3, 3, 4, 4, 5, 2])
        for y in range(depth):
            f = 1.0 - y * 0.05 + rng.uniform(-0.1, 0.1)
            color = shade(grass_color, f)
            canvas.set(x, y, color)
    return canvas


def tex_dirt(seed: int = 3, color: str = DIRT) -> Canvas:
    canvas = noise_canvas(seed, color, contrast=0.3, scale=2.5)
    rng = random.Random(seed + 3)
    for _ in range(18):
        x, y = rng.randrange(TILE), rng.randrange(TILE)
        canvas.set(x, y, shade(color, 0.72))
    return canvas


def tex_stone(seed: int = 4, color: str = STONE) -> Canvas:
    canvas = noise_canvas(seed, color, contrast=0.2, scale=2.0)
    rng = random.Random(seed + 5)
    for _ in range(12):
        x, y = rng.randrange(TILE), rng.randrange(TILE)
        w = rng.choice([1, 2, 3])
        for dx in range(w):
            canvas.set(x + dx, y, shade(color, rng.uniform(0.8, 0.9)))
    return canvas


def tex_cobblestone(seed: int = 6, marble: bool = False) -> Canvas:
    canvas = Canvas(TILE).fill(shade(STONE, 0.62))
    rng = random.Random(seed)
    # Irregular rounded stones separated by dark mortar.
    stones = [
        (0, 0, 7, 6), (8, 0, 7, 4), (0, 6, 4, 5), (5, 5, 5, 6),
        (11, 4, 4, 6), (0, 12, 6, 3), (7, 11, 4, 4), (12, 10, 3, 5),
    ]
    for (sx, sy, sw, sh) in stones:
        base = shade(STONE, rng.uniform(0.95, 1.25)) if not marble else shade("#e8e8e0", rng.uniform(0.9, 1.05))
        for y in range(sy + 1, sy + sh - 1):
            for x in range(sx + 1, sx + sw - 1):
                edge = x in (sx + 1, sx + sw - 2) or y in (sy + 1, sy + sh - 2)
                color = shade(base, 0.88 if edge else 1.0)
                canvas.set(x, y, shade(color, rng.uniform(0.92, 1.08)))
    canvas.speckle(seed + 1, shade(STONE, 0.7), 20)
    return canvas


def tex_mossy(seed: int = 8) -> Canvas:
    canvas = tex_cobblestone(seed)
    rng = random.Random(seed + 17)
    for _ in range(40):
        x, y = rng.randrange(TILE), rng.randrange(TILE)
        for dy in range(rng.randint(1, 2)):
            for dx in range(rng.randint(1, 3)):
                canvas.set(x + dx, y + dy, shade("#4a7a29", rng.uniform(0.8, 1.2)))
    return canvas


def tex_gravel(seed: int = 9) -> Canvas:
    canvas = Canvas(TILE)
    rng = random.Random(seed)
    for y in range(TILE):
        for x in range(TILE):
            tone = rng.choice(["#8f8a86", "#6f6a66", "#a8a29a", "#5b5854", "#c0bab0"])
            canvas.set(x, y, tone)
    for _ in range(26):
        canvas.blobs(rng.randint(0, 999), shade("#7d7873", rng.uniform(0.7, 1.2)), 1, 1.6)
    return canvas.noise(seed + 2, 0.08)


def tex_sand(seed: int = 10, color: str = "#dbcf9a") -> Canvas:
    canvas = noise_canvas(seed, color, contrast=0.12, scale=2.0)
    rng = random.Random(seed + 4)
    for _ in range(14):
        x, y = rng.randrange(TILE), rng.randrange(TILE)
        canvas.set(x, y, shade(color, 0.9))
    return canvas


def tex_sandstone_side(seed: int = 11) -> Canvas:
    canvas = noise_canvas(seed, "#d9cd98", contrast=0.1, scale=3.0)
    for y in (3, 9, 13):
        for x in range(TILE):
            canvas.set(x, y, shade("#c9ba85", 0.94))
    return canvas


def tex_sandstone_top(seed: int = 12) -> Canvas:
    return noise_canvas(seed, "#ded2a0", contrast=0.1, scale=3.0)


def tex_log_side(wood: str = "oak") -> Canvas:
    bark, dark, _, _, _, _ = WOOD_TYPES[wood]
    canvas = noise_canvas(_stable_seed(wood) % 999, bark, contrast=0.18, scale=2.0)
    rng = random.Random(len(wood) * 31)
    for _ in range(9):  # vertical bark streaks
        x = rng.randrange(TILE)
        y0 = rng.randrange(TILE)
        length = rng.randint(4, 12)
        for i in range(length):
            canvas.set(x, (y0 + i) % TILE, shade(bark, rng.uniform(0.62, 0.8)))
    return canvas


def tex_log_top(wood: str = "oak") -> Canvas:
    bark, _, light, dark, _, _ = WOOD_TYPES[wood]
    canvas = Canvas(TILE).fill(bark)
    cx = cy = 7.5
    for y in range(TILE):
        for x in range(TILE):
            d = math.hypot(x - cx, y - cy)
            if d > 7.4:
                canvas.set(x, y, shade(bark, 0.85))
            else:
                ring = int(d) % 2 == 0
                canvas.set(x, y, light if ring else dark)
    for y in range(TILE):  # bark border
        for x in range(TILE):
            if x < 1 or y < 1 or x > TILE - 2 or y > TILE - 2:
                canvas.set(x, y, shade(bark, 0.9))
    return canvas.noise(_stable_seed(wood) % 777, 0.1)


def tex_planks(wood: str = "oak", color: str | None = None) -> Canvas:
    _, _, light, dark, _, _ = WOOD_TYPES[wood]
    base = color or mix(light, "#c9a56a", 0.5)
    canvas = Canvas(TILE)
    plank_h = 4
    rng = random.Random(_stable_seed(wood) % 555)
    for y in range(TILE):
        row = y // plank_h
        tone = 1.0 + (row % 2) * 0.06
        for x in range(TILE):
            canvas.set(x, y, shade(base, tone * rng.uniform(0.95, 1.05)))
    for y in range(plank_h, TILE, plank_h):  # plank seams
        for x in range(TILE):
            canvas.set(x, y, shade(base, 0.62))
    rng = random.Random(_stable_seed(wood) % 111)
    for _ in range(6):  # vertical grain nicks
        x = rng.randrange(TILE)
        y = rng.randrange(TILE) // plank_h * plank_h
        canvas.set(x, y + 1, shade(base, 0.75))
        canvas.set(x, y + 2, shade(base, 0.82))
    return canvas


def tex_leaves(wood: str = "oak", density: float = 0.16) -> Canvas:
    _, _, _, _, leaf, alt = WOOD_TYPES[wood]
    canvas = Canvas(TILE)
    rng = random.Random(_stable_seed(wood) % 321)
    for y in range(TILE):
        for x in range(TILE):
            r = rng.random()
            if r < density:
                continue  # hole → transparency
            color = leaf if r < 0.6 else alt
            canvas.set(x, y, shade(color, rng.uniform(0.75, 1.25)))
    return canvas


def tex_ore(kind: str, seed: int = 20) -> Canvas:
    canvas = tex_stone(seed + _stable_seed(kind) % 50)
    color = ORE_COLORS[kind]
    rng = random.Random(seed)
    blobs = {
        "coal": [(2, 3), (9, 2), (5, 9), (11, 10), (3, 12)],
        "iron": [(3, 2), (10, 4), (6, 10), (12, 11)],
        "copper": [(2, 4), (8, 3), (5, 8), (11, 9), (4, 12)],
        "gold": [(3, 3), (9, 5), (6, 11)],
        "diamond": [(3, 4), (10, 3), (6, 10), (11, 11)],
        "emerald": [(2, 6), (9, 4), (5, 11)],
        "redstone": [(2, 3), (7, 3), (4, 8), (10, 8), (6, 12)],
        "lapis": [(3, 2), (9, 4), (4, 9), (11, 10)],
    }[kind]
    pattern = {
        "coal": [(0, 0), (1, 0), (0, 1), (1, 1), (2, 1), (1, 2)],
        "iron": [(0, 0), (1, 0), (2, 0), (0, 1), (1, 1), (2, 1)],
        "copper": [(0, 0), (1, 0), (0, 1), (1, 1), (2, 2)],
        "gold": [(0, 0), (1, 0), (2, 0), (0, 1), (1, 1), (0, 2)],
        "diamond": [(0, 0), (1, 0), (2, 0), (1, 1), (0, 2), (2, 2), (1, 3)],
        "emerald": [(0, 0), (1, 0), (2, 0), (1, 1), (0, 2), (2, 2)],
        "redstone": [(0, 0), (1, 0), (0, 1), (1, 1)],
        "lapis": [(0, 0), (1, 0), (0, 1), (1, 1), (2, 1)],
    }[kind]
    for (bx, by) in blobs:
        for (dx, dy) in pattern:
            light = 1.0 + rng.uniform(-0.1, 0.18)
            canvas.set(bx + dx, by + dy, shade(color, light))
    return canvas


def tex_bedrock(seed: int = 30) -> Canvas:
    canvas = Canvas(TILE)
    rng = random.Random(seed)
    for y in range(TILE):
        for x in range(TILE):
            canvas.set(x, y, shade("#3b3b3f", rng.uniform(0.55, 1.5)))
    canvas.speckle(seed + 1, "#1b1b1e", 40)
    return canvas


def tex_obsidian(seed: int = 31) -> Canvas:
    canvas = noise_canvas(seed, "#180d28", contrast=0.35, scale=3.0)
    rng = random.Random(seed + 2)
    for _ in range(24):
        x, y = rng.randrange(TILE), rng.randrange(TILE)
        canvas.set(x, y, shade("#4b2d78", rng.uniform(0.8, 1.3)))
    return canvas


def tex_stone_bricks(seed: int = 32) -> Canvas:
    canvas = tex_stone(seed)
    brick_w, brick_h = 8, 4
    for row, y in enumerate(range(0, TILE, brick_h)):
        offset = 0 if row % 2 == 0 else brick_w // 2
        for x in range(TILE):
            canvas.set(x, y, shade(STONE, 0.66))
        for x in range(offset, TILE, brick_w):
            for yy in range(y, min(y + brick_h, TILE)):
                canvas.set(x, yy, shade(STONE, 0.66))
    return canvas


def tex_bricks(seed: int = 33) -> Canvas:
    canvas = Canvas(TILE).fill("#9a5a44")
    rng = random.Random(seed)
    for y in range(TILE):
        for x in range(TILE):
            canvas.set(x, y, shade("#a4644a", rng.uniform(0.92, 1.08)))
    for row, y in enumerate(range(0, TILE, 4)):
        offset = 0 if row % 2 == 0 else 4
        for x in range(TILE):
            canvas.set(x, y, "#8b8578")  # mortar
        for x in range(offset, TILE, 8):
            for yy in range(y, min(y + 4, TILE)):
                canvas.set(x, yy, "#8b8578")
    return canvas


def tex_snow(seed: int = 34) -> Canvas:
    return noise_canvas(seed, "#f2fafa", contrast=0.06, scale=2.0)


def tex_ice(seed: int = 35) -> Canvas:
    canvas = noise_canvas(seed, "#8fbdf5", contrast=0.12, scale=3.0)
    rng = random.Random(seed)
    for _ in range(6):
        x, y = rng.randrange(TILE), rng.randrange(TILE)
        canvas.line(x, y, min(TILE - 1, x + rng.randint(2, 6)), y + rng.choice([-1, 0, 1]), "#cbe6ff")
    return canvas


def tex_water(seed: int = 36) -> Canvas:
    canvas = noise_canvas(seed, "#2f5fd0", contrast=0.1, scale=4.0)
    for y in range(0, TILE, 4):
        for x in range(TILE):
            canvas.set(x, (y + (x // 4) % 2) % TILE, "#3f74e6")
    return canvas


def tex_lava(seed: int = 37) -> Canvas:
    canvas = noise_canvas(seed, "#d8480f", contrast=0.25, scale=3.0)
    rng = random.Random(seed)
    for _ in range(30):
        canvas.blobs(rng.randint(0, 9999), "#ffd23f", 1, 1.6)
    for _ in range(14):
        canvas.blobs(rng.randint(0, 9999), "#ffe98a", 1, 1.0)
    return canvas


def tex_glass(seed: int = 38) -> Canvas:
    canvas = Canvas(TILE)
    for i in range(TILE):
        canvas.set(i, 0, rgba("#d8f2ff", 190))
        canvas.set(i, TILE - 1, rgba("#d8f2ff", 190))
        canvas.set(0, i, rgba("#d8f2ff", 190))
        canvas.set(TILE - 1, i, rgba("#d8f2ff", 190))
    for i in range(3, 9):  # highlight streak
        canvas.set(i, 12 - i, rgba("#ffffff", 120))
        canvas.set(i + 1, 12 - i, rgba("#ffffff", 80))
    canvas.set(11, 3, rgba("#ffffff", 90))
    canvas.set(12, 4, rgba("#ffffff", 60))
    return canvas


def tex_glowstone(seed: int = 39) -> Canvas:
    canvas = noise_canvas(seed, "#f0c14b", contrast=0.2, scale=3.0)
    rng = random.Random(seed + 1)
    for _ in range(28):
        x, y = rng.randrange(TILE), rng.randrange(TILE)
        canvas.set(x, y, shade("#fff6c0", rng.uniform(0.9, 1.15)))
        canvas.set((x + 1) % TILE, y, shade("#ffe07a", rng.uniform(0.9, 1.1)))
    return canvas


def tex_workstation(kind: str, seed: int = 40) -> Canvas:
    if kind == "crafting_top":
        canvas = tex_planks("oak", "#a5793f")
        canvas.rect(1, 1, 14, 14, "#7c5426")
        for x in range(2, 15, 4):
            canvas.line(x, 2, x, 13, "#5f3f1c")
        for y in range(2, 15, 4):
            canvas.line(2, y, 13, y, "#5f3f1c")
        canvas.rect(2, 2, 3, 3, "#b4834a")
        canvas.rect(10, 10, 3, 3, "#b4834a")
        return canvas
    if kind == "crafting_side":
        canvas = tex_planks("oak", "#a5793f")
        canvas.line(0, 4, 15, 4, "#5f3f1c")
        canvas.line(0, 11, 15, 11, "#5f3f1c")
        return canvas
    if kind.startswith("furnace"):
        canvas = tex_stone(seed, "#6f6f6f")
        canvas.rect(0, 0, TILE, 3, "#5d5d5d")
        if kind.endswith("front") or kind.endswith("lit"):
            canvas.rect(3, 5, 10, 8, "#3a3a3a")
            canvas.rect(4, 6, 8, 6, "#242424")
            if kind.endswith("lit"):
                canvas.rect(4, 8, 8, 4, "#ff9410")
                for x in range(4, 12):
                    canvas.set(x, 7, shade("#ffd166", random.Random(x).uniform(0.7, 1.1)))
        elif kind.endswith("top"):
            canvas.rect(3, 3, 10, 10, "#595959")
            canvas.rect(4, 4, 8, 8, "#7b7b7b")
        return canvas
    if kind.startswith("chest"):
        if kind.endswith("top"):
            return tex_planks("oak", "#8a5f2c").rect(0, 0, TILE, 2, "#5f3f1c")
        canvas = tex_planks("oak", "#8a5f2c")
        for y in range(TILE):
            canvas.set(0, y, "#4d3315")
            canvas.set(TILE - 1, y, "#4d3315")
        canvas.rect(0, 6, TILE, 3, "#4d3315")  # lid seam
        canvas.rect(7, 6, 2, 3, "#c8a24a")  # latch
        canvas.rect(6, 9, 4, 3, "#8f8f8f")
        return canvas
    if kind == "bookshelf":
        canvas = tex_planks("oak", "#a5793f")
        canvas.rect(0, 0, TILE, 5, "#7c5426")
        canvas.rect(0, 11, TILE, 5, "#7c5426")
        rng = random.Random(seed)
        x = 1
        while x < TILE - 1:
            w = rng.randint(1, 2)
            color = rng.choice(["#9b3b2f", "#2f5d9b", "#3f7a35", "#c9a227", "#8b3f8b"])
            canvas.rect(x, 5, w, 6, color)
            canvas.rect(x, 9, w, 1, shade(color, 1.25))
            x += w + 1
        return canvas
    if kind.startswith("tnt"):
        if kind.endswith("top"):
            canvas = Canvas(TILE).fill("#b0341f")
            canvas.rect(3, 3, 10, 10, "#d9d9d9")
            canvas.rect(5, 5, 6, 6, "#8f1f10")
            return canvas
        canvas = Canvas(TILE).fill("#b0341f")
        canvas.rect(0, 5, TILE, 6, "#e8e8e8")
        for i, ch in enumerate("TNT"):
            draw_glyph(canvas, ch, 3 + i * 4, 6, "#2c2c2c")
        canvas.rect(0, 0, TILE, 2, "#8f1f10")
        return canvas
    if kind.startswith("pumpkin") or kind.startswith("jack"):
        canvas = noise_canvas(seed, "#d8791c", contrast=0.14, scale=4.0)
        for x in range(0, TILE, 5):
            for y in range(TILE):
                canvas.set(x, y, shade("#c26a15", 0.95))
        if kind == "jack_front":
            canvas.rect(3, 4, 3, 3, "#241a09")
            canvas.rect(10, 4, 3, 3, "#241a09")
            canvas.rect(5, 9, 6, 3, "#241a09")
            canvas.set(5, 10, "#ffdd55")
            canvas.set(10, 10, "#ffdd55")
        return canvas
    if kind == "melon_side":
        canvas = noise_canvas(seed, "#4f8f2a", contrast=0.16, scale=3.0)
        for y in range(TILE):
            for x in range(0, TILE, 3):
                canvas.set((x + (y // 3) % 3) % TILE, y, "#3d7220")
        return canvas
    if kind == "cactus_side":
        canvas = noise_canvas(seed, "#3f7a35", contrast=0.12, scale=4.0)
        canvas.rect(0, 0, 1, TILE, "#2f5d28")
        canvas.rect(TILE - 1, 0, 1, TILE, "#2f5d28")
        for y in range(2, TILE, 5):
            canvas.set(3, y, "#e8e8c0")
            canvas.set(12, y + 2, "#e8e8c0")
        return canvas
    if kind == "cactus_top":
        canvas = noise_canvas(seed, "#46853b", contrast=0.1, scale=4.0)
        canvas.rect(4, 4, 8, 8, "#3a7132")
        return canvas
    if kind == "melon_top":
        canvas = noise_canvas(seed, "#4f8f2a", contrast=0.12, scale=3.0)
        canvas.rect(3, 3, 10, 10, "#5ba032")
        for x in range(4, 13, 3):
            for y in range(4, 13, 3):
                canvas.set(x, y, "#7fbf4a")
        return canvas
    if kind == "pumpkin_top":
        canvas = noise_canvas(seed, "#d8791c", contrast=0.12, scale=4.0)
        canvas.rect(6, 6, 4, 4, "#8f6a2a")
        canvas.rect(7, 5, 2, 6, "#6b5132")
        return canvas
    if kind == "mossy_stone_bricks":
        canvas = tex_stone_bricks(seed)
        rng = random.Random(seed + 9)
        for _ in range(46):
            x, y = rng.randrange(TILE), rng.randrange(TILE)
            for dy in range(rng.randint(1, 2)):
                for dx in range(rng.randint(1, 2)):
                    canvas.set(x + dx, y + dy, shade("#4a7a29", rng.uniform(0.75, 1.2)))
        return canvas
    if kind == "farmland":
        canvas = tex_dirt(seed, "#6b4a2f")
        for y in (3, 8, 13):
            for x in range(TILE):
                canvas.set(x, y, shade("#5a3d26", 1.0))
                canvas.set(x, y + 1, shade("#845c3a", 1.0))
        return canvas
    if kind == "clay":
        return noise_canvas(seed, "#a3a8b8", contrast=0.12, scale=3.0)
    if kind == "redstone_block":
        canvas = noise_canvas(seed, "#a41b12", contrast=0.2, scale=3.0)
        for x in range(2, TILE, 5):
            canvas.line(x, 0, x, TILE - 1, "#d13a24")
        for y in range(2, TILE, 5):
            canvas.line(0, y, TILE - 1, y, "#d13a24")
        return canvas
    if kind == "note_block":
        canvas = tex_planks("oak", "#8a5f2c")
        rng = random.Random(seed)
        for _ in range(10):
            x, y = rng.randrange(TILE), rng.randrange(TILE)
            canvas.set(x, y, "#5f3f1c")
        canvas.rect(4, 4, 8, 8, "#3b2a14")
        canvas.rect(5, 5, 6, 6, "#c8a24a")
        return canvas
    if kind == "jukebox":
        canvas = tex_planks("oak", "#8a5f2c")
        canvas.rect(2, 2, 12, 12, "#3b2a14")
        canvas.rect(3, 3, 10, 10, "#6a4a20")
        canvas.disc(8, 8, 3.0, "#1c1c1c")
        canvas.disc(8, 8, 1.2, "#d8b45a")
        return canvas
    if kind == "piston_side":
        canvas = tex_planks("oak", "#b9a184")
        canvas.rect(0, 0, TILE, 4, "#7c6a58")
        canvas.rect(0, 12, TILE, 4, "#7c6a58")
        canvas.rect(0, 4, TILE, 2, "#5d5044")
        return canvas
    if kind == "piston_top":
        canvas = tex_stone(seed, "#9d9d9d")
        canvas.rect(2, 2, 12, 12, "#c2c2c2")
        canvas.rect(4, 4, 8, 8, "#8a8a8a")
        return canvas
    if kind == "piston_arm":
        # Extended piston head: the plate face plus the rod behind it.
        canvas = tex_planks("oak", "#a5793f")
        canvas.rect(1, 1, 14, 14, "#8d8d8d")
        canvas.rect(2, 2, 12, 12, "#b0b0b0")
        canvas.rect(4, 4, 8, 8, "#6f6f6f")
        for x in range(3, 13, 2):
            canvas.line(x, 3, x, 12, "#9a9a9a")
        canvas.line(0, 7, 15, 7, "#7a5a2a")
        canvas.line(0, 8, 15, 8, "#6a4a20")
        return canvas
    if kind == "sticky_piston_top":
        canvas = tex_workstation("piston_top", seed)
        canvas.rect(3, 3, 10, 10, "#7fbf4a")
        return canvas
    if kind == "dispenser_front":
        canvas = tex_stone(seed, "#6f6f6f")
        canvas.rect(2, 2, 12, 12, "#4a4a4a")
        canvas.disc(8, 8, 3.4, "#2b2b2b")
        canvas.rect(7, 7, 2, 2, "#d8d8d8")
        return canvas
    if kind == "lever":
        canvas = tex_cobblestone(seed)
        canvas.rect(6, 3, 3, 8, "#8a6a3f")
        canvas.rect(5, 2, 5, 3, "#c8a24a")
        return canvas
    if kind == "pressure_plate":
        canvas = Canvas(TILE)
        canvas.rect(0, 0, TILE, 8, "#8f8f8f")
        canvas.rect(1, 0, 14, 6, "#b0b0b0")
        return canvas
    if kind == "ladder":
        canvas = Canvas(TILE)
        for x in (2, 3, 12, 13):
            for y in range(TILE):
                canvas.set(x, y, "#8a6a3f")
        for y in range(1, TILE, 5):
            for x in range(4, 12):
                canvas.set(x, y, "#a5793f")
                canvas.set(x, y + 1, "#7c5426")
        return canvas
    raise ValueError(f"unknown workstation texture: {kind}")


def tex_bed(kind: str) -> Canvas:
    """Bed block: red blanket with a pillow band (top) and a wooden frame (side)."""
    if kind == "top":
        canvas = Canvas(TILE).fill("#8f2f2f")
        for y in range(4, TILE):  # fabric weave on the blanket
            for x in range(TILE):
                if (x + y) % 4 == 0:
                    canvas.set(x, y, shade("#8f2f2f", 0.92))
        canvas.rect(0, 0, TILE, 4, "#e8e4d8")     # pillow
        canvas.rect(0, 0, TILE, 1, "#c9c4b4")
        canvas.rect(0, 3, TILE, 1, "#6f2323")     # blanket edge
        return canvas
    canvas = tex_planks("oak", "#a5793f")         # frame
    canvas.rect(0, 0, TILE, 5, "#8f2f2f")         # blanket overhangs the frame
    canvas.rect(0, 4, TILE, 1, "#6f2323")
    canvas.rect(2, 8, 12, 4, "#7c5426")           # legs
    return canvas


def tex_cross(kind: str, seed: int = 50) -> Canvas:
    """Plants, torches, dust: transparent sprites rendered as crossed quads."""
    canvas = Canvas(TILE)
    rng = random.Random(seed)
    if kind == "torch":
        for y in range(4, 15):
            canvas.set(7, y, "#7c5426")
            canvas.set(8, y, "#8a6a3f")
        canvas.rect(6, 2, 4, 3, "#ffd166")
        canvas.set(7, 1, "#fff3b0")
        canvas.set(8, 1, "#fff3b0")
        return canvas
    if kind == "redstone_torch":
        for y in range(4, 15):
            canvas.set(7, y, "#7c5426")
            canvas.set(8, y, "#8a6a3f")
        canvas.rect(6, 2, 4, 3, "#e03a20")
        canvas.set(7, 1, "#ffb0a0")
        return canvas
    if kind == "redstone_dust":
        for i in range(2, 14):
            canvas.set(i, 8, "#d82b1f")
            if i % 2 == 0:
                canvas.set(i, 7, "#8f1c14")
        return canvas
    if kind in ("tall_grass", "fern"):
        for x in range(2, 14, 2):
            height = rng.randint(4, 9)
            lean = rng.choice([-1, 0, 1])
            for i in range(height):
                y = 14 - i
                canvas.set(x + (lean if i > height // 2 else 0), y, shade("#5d9c3a", rng.uniform(0.8, 1.2)))
        return canvas
    if kind == "dead_bush":
        for _ in range(9):
            x, y = 8, 14
            dx, dy = rng.choice([-1, 0, 1]), -1
            for _ in range(rng.randint(3, 7)):
                canvas.set(x, y, "#8a6a3f")
                x += dx
                y += dy
        return canvas
    if kind.startswith("flower_"):
        stem_top = 5
        for y in range(stem_top, 15):
            canvas.set(8, y, "#3f7a35")
        canvas.set(6, 11, "#4a8f3d")
        canvas.set(10, 12, "#4a8f3d")
        petal = {
            "flower_dandelion": ("#f8e04a", "#f8c627"),
            "flower_poppy": ("#e33b2f", "#b02a20"),
            "flower_tulip_red": ("#e34a3b", "#a12722"),
            "flower_tulip_orange": ("#f08a2a", "#c46a15"),
            "flower_tulip_white": ("#f2f2f2", "#c9c9c9"),
            "flower_blue_orchid": ("#3fa9e0", "#2a7fb0"),
            "flower_allium": ("#c07fe0", "#8f5fb0"),
        }[kind]
        light, dark = petal
        canvas.rect(6, 3, 5, 3, light)
        canvas.rect(7, 2, 3, 5, light)
        canvas.rect(7, 4, 3, 2, dark)
        canvas.set(7, 3, "#ffffff") if kind == "flower_tulip_white" else None
        canvas.set(8, 2, dark)
        return canvas
    if kind.startswith("sapling_") or kind.endswith("_sapling"):
        wood = kind.split("_", 1)[1] if kind.startswith("sapling_") else kind[:-len("_sapling")]
        _, _, _, _, leaf, alt = WOOD_TYPES[wood]
        for y in range(9, 15):
            canvas.set(7, y, "#6b5132")
            canvas.set(8, y, "#5a4228")
        for y in range(3, 10):
            for x in range(3, 13):
                if math.hypot((x - 8) * 1.0, (y - 6) * 1.4) < 4.4 and rng.random() > 0.12:
                    canvas.set(x, y, shade(leaf if rng.random() < 0.6 else alt, rng.uniform(0.85, 1.15)))
        return canvas
    if kind == "sugar_cane":
        for x in (5, 8, 11):
            for y in range(1, 15):
                if rng.random() > 0.08:
                    canvas.set(x, y, shade("#7fbf5a", rng.uniform(0.85, 1.1)))
        return canvas
    if kind.startswith("wheat_"):
        stage = int(kind.split("_")[-1])
        height = 4 + stage * 3
        for x in range(4, 13, 2):
            for y in range(15 - height, 15):
                canvas.set(x, y, "#8faf4a" if stage < 3 else "#d9b23f")
            if stage >= 2:
                canvas.set(x - 1, 15 - height + 2, "#e8cf6a")
                canvas.set(x + 1, 15 - height + 3, "#e8cf6a")
            if stage >= 3:
                canvas.set(x, 15 - height, "#e8cf6a")
        return canvas
    if kind == "carrots" or kind == "potatoes":
        for x in range(4, 13, 2):
            for y in range(11, 15):
                canvas.set(x, y, "#3f7a35")
        if kind == "carrots":
            for x in range(5, 12, 3):
                canvas.set(x, 13, "#e07a20")
        else:
            for x in range(5, 12, 3):
                canvas.set(x, 13, "#c8a24a")
        return canvas
    if kind == "mushroom_red" or kind == "mushroom_brown":
        cap = "#c0392b" if kind == "mushroom_red" else "#9b7653"
        for y in range(6, 10):
            width = 5 - abs(y - 8)
            for x in range(8 - width, 8 + width + 1):
                canvas.set(x, y, cap)
        if kind == "mushroom_red":
            for x, y in ((6, 7), (10, 8), (8, 6)):
                canvas.set(x, y, "#f2f2f2")
        for y in range(10, 15):
            canvas.set(7, y, "#e8e0cf")
            canvas.set(8, y, "#d9cfb8")
        return canvas
    if kind == "web":
        for i in range(TILE):
            canvas.set(i, i, rgba("#e8e8e8", 150))
            canvas.set(i, TILE - 1 - i, rgba("#e8e8e8", 150))
        for r in (4, 8, 12):
            canvas.disc(8, 8, r, rgba("#e8e8e8", 90), soft=6)
        for i in range(TILE):
            canvas.set(i, 8, rgba("#d8d8d8", 120))
            canvas.set(8, i, rgba("#d8d8d8", 120))
        return canvas
    raise ValueError(f"unknown cross texture: {kind}")


def tex_grass_block_side_snowy() -> Canvas:
    return tex_grass_side(70, grass_color="#f2fafa")


def draw_glyph(canvas: Canvas, char: str, x: int, y: int, color: str) -> None:
    """Tiny 3x5 bitmap font for text baked into block textures."""
    glyphs = {
        "T": [(0, 0), (1, 0), (2, 0), (1, 1), (1, 2), (1, 3), (1, 4)],
        "N": [(0, 0), (0, 1), (0, 2), (0, 3), (0, 4), (1, 1), (1, 2), (2, 0), (2, 1), (2, 2), (2, 3), (2, 4)],
        "A": [(1, 0), (0, 1), (2, 1), (0, 2), (1, 2), (2, 2), (0, 3), (2, 3), (0, 4), (2, 4)],
        "B": [(0, 0), (1, 0), (0, 1), (2, 1), (0, 2), (1, 2), (0, 3), (2, 3), (0, 4), (1, 4)],
        "1": [(1, 0), (0, 1), (1, 1), (1, 2), (1, 3), (1, 4)],
        "2": [(0, 0), (1, 0), (2, 0), (2, 1), (1, 2), (0, 3), (0, 4), (1, 4), (2, 4)],
        "3": [(0, 0), (1, 0), (2, 1), (1, 2), (2, 3), (0, 4), (1, 4)],
        "4": [(0, 0), (0, 1), (2, 0), (2, 1), (0, 2), (1, 2), (2, 2), (2, 3), (2, 4)],
    }
    for (dx, dy) in glyphs.get(char.upper(), []):
        canvas.set(x + dx, y + dy, color)

"""Generates item icons, HUD icons and mob skin atlases.

Mob skins use a fixed 5x3 grid of 16x16 face tiles so the model code can pick
exact rectangles (see `entities.json`): rows are head / body / limbs, columns
are front, side, back, top, extra.
"""

from __future__ import annotations

import math
import random
import zlib

from pixelart import Canvas, mix, rgba, shade
from gen_textures import WOOD_TYPES, draw_glyph

TILE = 16


# ---------------------------------------------------------------------------
# Item shapes
# ---------------------------------------------------------------------------



def _stable_seed(text) -> int:
    """Deterministic stand-in for _stable_seed() - Python salts _stable_seed() per process."""
    return zlib.crc32(str(text).encode("utf-8"))

def ingot(color: str, dark: str) -> Canvas:
    canvas = Canvas(TILE)
    canvas.poly([(4, 11), (11, 11), (13, 8), (6, 8)], color)
    canvas.poly([(6, 8), (13, 8), (12, 6), (5, 6)], shade(color, 1.18))
    canvas.line(5, 7, 12, 7, shade(color, 1.35))
    canvas.line(4, 11, 11, 11, dark)
    canvas.line(11, 11, 13, 8, dark)
    return canvas


def gem(color: str) -> Canvas:
    canvas = Canvas(TILE)
    canvas.poly([(8, 2), (13, 6), (8, 13), (3, 6)], color)
    canvas.poly([(8, 2), (11, 5), (8, 7), (5, 5)], shade(color, 1.3))
    canvas.poly([(8, 7), (11, 5), (8, 13)], shade(color, 0.8))
    canvas.line(3, 6, 13, 6, shade(color, 0.65))
    return canvas


def round_item(
    color: str,
    radius: float = 5.0,
    dark: float = 0.72,
    highlight: bool = True,
) -> Canvas:
    canvas = Canvas(TILE)
    canvas.disc(8, 8.5, radius, color)
    for y in range(TILE):
        for x in range(TILE):
            c = canvas.get(x, y)
            if c[3] == 0:
                continue
            d = math.hypot(x - 8, y - 7.5) / radius
            canvas.set(x, y, shade(color, 1.25 - d * 0.55))
    if highlight:
        canvas.set(6, 5, shade(color, 1.6))
        canvas.set(7, 5, shade(color, 1.45))
        canvas.set(6, 6, shade(color, 1.4))
    for y in range(TILE):
        for x in range(TILE):
            if math.hypot(x - 8, y - 8.5) > radius:
                canvas.set(x, y, (0, 0, 0, 0))
    return canvas


def ingot_nugget(color: str) -> Canvas:
    return round_item(color, 3.0, highlight=False)


def stick_item() -> Canvas:
    canvas = Canvas(TILE)
    for i in range(10):
        canvas.set(4 + i, 12 - i, "#8a6a3f")
        canvas.set(5 + i, 12 - i, "#6b5132")
        canvas.set(4 + i, 13 - i, "#5f4526")
    return canvas


def feather_item() -> Canvas:
    canvas = Canvas(TILE)
    for i in range(9):
        canvas.set(4 + i, 12 - i, "#d8d3c8")
    for y in range(2, 12):
        width = int(3 * math.sin((y - 2) / 9.0 * math.pi)) + 1
        for x in range(3, 3 + width):
            canvas.set(x + (11 - y) // 2, y, "#f2f0ea")
    canvas.set(13, 3, "#c9c4b8")
    return canvas


def leather_item() -> Canvas:
    canvas = Canvas(TILE)
    canvas.poly([(3, 5), (12, 3), (13, 11), (4, 13), (3, 5)], "#a4703f")
    for y in range(TILE):
        for x in range(TILE):
            if canvas.get(x, y)[3] == 0:
                continue
            canvas.set(x, y, shade(canvas.get(x, y), 0.9 + (x + y) % 3 * 0.06))
    canvas.line(4, 6, 12, 5, "#c9a06a")
    return canvas


def bone_item() -> Canvas:
    canvas = Canvas(TILE)
    canvas.rect(7, 4, 2, 8, "#e8e4d8")
    canvas.rect(5, 2, 6, 3, "#f2efe6")
    canvas.rect(5, 11, 6, 3, "#f2efe6")
    canvas.set(5, 2, (0, 0, 0, 0))
    canvas.set(10, 2, (0, 0, 0, 0))
    canvas.set(5, 13, (0, 0, 0, 0))
    canvas.set(10, 13, (0, 0, 0, 0))
    return canvas


def paper_item() -> Canvas:
    canvas = Canvas(TILE)
    canvas.rect(3, 3, 10, 10, "#f2f0e8")
    for y in range(4, 12, 2):
        canvas.line(4, y, 11, y, "#c9c4b0")
    return canvas


def book_item() -> Canvas:
    canvas = Canvas(TILE)
    canvas.rect(3, 2, 10, 12, "#8b3f2f")
    canvas.rect(4, 3, 8, 10, "#f2eee2")
    canvas.rect(4, 3, 2, 10, "#c9b48a")
    return canvas


def wheat_item() -> Canvas:
    canvas = Canvas(TILE)
    for i in range(11):
        canvas.set(4 + i, 13 - i, "#8faf4a")
    for i in range(4):
        y = 3 + i * 2
        canvas.set(9 - i, y + 2, "#d9b23f")
        canvas.set(10 - i, y + 3, "#e8cf6a")
        canvas.set(11 - i, y + 4, "#d9b23f")
    return canvas


def seeds_item(color: str = "#7fbf4a") -> Canvas:
    canvas = Canvas(TILE)
    rng = random.Random(4)
    for _ in range(9):
        x, y = rng.randint(3, 11), rng.randint(4, 12)
        canvas.rect(x, y, 2, 1, color)
    return canvas


def dust_item(color: str = "#d82b1f") -> Canvas:
    canvas = Canvas(TILE)
    rng = random.Random(7)
    for _ in range(26):
        x, y = rng.randint(3, 12), rng.randint(3, 12)
        canvas.set(x, y, shade(color, rng.uniform(0.75, 1.25)))
        if rng.random() < 0.4:
            canvas.set(x + 1, y, shade(color, rng.uniform(0.7, 1.1)))
    return canvas


def string_item() -> Canvas:
    canvas = Canvas(TILE)
    canvas.line(3, 3, 12, 6, "#e8e8e8")
    canvas.line(12, 6, 4, 9, "#d8d8d8")
    canvas.line(4, 9, 12, 12, "#e8e8e8")
    return canvas


def arrow_item() -> Canvas:
    canvas = Canvas(TILE)
    for i in range(11):
        canvas.set(3 + i, 12 - i, "#8a6a3f")
    canvas.poly([(13, 2), (14, 3), (11, 3), (12, 2)], "#d8d8d8")
    canvas.poly([(3, 12), (4, 13), (2, 13), (2, 12)], "#e8e8e8")
    canvas.set(2, 11, "#e8e8e8")
    canvas.set(4, 13, "#e8e8e8")
    return canvas


def bucket_item(fill: str | None = None) -> Canvas:
    canvas = Canvas(TILE)
    canvas.poly([(3, 5), (13, 5), (11, 13), (5, 13)], "#c9c9d2")
    canvas.line(3, 5, 13, 5, "#e8e8f0")
    for x in range(3, 14, 3):
        canvas.line(x, 6, x - 1, 12, "#a8a8b2")
    if fill:
        canvas.rect(5, 6, 7, 3, fill)
    return canvas


def flint_and_steel() -> Canvas:
    canvas = Canvas(TILE)
    canvas.poly([(4, 6), (9, 4), (11, 9), (6, 11)], "#8f8f96")
    canvas.line(4, 6, 9, 4, "#c9c9d2")
    canvas.poly([(10, 10), (13, 13), (8, 14)], "#d9b23f")
    return canvas


def bow_item() -> Canvas:
    canvas = Canvas(TILE)
    for i in range(11):
        canvas.set(4 + (i // 4), 2 + i, "#8a6a3f")
        canvas.set(5 + (i // 4), 2 + i, "#a5793f")
    canvas.line(9, 12, 5, 3, "#e8e8e8")
    canvas.line(9, 12, 13, 8, "#d8d8d8")
    return canvas


def apple_item(golden: bool = False) -> Canvas:
    color = "#f2d24a" if golden else "#d13a24"
    canvas = round_item(color, 5.0)
    canvas.set(8, 3, "#4a3a20")
    canvas.set(9, 2, "#3f7a35")
    canvas.set(10, 2, "#4a8f3d")
    return canvas


def bread_item() -> Canvas:
    canvas = Canvas(TILE)
    canvas.poly([(2, 10), (4, 5), (12, 4), (14, 9), (12, 13), (4, 13)], "#c8933f")
    canvas.poly([(4, 6), (12, 5), (13, 8), (3, 9)], "#dcae5f")
    for x in range(5, 12, 3):
        canvas.set(x, 7, "#a3702a")
        canvas.set(x + 1, 8, "#a3702a")
    return canvas


def meat_item(cooked: bool, name: str) -> Canvas:
    base = "#b0503a" if not cooked else "#8f5a2a"
    if "chicken" in name:
        base = "#e8b27f" if not cooked else "#c9834a"
    if "mutton" in name:
        base = "#c05a4a" if not cooked else "#8f4a30"
    canvas = Canvas(TILE)
    canvas.poly([(3, 6), (11, 4), (13, 10), (6, 13), (3, 10)], base)
    canvas.disc(6.5, 8.5, 3.0, shade(base, 1.2))
    canvas.disc(11.0, 7.0, 2.0, shade(base, 1.15))
    for y in range(TILE):
        for x in range(TILE):
            if canvas.get(x, y)[3] == 0:
                continue
            canvas.set(x, y, shade(canvas.get(x, y), 0.95 + ((x * 3 + y) % 4) * 0.03))
    canvas.set(2, 11, "#e8e0cf")  # bone nub
    canvas.set(2, 10, "#f2efe6")
    return canvas


def vegetable_item(kind: str) -> Canvas:
    canvas = Canvas(TILE)
    if kind == "carrot":
        canvas.poly([(5, 4), (11, 5), (9, 13), (6, 12)], "#e07a20")
        for y in range(6, 12, 2):
            canvas.line(6, y, 9, y + 1, "#c05f14")
        canvas.set(6, 3, "#3f7a35")
        canvas.set(7, 2, "#4a8f3d")
        canvas.set(9, 3, "#3f7a35")
    elif kind == "potato":
        canvas.disc(8, 9, 4.6, "#c8a24a")
        rng = random.Random(3)
        for _ in range(9):
            canvas.set(rng.randint(4, 11), rng.randint(6, 12), "#8f7030")
    elif kind == "baked_potato":
        canvas.disc(8, 9, 4.6, "#b07a3a")
        rng = random.Random(5)
        for _ in range(10):
            canvas.set(rng.randint(4, 11), rng.randint(6, 12), "#7f5a26")
    elif kind == "cookie":
        canvas.disc(8, 8, 4.6, "#c8933f")
        rng = random.Random(9)
        for _ in range(7):
            canvas.set(rng.randint(5, 11), rng.randint(5, 11), "#5f3f1c")
    elif kind == "melon_slice":
        canvas.poly([(2, 12), (8, 3), (14, 12)], "#4f8f2a")
        canvas.poly([(4, 12), (8, 6), (12, 12)], "#e35a4a")
        for x in range(5, 12, 2):
            canvas.set(x, 11, "#2f2f2f")
    elif kind == "pumpkin_pie":
        canvas.disc(8, 9, 5.0, "#e0a23f")
        canvas.disc(8, 8, 3.4, "#f2c96a")
        for x in range(4, 12, 2):
            canvas.set(x, 6, "#c9834a")
    elif kind == "stew":
        canvas.poly([(2, 8), (14, 8), (12, 13), (4, 13)], "#8f5a2a")
        canvas.rect(2, 7, 12, 2, "#a4703f")
        canvas.rect(4, 3, 8, 4, "#b0503a")
        canvas.set(6, 4, "#e07a20")
        canvas.set(9, 5, "#3f7a35")
    elif kind == "rotten_flesh":
        canvas.poly([(3, 5), (11, 3), (13, 10), (6, 13)], "#6f5a3a")
        rng = random.Random(11)
        for _ in range(14):
            canvas.set(rng.randint(4, 12), rng.randint(4, 12), rng.choice(["#4f7a3a", "#8f7a4a", "#3f5a2a"]))
    return canvas


def slimeball() -> Canvas:
    canvas = round_item("#7fbf4a", 5.0)
    canvas.disc(6.0, 6.0, 1.6, rgba("#c9f2a0", 180))
    return canvas


def snowball() -> Canvas:
    return round_item("#eef6ff", 5.0)


def egg_item() -> Canvas:
    canvas = Canvas(TILE)
    for y in range(TILE):
        for x in range(TILE):
            d = math.hypot((x - 8) / 4.2, (y - 9) / 6.0)
            if d <= 1.0:
                canvas.set(x, y, shade("#f2ece0", 1.15 - d * 0.3))
    rng = random.Random(13)
    for _ in range(8):
        canvas.set(rng.randint(5, 11), rng.randint(4, 13), "#d8d0c0")
    return canvas


def shears_item() -> Canvas:
    canvas = Canvas(TILE)
    canvas.line(3, 12, 11, 4, "#c9c9d2")
    canvas.line(4, 12, 12, 5, "#8f8f96")
    canvas.line(11, 12, 4, 5, "#c9c9d2")
    canvas.line(12, 12, 5, 6, "#8f8f96")
    canvas.rect(3, 12, 2, 2, "#5f5f66")
    canvas.rect(11, 12, 2, 2, "#5f5f66")
    return canvas


# ---------------------------------------------------------------------------
# Tools & armour
# ---------------------------------------------------------------------------

TOOL_MATERIALS = {
    "wood": ("#a5793f", "#6b5132"),
    "stone": ("#9d9d9d", "#6f6f6f"),
    "iron": ("#e0e0e6", "#a8a8b2"),
    "gold": ("#f8d84a", "#c9a227"),
    "diamond": ("#5ce8dc", "#2fa8a0"),
    "netherite": ("#6b5f66", "#3f363c"),
}

TOOL_KINDS = ["pickaxe", "axe", "shovel", "sword", "hoe"]


def tool_item(kind: str, material: str) -> Canvas:
    light, dark = TOOL_MATERIALS[material]
    handle = "#8a6a3f"
    canvas = Canvas(TILE)
    if kind == "sword":
        for i in range(7):
            canvas.set(11 - i, 3 + i, light)
            canvas.set(12 - i, 3 + i, dark)
        canvas.rect(7, 8, 5, 2, "#8f8f96")
        canvas.rect(9, 10, 3, 3, handle)
        canvas.set(10, 13, "#6b5132")
        return canvas
    # common handle, leaning up-right
    for i in range(9):
        canvas.set(5 + i, 13 - i, handle)
        canvas.set(6 + i, 13 - i, shade(handle, 0.75))
    if kind == "pickaxe":
        canvas.line(8, 3, 13, 5, light)
        canvas.line(7, 4, 12, 6, light)
        canvas.line(6, 5, 11, 7, dark)
        canvas.set(7, 3, light)
        canvas.set(9, 2, light)
        canvas.set(11, 3, light)
        canvas.set(13, 6, dark)
    elif kind == "axe":
        canvas.poly([(9, 2), (13, 3), (13, 8), (9, 7)], light)
        canvas.poly([(10, 3), (12, 4), (12, 6), (10, 6)], shade(light, 0.85))
        canvas.line(9, 2, 13, 3, shade(light, 1.3))
        canvas.set(13, 7, dark)
    elif kind == "shovel":
        canvas.poly([(8, 2), (13, 3), (13, 7), (8, 6)], light)
        canvas.poly([(9, 3), (12, 4), (12, 6)], shade(light, 1.2))
    elif kind == "hoe":
        canvas.rect(8, 3, 5, 2, light)
        canvas.rect(11, 5, 2, 2, dark)
        canvas.set(8, 3, shade(light, 1.3))
    return canvas


def armor_item(kind: str, material: str) -> Canvas:
    if material == "leather":
        light, dark = "#a4703f", "#6f4a26"
    elif material == "iron":
        light, dark = "#e0e0e6", "#a8a8b2"
    elif material == "gold":
        light, dark = "#f8d84a", "#c9a227"
    else:
        light, dark = "#5ce8dc", "#2fa8a0"
    canvas = Canvas(TILE)
    if kind == "helmet":
        canvas.poly([(3, 9), (4, 4), (11, 4), (12, 9), (10, 9), (9, 6), (6, 6), (5, 9)], light)
        canvas.rect(4, 8, 8, 2, light)
        canvas.line(4, 4, 11, 4, shade(light, 1.25))
        canvas.rect(5, 9, 6, 3, dark)
        canvas.rect(6, 12, 4, 1, shade(dark, 0.85))
    elif kind == "chestplate":
        canvas.poly([(4, 4), (11, 4), (12, 7), (11, 12), (4, 12), (3, 7)], light)
        canvas.rect(1, 5, 3, 4, light)
        canvas.rect(12, 5, 3, 4, light)
        canvas.rect(6, 4, 4, 3, dark)
        canvas.line(4, 5, 11, 5, shade(light, 1.3))
        canvas.set(8, 9, dark)
    elif kind == "leggings":
        canvas.rect(4, 3, 8, 4, light)
        canvas.rect(4, 7, 3, 7, dark)
        canvas.rect(9, 7, 3, 7, dark)
        canvas.rect(4, 7, 8, 1, light)
        canvas.line(4, 3, 11, 3, shade(light, 1.25))
    else:  # boots
        canvas.rect(3, 8, 4, 5, light)
        canvas.rect(9, 8, 4, 5, light)
        canvas.rect(3, 12, 5, 2, dark)
        canvas.rect(9, 12, 5, 2, dark)
        canvas.line(3, 8, 6, 8, shade(light, 1.25))
        canvas.line(9, 8, 12, 8, shade(light, 1.25))
    return canvas


# ---------------------------------------------------------------------------
# HUD icons
# ---------------------------------------------------------------------------


def heart(state: str) -> Canvas:
    canvas = Canvas(9)
    shape = [
        (1, 1), (2, 1), (6, 1), (7, 1),
        (0, 2), (1, 2), (2, 2), (3, 2), (4, 2), (5, 2), (6, 2), (7, 2), (8, 2),
        (0, 3), (1, 3), (2, 3), (3, 3), (4, 3), (5, 3), (6, 3), (7, 3), (8, 3),
        (0, 4), (1, 4), (2, 4), (3, 4), (4, 4), (5, 4), (6, 4), (7, 4), (8, 4),
        (1, 5), (2, 5), (3, 5), (4, 5), (5, 5), (6, 5), (7, 5),
        (2, 6), (3, 6), (4, 6), (5, 6), (6, 6),
        (3, 7), (4, 7), (5, 7),
        (4, 8),
    ]
    for (x, y) in shape:
        half = state == "half" and x > 4
        color = "#2b2b2b" if (state == "empty" or half) else "#d13a24"
        canvas.set(x, y, color)
        if state == "full" and (x, y) in ((1, 2), (2, 2), (1, 3)):
            canvas.set(x, y, "#f2766a")
        if half and x == 5:
            canvas.set(x, y, "#8f1f10")
    return canvas


def hunger_icon(state: str) -> Canvas:
    canvas = Canvas(9)
    border = "#2b2b2b"
    for y in range(2, 8):
        width = 4 - abs(y - 4)
        for x in range(4 - width, 4 + width + 1):
            filled = state == "full" or (state == "half" and x < 4)
            canvas.set(x, y, "#b06a2a" if filled else border)
    canvas.set(4, 1, border)
    canvas.set(3, 1, border)
    canvas.set(5, 1, border)
    canvas.set(2, 3, border)
    canvas.set(6, 3, border)
    canvas.set(1, 4, border)
    canvas.set(7, 4, border)
    if state == "full":
        canvas.set(3, 3, "#e0a050")
    return canvas


def bubble_icon(state: str = "full") -> Canvas:
    canvas = Canvas(9)
    canvas.disc(4.5, 4.5, 4.0, rgba("#cfe8ff", 235) if state == "full" else rgba("#3a4a5a", 160))
    canvas.set(3, 2, rgba("#ffffff", 220))
    canvas.set(4, 2, rgba("#ffffff", 200))
    return canvas


def crosshair() -> Canvas:
    canvas = Canvas(16)
    for i in range(4, 12):
        canvas.set(i, 7, rgba("#ffffff", 200))
        canvas.set(i, 8, rgba("#ffffff", 200))
        canvas.set(7, i, rgba("#ffffff", 200))
        canvas.set(8, i, rgba("#ffffff", 200))
    canvas.set(7, 7, (0, 0, 0, 0))
    canvas.set(8, 8, (0, 0, 0, 0))
    return canvas


def hotbar_slot(selected: bool = False) -> Canvas:
    canvas = Canvas(20)
    canvas.rect(0, 0, 20, 20, rgba("#1b1b1b", 150 if not selected else 190))
    canvas.frame(0, 0, 20, 20, rgba("#3a3a3a", 255))
    if selected:
        canvas.frame(0, 0, 20, 20, rgba("#ffffff", 255))
        canvas.frame(1, 1, 18, 18, rgba("#c9c9c9", 200))
    return canvas


def break_stage(stage: int) -> Canvas:
    canvas = Canvas(TILE)
    rng = random.Random(stage * 17 + 3)
    cracks = 2 + stage * 2
    for _ in range(cracks):
        x, y = rng.randint(2, 13), rng.randint(2, 13)
        length = rng.randint(2, 5 + stage)
        dx = rng.choice([-1, 0, 1])
        dy = rng.choice([-1, 1])
        for i in range(length):
            canvas.set(x + i * dx, y + i * dy, rgba("#101010", 170))
    return canvas


def cloud_texture() -> Canvas:
    size = 128
    canvas = Canvas(size)
    rng = random.Random(21)
    blobs = [(x, y, rng.uniform(8, 20)) for x in range(0, size, 24) for y in range(0, size, 24)]
    for (cx, cy, r) in blobs:
        for y in range(size):
            for x in range(size):
                d = math.hypot(min(abs(x - cx), size - abs(x - cx)), min(abs(y - cy), size - abs(y - cy)))
                if d < r * 0.62:
                    canvas.set(x, y, rgba("#ffffff", 190))
                elif d < r:
                    canvas.set(x, y, rgba("#f2f6ff", int(150 * (1 - (d - r * 0.62) / (r * 0.38)))))
    return canvas


def logo_texture() -> Canvas:
    size = 128
    canvas = Canvas(size)
    canvas.rect(0, 0, size, size, (0, 0, 0, 0))
    # isometric grass block
    top = [(64, 6), (122, 38), (64, 70), (6, 38)]
    left = [(6, 38), (64, 70), (64, 122), (6, 90)]
    right = [(122, 38), (64, 70), (64, 122), (122, 90)]
    canvas.poly(top, "#5d9c3a")
    canvas.poly(left, "#79553a")
    canvas.poly(right, "#5f4128")
    rng = random.Random(2)
    for y in range(size):
        for x in range(size):
            if canvas.get(x, y)[3] == 0:
                continue
            canvas.set(x, y, shade(canvas.get(x, y), rng.uniform(0.9, 1.15)))
    canvas.poly(top, rgba("#5d9c3a", 60))
    for i in range(0, 60, 6):
        canvas.set(6 + i, 38 + i, rgba("#000000", 40))
    return canvas


def sun_texture() -> Canvas:
    canvas = Canvas(32)
    canvas.disc(16, 16, 9, "#fff3b0")
    canvas.disc(16, 16, 6, "#fff9dc")
    return canvas


def moon_texture() -> Canvas:
    canvas = Canvas(32)
    canvas.disc(16, 16, 9, "#e8ecff")
    canvas.disc(12, 13, 8, (0, 0, 0, 0))
    return canvas


# ---------------------------------------------------------------------------
# Mob skins (5x3 grid of 16px tiles)
# ---------------------------------------------------------------------------

SKIN_COLS, SKIN_ROWS = 5, 3

SKIN_TILES = {
    "head_front": (0, 0), "head_side": (1, 0), "head_back": (2, 0), "head_top": (3, 0),
    "body_front": (0, 1), "body_side": (1, 1), "body_back": (2, 1), "body_top": (3, 1),
    "limb_side": (4, 1), "limb_top": (0, 2), "extra_a": (1, 2), "extra_b": (2, 2),
    "extra_c": (3, 2), "extra_d": (4, 2),
}


def _tile_canvas(skin: Canvas, key: str) -> Canvas:
    col, row = SKIN_TILES[key]
    x0, y0 = col * TILE, row * TILE
    tile = Canvas(TILE)
    for y in range(TILE):
        for x in range(TILE):
            tile.set(x, y, skin.get(x0 + x, y0 + y))
    return tile


def _put_tile(skin: Canvas, key: str, tile: Canvas) -> None:
    col, row = SKIN_TILES[key]
    x0, y0 = col * TILE, row * TILE
    for y in range(TILE):
        for x in range(TILE):
            skin.set(x0 + x, y0 + y, tile.get(x, y))


def _skin_base(color: str, seed: int, contrast: float = 0.1) -> Canvas:
    canvas = Canvas(TILE)
    rng = random.Random(seed)
    for y in range(TILE):
        for x in range(TILE):
            canvas.set(x, y, shade(color, 1.0 + rng.uniform(-contrast, contrast)))
    return canvas


def _eyes(tile: Canvas, color: str = "#241a09", white: str | None = None, y: int = 6, xs=(4, 10), size: int = 2) -> None:
    for x in xs:
        tile.rect(x, y, size, size, color)
        if white:
            tile.set(x + 1, y, white)


def skin_humanoid(
    skin_color: str,
    hair: str,
    shirt: str,
    pants: str,
    shoes: str,
    seed: int = 1,
    face: str = "player",
) -> Canvas:
    canvas = Canvas(TILE * SKIN_COLS, TILE * SKIN_ROWS)
    # head
    head_front = _skin_base(skin_color, seed)
    head_front.rect(0, 0, TILE, 4, hair)
    head_front.rect(0, 4, 2, 4, hair)
    head_front.rect(14, 4, 2, 4, hair)
    if face == "player":
        _eyes(head_front, white="#f2f2f2")
        head_front.rect(6, 9, 4, 1, "#7a5a3a")
        head_front.set(7, 8, shade(skin_color, 0.85))
    elif face == "zombie":
        _eyes(head_front, color="#1b2a12")
        head_front.rect(6, 10, 4, 2, "#3f5a24")
        head_front.rect(6, 9, 4, 1, "#2b3a18")
    elif face == "villager":
        head_front.rect(5, 7, 2, 2, "#f2f2f2")
        head_front.rect(9, 7, 2, 2, "#f2f2f2")
        head_front.rect(6, 10, 4, 3, "#a4703f")
    elif face == "skeleton":
        head_front.rect(4, 3, 8, 8, "#e8e4d8")
        _eyes(head_front, color="#241a09")
        head_front.rect(7, 9, 2, 2, "#8f8a7a")
        for x in range(5, 11, 2):
            head_front.set(x, 9, "#e8e4d8")
    _put_tile(canvas, "head_front", head_front)
    head_side = _skin_base(skin_color, seed + 1)
    head_side.rect(0, 0, TILE, 4, hair)
    head_side.rect(0, 4, 3, 4, hair)
    if face == "skeleton":
        head_side.rect(2, 6, 4, 4, "#e8e4d8")
    _put_tile(canvas, "head_side", head_side)
    head_back = _skin_base(skin_color, seed + 2)
    head_back.rect(0, 0, TILE, 7, hair)
    _put_tile(canvas, "head_back", head_back)
    head_top = _skin_base(hair if face != "skeleton" else "#e8e4d8", seed + 3)
    _put_tile(canvas, "head_top", head_top)
    # body
    body_front = _skin_base(shirt, seed + 4)
    body_front.rect(0, 0, TILE, 2, shade(shirt, 0.8))
    if face == "zombie":
        for i in range(4):  # torn shirt
            body_front.rect(2 + i * 3, 10, 2, 4, shade(shirt, 0.8))
    elif face == "skeleton":
        body_front = _skin_base("#d8d4c6", seed + 4)
        body_front.rect(4, 2, 8, 12, "#e8e4d8")
        for y in range(4, 14, 3):
            body_front.rect(3, y, 10, 1, "#b8b4a6")
    _put_tile(canvas, "body_front", body_front)
    _put_tile(canvas, "body_side", _skin_base(shirt, seed + 5))
    _put_tile(canvas, "body_back", _skin_base(shade(shirt, 0.9), seed + 6))
    _put_tile(canvas, "body_top", _skin_base(shade(shirt, 0.75), seed + 7))
    # limbs
    limb = _skin_base(shirt if face != "skeleton" else "#d8d4c6", seed + 8)
    limb.rect(0, 10, TILE, 6, pants)
    _put_tile(canvas, "limb_side", limb)
    limb_top = _skin_base(skin_color if face != "skeleton" else "#e8e4d8", seed + 9)
    _put_tile(canvas, "limb_top", limb_top)
    _put_tile(canvas, "extra_a", _skin_base(skin_color, seed + 10))
    boot = _skin_base(shoes, seed + 11)
    _put_tile(canvas, "extra_b", boot)
    _put_tile(canvas, "extra_c", boot)
    _put_tile(canvas, "extra_d", _skin_base(pants, seed + 12))
    return canvas


def _camo(seed: int, base: str = "#4a9c2a", dark: str = "#2f6f1c", light: str = "#6fbf3a") -> Canvas:
    tile = _skin_base(base, seed, contrast=0.08)
    rng = random.Random(seed)
    for _ in range(9):
        x, y = rng.randint(-2, 14), rng.randint(-2, 14)
        w, h = rng.randint(2, 5), rng.randint(2, 5)
        color = dark if rng.random() < 0.6 else light
        tile.rect(x, y, w, h, color)
    return tile


def skin_creeper_sheet() -> Canvas:
    canvas = Canvas(TILE * SKIN_COLS, TILE * SKIN_ROWS)
    face = _camo(31)
    _eyes(face, color="#141414", y=5, xs=(3, 9), size=3)
    face.rect(5, 9, 6, 5, "#141414")
    face.rect(6, 10, 4, 3, "#2b2b2b")
    _put_tile(canvas, "head_front", face)
    _put_tile(canvas, "head_side", _camo(32))
    _put_tile(canvas, "head_back", _camo(33))
    _put_tile(canvas, "head_top", _camo(34))
    for key, seed in (
        ("body_front", 35), ("body_side", 36), ("body_back", 37), ("body_top", 38),
        ("limb_side", 39), ("limb_top", 40), ("extra_a", 41), ("extra_b", 42),
        ("extra_c", 43), ("extra_d", 44),
    ):
        _put_tile(canvas, key, _camo(seed))
    return canvas


def skin_pig() -> Canvas:
    canvas = Canvas(TILE * SKIN_COLS, TILE * SKIN_ROWS)
    pink = "#e8a0a8"
    face = _skin_base(pink, 51)
    face.rect(3, 8, 10, 6, "#d98a94")  # snout
    for x in (5, 8):
        face.rect(x, 10, 2, 2, "#a05a66")
    _eyes(face, color="#2b1a1a", y=5, xs=(4, 10), size=2)
    _put_tile(canvas, "head_front", face)
    _put_tile(canvas, "head_side", _skin_base(pink, 52))
    _put_tile(canvas, "head_back", _skin_base(pink, 53))
    top = _skin_base("#f0b0b8", 54)
    top.rect(4, 4, 8, 8, "#d98a94")
    _put_tile(canvas, "head_top", top)
    body = _skin_base(pink, 55)
    body.rect(0, 4, TILE, 4, "#d98a94")
    _put_tile(canvas, "body_front", body)
    _put_tile(canvas, "body_side", _skin_base(pink, 56))
    _put_tile(canvas, "body_back", _skin_base(pink, 57))
    _put_tile(canvas, "body_top", _skin_base(pink, 58))
    limb = _skin_base("#d98a94", 59)
    limb.rect(0, 12, TILE, 4, "#a05a66")
    _put_tile(canvas, "limb_side", limb)
    for key in ("limb_top", "extra_a", "extra_b", "extra_c", "extra_d"):
        _put_tile(canvas, key, _skin_base(pink, _stable_seed(key) % 90))
    tail = _skin_base(pink, 60)
    tail.rect(6, 4, 4, 4, "#d98a94")
    _put_tile(canvas, "extra_a", tail)
    return canvas


def skin_cow() -> Canvas:
    canvas = Canvas(TILE * SKIN_COLS, TILE * SKIN_ROWS)
    hide = "#4a3a2a"

    def spotted(seed: int, base: str = hide) -> Canvas:
        tile = _skin_base(base, seed, contrast=0.08)
        rng = random.Random(seed)
        for _ in range(4):
            x, y = rng.randint(-3, 12), rng.randint(-3, 12)
            w, h = rng.randint(4, 8), rng.randint(4, 7)
            tile.rect(x, y, w, h, "#f2f0e8")
        return tile

    face = spotted(71)
    face.rect(4, 10, 8, 5, "#f2f0e8")
    for x in (6, 8):
        face.rect(x, 12, 2, 2, "#7a4a5a")
    _eyes(face, color="#241a09", y=6, xs=(4, 10), size=2)
    face.rect(2, 2, 3, 3, "#e8e4d8")  # horns
    face.rect(11, 2, 3, 3, "#e8e4d8")
    _put_tile(canvas, "head_front", face)
    _put_tile(canvas, "head_side", spotted(72))
    _put_tile(canvas, "head_back", spotted(73))
    _put_tile(canvas, "head_top", spotted(74))
    for key, seed in (
        ("body_front", 75), ("body_side", 76), ("body_back", 77), ("body_top", 78),
        ("limb_side", 79), ("limb_top", 80), ("extra_a", 81), ("extra_b", 82),
        ("extra_c", 83), ("extra_d", 84),
    ):
        _put_tile(canvas, key, spotted(seed))
    return canvas


def skin_sheep(wool: str = "#e8e4d8") -> Canvas:
    canvas = Canvas(TILE * SKIN_COLS, TILE * SKIN_ROWS)

    def fleece(seed: int) -> Canvas:
        tile = _skin_base(wool, seed, contrast=0.12)
        rng = random.Random(seed)
        for _ in range(22):
            x, y = rng.randint(0, 15), rng.randint(0, 15)
            tile.set(x, y, shade(wool, rng.uniform(0.82, 1.1)))
            tile.set((x + 1) % TILE, y, shade(wool, rng.uniform(0.85, 1.05)))
        return tile

    face = _skin_base("#d8cfc0", 91)
    face.rect(0, 0, TILE, 5, wool)
    face.rect(0, 5, 3, 4, wool)
    face.rect(13, 5, 3, 4, wool)
    _eyes(face, color="#241a09", y=8, xs=(5, 9), size=2)
    _put_tile(canvas, "head_front", face)
    _put_tile(canvas, "head_side", fleece(92))
    _put_tile(canvas, "head_back", fleece(93))
    _put_tile(canvas, "head_top", fleece(94))
    for key, seed in (
        ("body_front", 95), ("body_side", 96), ("body_back", 97), ("body_top", 98),
        ("limb_side", 99), ("limb_top", 100), ("extra_a", 101), ("extra_b", 102),
        ("extra_c", 103), ("extra_d", 104),
    ):
        _put_tile(canvas, key, fleece(seed))
    return canvas


def skin_chicken() -> Canvas:
    canvas = Canvas(TILE * SKIN_COLS, TILE * SKIN_ROWS)
    white = "#f2f0e8"
    face = _skin_base(white, 111)
    face.poly([(8, 8), (12, 11), (8, 13), (4, 11)], "#f0a030")  # beak
    _eyes(face, color="#241a09", y=5, xs=(4, 10), size=2)
    face.rect(6, 2, 5, 3, "#d13a24")  # comb
    _put_tile(canvas, "head_front", face)
    _put_tile(canvas, "head_side", _skin_base(white, 112))
    _put_tile(canvas, "head_back", _skin_base(white, 113))
    _put_tile(canvas, "head_top", _skin_base("#d13a24", 114))
    body = _skin_base(white, 115)
    for i in range(3):  # wing feathers
        body.rect(3, 6 + i * 3, 10, 1, "#d8d4c6")
    _put_tile(canvas, "body_front", body)
    _put_tile(canvas, "body_side", _skin_base(white, 116))
    _put_tile(canvas, "body_back", _skin_base(white, 117))
    _put_tile(canvas, "body_top", _skin_base(white, 118))
    _put_tile(canvas, "limb_side", _skin_base("#f0a030", 119))
    for key in ("limb_top", "extra_a"):
        _put_tile(canvas, key, _skin_base(white, _stable_seed(key) % 90))
    for key in ("extra_b", "extra_c", "extra_d"):
        _put_tile(canvas, key, _skin_base("#f0a030", _stable_seed(key) % 90))
    return canvas


def skin_cat() -> Canvas:
    canvas = Canvas(TILE * SKIN_COLS, TILE * SKIN_ROWS)
    fur = "#c98a3a"
    face = _skin_base(fur, 121)
    face.set(3, 3, fur)
    face.set(4, 2, fur)
    face.set(11, 3, fur)
    face.set(12, 2, fur)
    face.rect(5, 2, 6, 3, shade(fur, 0.85))
    _eyes(face, color="#2f6f1c", y=6, xs=(4, 10), size=2)
    face.rect(7, 9, 2, 2, "#e8a0a8")
    face.rect(8, 10, 1, 1, "#a05a66")
    for x in (3, 6, 9, 12):
        face.rect(x, 11, 1, 3, "#f2f0e8")
    _put_tile(canvas, "head_front", face)
    _put_tile(canvas, "head_side", _skin_base(fur, 122))
    _put_tile(canvas, "head_back", _skin_base(fur, 123))
    _put_tile(canvas, "head_top", _skin_base(fur, 124))
    for key, seed in (
        ("body_front", 125), ("body_side", 126), ("body_back", 127), ("body_top", 128),
        ("limb_side", 129), ("limb_top", 130), ("extra_a", 131), ("extra_b", 132),
        ("extra_c", 133), ("extra_d", 134),
    ):
        _put_tile(canvas, key, _skin_base(fur, seed))
    return canvas


def skin_skin_library() -> dict[str, Canvas]:
    return {
        "player": skin_humanoid("#c98a5a", "#3f2a15", "#2f8fb0", "#3a3f8f", "#4a4a4a", 1, "player"),
        "zombie": skin_humanoid("#4a7a3a", "#2b3a18", "#3f6a9c", "#2f3a5a", "#3a3a3a", 61, "zombie"),
        "skeleton": skin_humanoid("#d8d4c6", "#c9c4b0", "#d8d4c6", "#c9c4b0", "#a8a496", 65, "skeleton"),
        "creeper": skin_creeper_sheet(),
        "pig": skin_pig(),
        "cow": skin_cow(),
        "sheep": skin_sheep(),
        "chicken": skin_chicken(),
        "cat": skin_cat(),
        # Villagers: brown robe, big nose, bald head - close enough to the
        # blocky look and it keeps them distinguishable from the player.
        "villager": skin_humanoid("#c98a5a", "#8a6a3a", "#7a5a2a", "#4a3a20", "#3a3020", 137,
                                  "villager"),
    }

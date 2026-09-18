"""Imports a texture pack into the generated art the game loads.

Why this exists: the game ships with its own procedurally generated art, but a
lot of people want Minecraft-style textures. Those textures belong to Mojang, so
this repository cannot ship them - instead this tool takes a pack **you** have on
disk and maps it onto the game's tile names. Nothing copyrighted ends up in git
(see `.gitignore`: `assets/pack/` is ignored).

Typical use:

    python3 tools/pack_import.py --pack ~/Downloads/SomePack --tile 16
    python3 tools/gen_assets.py textures      # rebuild the atlas from the pack
    godot --path .                            # the game now renders with it

Name matching runs in three passes:

  1. an explicit entry in `--map FILE` (JSON: `{"pack_file_stem": "tile_name"}`),
  2. the built-in table below, which covers Bedrock and Java conventions,
  3. normalisation heuristics (`log_oak` -> `oak_log_side`, `planks_oak` ->
     `oak_planks`, `wool_colored_red` -> `red_wool`, stripping `_carried`, ...).

Tiles with no match keep the generated art, and the report says which ones, so a
mixed result is expected and visible rather than silent.
"""

from __future__ import annotations

import argparse
import json
import os
import sys

import pngread
from pixelart import Canvas, write_png

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ATLAS_MANIFEST = os.path.join(ROOT, "assets", "generated", "atlas.json")
PACK_ROOT = os.path.join(ROOT, "assets", "pack")
PACK_TILES = os.path.join(PACK_ROOT, "tiles")
PACK_MANIFEST = os.path.join(PACK_ROOT, "pack.json")

WOODS = ("oak", "birch", "spruce", "jungle")
WOOL_COLORS = ("white", "orange", "magenta", "light_blue", "yellow", "lime", "pink", "gray",
               "light_gray", "cyan", "purple", "blue", "brown", "green", "red", "black")
ORES = ("coal", "iron", "copper", "gold", "diamond", "emerald", "redstone", "lapis_lazuli")

#: Source file stem (lower case, no extension) -> game tile name.
NAME_MAP: dict[str, str] = {
    # terrain
    "grass_top": "grass_top",
    "grass_carried": "grass_top",
    "grass_side": "grass_side",
    "grass_side_carried": "grass_side",
    "grass_side_snowed": "grass_side_snowy",
    "grass_side_snowy": "grass_side_snowy",
    "dirt": "dirt",
    "coarse_dirt": "coarse_dirt",
    "sand": "sand",
    "red_sand": "red_sand",
    "gravel": "gravel",
    "clay": "clay",
    "cobblestone": "cobblestone",
    "mossy_cobblestone": "mossy_cobblestone",
    "stone": "stone",
    "stone_granite": "granite",
    "stone_diorite": "diorite",
    "stone_andesite": "andesite",
    "sandstone_top": "sandstone_top",
    "sandstone_normal": "sandstone_side",
    "sandstone_side": "sandstone_side",
    "sandstone_bottom": "sandstone_bottom",
    "sandstone_carried": "sandstone_top",
    "bedrock": "bedrock",
    "obsidian": "obsidian",
    "soul_sand": "soul_sand",
    "stonebrick": "stone_bricks",
    "stone_bricks": "stone_bricks",
    "stonebrick_mossy": "mossy_stone_bricks",
    "mossy_stone_bricks": "mossy_stone_bricks",
    "brick": "bricks",
    "bricks": "bricks",
    "glass": "glass",
    "glowstone": "glowstone",
    "quartz_block_top": "snow",
    "quartz_block_side": "snow",
    "snow": "snow",
    "ice": "ice",
    "packed_ice": "packed_ice",
    "water_still": "water",
    "water_flow": "water",
    "water": "water",
    "lava_still": "lava",
    "lava_flow": "lava",
    "lava": "lava",
    # ores and metal blocks
    "redstone_block": "redstone_block",
    "gold_block": "gold_block",
    "iron_block": "iron_block",
    "diamond_block": "diamond_block",
    # wood
    "bookshelf": "bookshelf",
    # plants and devices that keep their names
    "crafting_table_top": "crafting_top",
    "crafting_table_side": "crafting_side",
    "crafting_table_front": "crafting_side",
    "crafting_table": "crafting_top",
    "furnace_top": "furnace_top",
    "furnace_side": "furnace_side",
    "furnace_front_off": "furnace_front",
    "furnace_front": "furnace_front",
    "furnace_front_on": "furnace_front_lit",
    "chest_top": "chest_top",
    "chest_side": "chest_side",
    "chest_front": "chest_front",
    "dispenser_front_vertical": "dispenser_front",
    "dispenser_front_horizontal": "dispenser_front",
    "torch_on": "torch",
    "torch": "torch",
    "redstone_torch_on": "redstone_torch",
    "redstone_torch": "redstone_torch",
    "redstone_dust_cross": "redstone_dust",
    "redstone_dust_line": "redstone_dust",
    "redstone_dust": "redstone_dust",
    "lever": "lever",
    "pressure_plate_stone": "pressure_plate",
    "stone_pressure_plate": "pressure_plate",
    "noteblock": "note_block",
    "note_block": "note_block",
    "jukebox_side": "jukebox",
    "jukebox_top": "jukebox",
    "jukebox": "jukebox",
    "tnt_top": "tnt_top",
    "tnt_side": "tnt_side",
    "tnt_bottom": "tnt_bottom",
    "piston_top_normal": "piston_top",
    "piston_top_sticky": "sticky_piston_top",
    "piston_side": "piston_side",
    "piston_bottom": "piston_side",
    "piston_inner": "piston_arm",
    "piston_top": "piston_top",
    "ladder": "ladder",
    "rail_normal": "rail",
    "rail": "rail",
    "rail_normal_turned": "rail",
    "farmland_wet": "farmland",
    "farmland_dry": "farmland",
    "farmland": "farmland",
    "cactus_side": "cactus_side",
    "cactus_top": "cactus_top",
    "cactus_bottom": "cactus_bottom",
    "pumpkin_side": "pumpkin_side",
    "pumpkin_top": "pumpkin_top",
    "pumpkin_face_off": "jack_front",
    "pumpkin_face_on": "jack_front",
    "melon_side": "melon_side",
    "melon_top": "melon_top",
    "web": "web",
    "tallgrass": "tall_grass",
    "tall_grass": "tall_grass",
    "fern": "fern",
    "deadbush": "dead_bush",
    "dead_bush": "dead_bush",
    "reeds": "sugar_cane",
    "sugar_cane": "sugar_cane",
    "mushroom_red": "mushroom_red",
    "mushroom_brown": "mushroom_brown",
    "flower_dandelion": "flower_dandelion",
    "flower_rose": "flower_poppy",
    "flower_poppy": "flower_poppy",
    "flower_tulip_red": "flower_tulip_red",
    "flower_tulip_orange": "flower_tulip_orange",
    "flower_tulip_white": "flower_tulip_white",
    "flower_blue_orchid": "flower_blue_orchid",
    "flower_allium": "flower_allium",
    "wheat_stage_0": "wheat_0",
    "wheat_stage_1": "wheat_1",
    "wheat_stage_2": "wheat_2",
    "wheat_stage_3": "wheat_3",
    "carrots_stage_3": "carrots",
    "potatoes_stage_3": "potatoes",
    "hopper_top": "hopper_top",
    "hopper_outside": "hopper_side",
    "hopper_inside": "hopper_side",
    "hopper": "hopper_side",
}

#: Generated per-name families, so the built-in table stays small.
def _family_map() -> dict[str, str]:
    mapping: dict[str, str] = {}
    for wood in WOODS:
        mapping[f"log_{wood}"] = f"{wood}_log_side"
        mapping[f"log_{wood}_top"] = f"{wood}_log_top"
        mapping[f"planks_{wood}"] = f"{wood}_planks"
        mapping[f"{wood}_planks"] = f"{wood}_planks"
        mapping[f"leaves_{wood}"] = f"{wood}_leaves"
        mapping[f"{wood}_leaves"] = f"{wood}_leaves"
        mapping[f"sapling_{wood}"] = f"{wood}_sapling"
        mapping[f"{wood}_sapling"] = f"{wood}_sapling"
    for color in WOOL_COLORS:
        # The game's tiles are "wool_<colour>"; Bedrock says "wool_colored_<colour>".
        mapping[f"wool_colored_{color}"] = f"wool_{color}"
        mapping[f"{color}_wool"] = f"wool_{color}"
        mapping[f"wool_{color}"] = f"wool_{color}"
    for ore in ORES:
        mapping[f"{ore}_ore"] = f"{ore}_ore"
    mapping["lapis_ore"] = "lapis_ore"
    return mapping


NAME_MAP.update(_family_map())

#: Fallbacks tried when a file name is not mapped directly.
SUFFIX_STRIPS = ("_carried", "_still", "_flow", "_on", "_off", "_normal")


def game_tiles() -> list[str]:
    """Every tile name the game's atlas is expected to contain."""
    if not os.path.exists(ATLAS_MANIFEST):
        raise SystemExit("assets/generated/atlas.json is missing - run gen_assets.py first")
    with open(ATLAS_MANIFEST, encoding="utf-8") as handle:
        manifest = json.load(handle)
    return sorted(manifest.get("tiles", {}))


def candidate_names(stem: str) -> list[str]:
    """Names to try for one source file, most specific first."""
    base: str = stem.lower().replace("-", "_").replace(" ", "_")
    candidates: list[str] = [base]
    for strip in SUFFIX_STRIPS:
        if base.endswith(strip):
            candidates.append(base[: -len(strip)])
    if base.startswith("block_"):
        candidates.append(base[len("block_"):])
    if base.startswith("texture_"):
        candidates.append(base[len("texture_"):])
    # Bedrock keeps animated/mipmap variants next to the base name.
    for suffix in ("_mipmap", "_animated"):
        if base.endswith(suffix):
            candidates.append(base[: -len(suffix)])
    return candidates


def build_index(pack_dirs: list[str], extra_map: dict[str, str]) -> dict[str, str]:
    """Maps tile name -> source png path by scanning the pack directories."""
    by_stem: dict[str, str] = {}
    for pack_dir in pack_dirs:
        for folder, _subdirs, files in os.walk(pack_dir):
            for filename in sorted(files):
                if not filename.lower().endswith(".png"):
                    continue
                path = os.path.join(folder, filename)
                stem = os.path.splitext(filename)[0].lower()
                # Prefer the shortest path when a pack ships several variants.
                existing = by_stem.get(stem)
                if existing is None or len(path) < len(existing):
                    by_stem[stem] = path
    resolved: dict[str, str] = {}
    for tile in game_tiles():
        # Pass 1: explicit map (both directions of spelling are accepted).
        for source, target in extra_map.items():
            if target == tile and source.lower() in by_stem:
                resolved[tile] = by_stem[source.lower()]
                break
        if tile in resolved:
            continue
        # Pass 2: built-in table.
        for stem, path in by_stem.items():
            if NAME_MAP.get(stem) == tile or stem == tile:
                resolved[tile] = path
                break
        if tile in resolved:
            continue
        # Pass 3: normalisation.
        for stem, path in by_stem.items():
            for candidate in candidate_names(stem):
                if NAME_MAP.get(candidate) == tile or candidate == tile:
                    resolved[tile] = path
                    break
            if tile in resolved:
                break
    return resolved


def read_tile(path: str, tile_pixels: int) -> tuple[int, int, bytes]:
    width, height, pixels = pngread.read_png(path)
    if width != height:
        print(f"  ! {os.path.basename(path)}: {width}x{height} is not square, "
              f"using square crop", file=sys.stderr)
        size = min(width, height)
        cropped = bytearray(size * size * 4)
        for y in range(size):
            row = (y * width) * 4
            cropped[y * size * 4:(y + 1) * size * 4] = pixels[row:row + size * 4]
        width = height = size
        pixels = bytes(cropped)
    return width, height, pngread.resize_rgba(width, height, pixels, tile_pixels)


def to_canvas(tile_pixels: int, pixels: bytes) -> Canvas:
    canvas = Canvas(tile_pixels)
    for y in range(tile_pixels):
        for x in range(tile_pixels):
            index = (y * tile_pixels + x) * 4
            canvas.set(x, y, (pixels[index], pixels[index + 1], pixels[index + 2],
                              pixels[index + 3]))
    return canvas


def import_pack(pack_dirs: list[str], tile_pixels: int, extra_map: dict[str, str],
                report_only: bool) -> int:
    tiles = game_tiles()
    index = build_index(pack_dirs, extra_map)
    missing = [tile for tile in tiles if tile not in index]
    print(f"pack import: {len(index)}/{len(tiles)} tiles matched at {tile_pixels}px")
    if report_only:
        for tile in tiles:
            source = index.get(tile, "")
            print(f"  {tile:26s} {os.path.basename(source) if source else '(generated)'}")
        return 0

    os.makedirs(PACK_TILES, exist_ok=True)
    for stale in os.listdir(PACK_TILES):
        if stale.endswith(".png"):
            os.remove(os.path.join(PACK_TILES, stale))

    imported: dict[str, dict] = {}
    for tile, source in sorted(index.items()):
        _width, _height, pixels = read_tile(source, tile_pixels)
        to_canvas(tile_pixels, pixels).save(os.path.join(PACK_TILES, f"{tile}.png"))
        imported[tile] = {"source": os.path.relpath(source, ROOT), "path": f"tiles/{tile}.png"}

    manifest = {
        "tile_pixels": tile_pixels,
        "source": [os.path.basename(os.path.abspath(pack_dir)) for pack_dir in pack_dirs],
        "imported": imported,
        "missing": missing,
    }
    with open(PACK_MANIFEST, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=1, sort_keys=True)

    print(f"wrote {len(imported)} tiles to assets/pack/tiles/")
    if missing:
        print(f"{len(missing)} tiles keep the generated art: {', '.join(missing)}")
    print("now run: python3 tools/gen_assets.py textures")
    return 0


def clear_pack() -> int:
    for path in (PACK_MANIFEST,):
        if os.path.exists(path):
            os.remove(path)
    if os.path.isdir(PACK_TILES):
        for name in os.listdir(PACK_TILES):
            if name.endswith(".png"):
                os.remove(os.path.join(PACK_TILES, name))
    print("pack import cleared; generated art is in use again")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Import a texture pack into the game's atlas")
    parser.add_argument("--pack", action="append", default=[], metavar="DIR",
                        help="folder to scan for PNGs (repeatable)")
    parser.add_argument("--tile", type=int, default=16, choices=(16, 32, 64, 128),
                        help="tile resolution to normalise to (default 16)")
    parser.add_argument("--map", default="", metavar="FILE",
                        help="JSON file of extra {'pack_file': 'tile_name'} entries")
    parser.add_argument("--list", action="store_true", help="report matches and exit")
    parser.add_argument("--clear", action="store_true", help="forget the imported pack")
    args = parser.parse_args(argv[1:])

    if args.clear:
        return clear_pack()
    if not args.pack:
        parser.error("--pack DIR is required (or use --clear)")

    extra_map: dict[str, str] = {}
    if args.map:
        with open(args.map, encoding="utf-8") as handle:
            extra_map = json.load(handle)
    return import_pack(args.pack, args.tile, extra_map, args.list)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

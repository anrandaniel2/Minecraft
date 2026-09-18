"""Asset build script: generates all textures, atlases, mob skins and sounds.

    python3 tools/gen_assets.py            # everything
    python3 tools/gen_assets.py textures   # blocks/items/ui/entities/atlas
    python3 tools/gen_assets.py sounds     # audio only
    python3 tools/gen_assets.py atlas      # re-pack the terrain atlas only
    python3 tools/gen_assets.py textures --tile 32   # HD atlas from the same art
    python3 tools/gen_assets.py textures --no-pack   # ignore assets/pack/

Texture pack support: if `assets/pack/pack.json` exists (written by
`tools/pack_import.py`), those tiles replace the generated ones and the whole
atlas is rebuilt at the pack's resolution. `--tile N` upscales the generated art
to N pixels per tile instead.

Outputs (all committed, all reproducible):
    assets/generated/blocks/<name>.png     individual block faces (also used as
                                           inventory icons for block items)
    assets/generated/atlas.png             terrain atlas used by the chunk mesher
    assets/generated/atlas.json            tile name -> grid cell lookup
    assets/generated/items/<name>.png      item icons
    assets/generated/ui/<name>.png         HUD icons
    assets/generated/entities/<mob>.png    mob skin sheets
    assets/generated/entities.json         skin tile rectangles per mob
    assets/audio/<name>.wav                synthesised sound effects
"""

from __future__ import annotations

import json
import os
import zlib
import sys

import gen_items
import gen_textures as gt
import gen_sounds
import pngread
from pixelart import Canvas, rgba

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets")
PACK_DIR = os.path.join(OUT, "pack")
PACK_MANIFEST = os.path.join(PACK_DIR, "pack.json")

#: Tile resolutions the pipeline understands; each is a power-of-two multiple of
#: the 16px source art so upscaling stays crisp.
VALID_TILE_SIZES = (16, 32, 64, 128)


def _stable_seed(text: str) -> int:
    """Deterministic seed for a string.

    Python salts `hash()` per process, which would make generated textures
    differ between builds; crc32 keeps the pipeline reproducible.
    """
    return zlib.crc32(text.encode("utf-8"))


def ensure(path: str) -> str:
    os.makedirs(path, exist_ok=True)
    return path


# ---------------------------------------------------------------------------
# Block tiles
# ---------------------------------------------------------------------------


def pack_manifest() -> dict:
    """The imported pack's manifest, or {} when no pack is installed."""
    if not os.path.exists(PACK_MANIFEST):
        return {}
    try:
        with open(PACK_MANIFEST, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        print("assets/pack/pack.json is unreadable; ignoring the pack", file=sys.stderr)
        return {}


def pack_tiles(tile_pixels: int) -> dict[str, Canvas]:
    """Loads imported pack tiles at `tile_pixels`, keyed by tile name."""
    manifest = pack_manifest()
    if not manifest:
        return {}
    tiles: dict[str, Canvas] = {}
    for name in manifest.get("imported", {}):
        path = os.path.join(PACK_DIR, "tiles", f"{name}.png")
        if not os.path.exists(path):
            continue
        width, height, pixels = pngread.read_png(path)
        if width != tile_pixels:
            pixels = pngread.resize_rgba(width, height, pixels, tile_pixels)
            width = height = tile_pixels
        canvas = Canvas(tile_pixels)
        for y in range(height):
            for x in range(width):
                index = (y * width + x) * 4
                canvas.set(x, y, (pixels[index], pixels[index + 1], pixels[index + 2],
                                  pixels[index + 3]))
        tiles[name] = canvas
    return tiles


def scale_tiles(tiles: dict[str, Canvas], tile_pixels: int) -> dict[str, Canvas]:
    """Nearest-neighbour upscale of the 16px source art to `tile_pixels`."""
    factor: int = tile_pixels // gt.TILE
    if factor <= 1:
        return tiles
    return {name: canvas.scale(factor) for name, canvas in tiles.items()}


def resolve_tiles(requested_tile, use_pack: bool):
    """Builds the tile set: generated art, overridden by an imported pack.

    Returns `(tiles, tile_pixels, source)` where source is "pack" or "generated".
    """
    generated: dict[str, Canvas] = build_block_tiles()
    manifest: dict = pack_manifest() if use_pack else {}
    if manifest:
        tile_pixels: int = int(manifest.get("tile_pixels", gt.TILE))
        imported: dict[str, Canvas] = pack_tiles(tile_pixels)
        if imported:
            merged = dict(generated)
            if tile_pixels != gt.TILE:
                merged = scale_tiles(merged, tile_pixels)
            merged.update(imported)
            print(f"pack: {len(imported)} imported tiles at {tile_pixels}px "
                  f"(from {', '.join(manifest.get('source', ['?']))})")
            return merged, tile_pixels, "pack"
        print("pack manifest found but no tiles loaded; using generated art")
    tile_pixels = requested_tile or gt.TILE
    if tile_pixels not in VALID_TILE_SIZES:
        raise SystemExit(f"--tile must be one of {VALID_TILE_SIZES}")
    return scale_tiles(generated, tile_pixels), tile_pixels, "generated"


def build_block_tiles() -> dict[str, Canvas]:
    tiles: dict[str, Canvas] = {}

    def add(name: str, canvas: Canvas) -> None:
        tiles[name] = canvas

    # --- natural terrain ---
    add("grass_top", gt.tex_grass_top())
    add("grass_side", gt.tex_grass_side())
    add("grass_side_snowy", gt.tex_grass_side(70, grass_color="#f2fafa"))
    add("dirt", gt.tex_dirt())
    add("coarse_dirt", gt.tex_dirt(71, "#6b4a30"))
    add("stone", gt.tex_stone())
    add("cobblestone", gt.tex_cobblestone())
    add("mossy_cobblestone", gt.tex_mossy())
    add("gravel", gt.tex_gravel())
    add("sand", gt.tex_sand())
    add("red_sand", gt.tex_sand(72, "#c07a3a"))
    add("sandstone_top", gt.tex_sandstone_top())
    add("sandstone_side", gt.tex_sandstone_side())
    add("clay", gt.tex_workstation("clay"))
    add("snow", gt.tex_snow())
    add("ice", gt.tex_ice())
    add("packed_ice", gt.tex_ice(73))
    add("water", gt.tex_water())
    add("lava", gt.tex_lava())
    add("bedrock", gt.tex_bedrock())
    add("obsidian", gt.tex_obsidian())
    add("soul_sand", gt.tex_dirt(74, "#5a4230"))
    add("sandstone_bottom", gt.tex_sandstone_side(75))

    # --- wood ---
    for wood in ("oak", "birch", "spruce", "jungle"):
        add(f"{wood}_log_side", gt.tex_log_side(wood))
        add(f"{wood}_log_top", gt.tex_log_top(wood))
        add(f"{wood}_planks", gt.tex_planks(wood))
        add(f"{wood}_leaves", gt.tex_leaves(wood, 0.16 if wood != "spruce" else 0.22))

    # --- ores ---
    for ore in gt.ORE_COLORS:
        add(f"{ore}_ore", gt.tex_ore(ore))

    # --- crafted blocks ---
    add("stone_bricks", gt.tex_stone_bricks())
    add("mossy_stone_bricks", gt.tex_workstation("mossy_stone_bricks", 76))
    add("bricks", gt.tex_bricks())
    add("glass", gt.tex_glass())
    add("glowstone", gt.tex_glowstone())
    add("bookshelf", gt.tex_workstation("bookshelf"))
    for name in (
        "crafting_top", "crafting_side", "furnace_top", "furnace_side", "furnace_front",
        "furnace_front_lit", "chest_top", "chest_side", "chest_front", "tnt_top", "tnt_side",
        "pumpkin_side", "jack_front", "melon_side", "melon_top", "cactus_side", "cactus_top",
        "farmland", "redstone_block", "note_block", "jukebox", "piston_side", "piston_top",
        "piston_arm",
        "sticky_piston_top", "dispenser_front", "lever", "pressure_plate",
    ):
        add(name, gt.tex_workstation(name))
    add("tnt_bottom", gt.tex_workstation("tnt_top"))
    add("pumpkin_top", gt.tex_workstation("pumpkin_top"))
    add("cactus_bottom", gt.tex_workstation("cactus_top"))
    add("birch_log_side_snowy", gt.tex_log_side("birch"))

    # --- wool ---
    for color, hexcode in gt.WOOL_COLORS.items():
        wool = gt.noise_canvas(_stable_seed(color) % 5000, hexcode, contrast=0.14, scale=2.0)
        for y in range(gt.TILE):  # fabric weave
            for x in range(gt.TILE):
                if (x + y) % 4 == 0:
                    wool.set(x, y, gt.shade(hexcode, 0.92))
        add(f"wool_{color}", wool)

    # --- crossed / cutout plants and devices ---
    for wood in ("oak", "birch", "spruce", "jungle"):
        add(f"{wood}_sapling", gt.tex_cross("sapling_%s" % wood))
    for name in (
        "torch", "redstone_torch", "redstone_dust", "tall_grass", "fern", "dead_bush",
        "sugar_cane", "wheat_0", "wheat_1", "wheat_2", "wheat_3", "carrots", "potatoes",
        "mushroom_red", "mushroom_brown", "web", "flower_dandelion", "flower_poppy",
        "flower_tulip_red", "flower_tulip_orange", "flower_tulip_white", "flower_blue_orchid",
        "flower_allium",
    ):
        add(name, gt.tex_cross(name))
    add("ladder", gt.tex_workstation("ladder"))
    add("bed_top", gt.tex_bed("top"))
    add("bed_side", gt.tex_bed("side"))
    add("rail", gt.tex_rail())
    add("hopper_top", gt.tex_hopper("top"))
    add("hopper_side", gt.tex_hopper("side"))
    add("sign_side", gt.tex_sign("side"))
    add("sign_top", gt.tex_sign("top"))
    add("gold_block", gt.tex_gold_block())
    return tiles


ATLAS_COLS = 16


def build_atlas(tiles: dict[str, Canvas], tile_pixels: int = gt.TILE,
                source: str = "generated") -> tuple[Canvas, dict]:
    """Pack tiles in a padded grid so mipmapped sampling never bleeds.

    The padding scales with the tile so HD packs keep the same mipmap guard the
    16px art uses (a quarter of a tile, at least one pixel).
    """
    pad: int = max(1, tile_pixels // 4)
    cell = tile_pixels + pad * 2
    rows = (len(tiles) + ATLAS_COLS - 1) // ATLAS_COLS
    # The canvas is square, so a 16x16 grid of cells holds up to 256 tiles.
    side = ATLAS_COLS
    assert rows <= side, "atlas grid overflow"
    atlas = Canvas(cell * side)
    manifest = {"tile_pixels": tile_pixels, "pad": pad, "cell": cell, "cols": side,
                "rows": rows, "size": cell * side, "source": source, "tiles": {}}
    for index, (name, tile) in enumerate(tiles.items()):
        col = index % side
        row = index // side
        x0 = col * cell + pad
        y0 = row * cell + pad
        for y in range(tile_pixels):
            for x in range(tile_pixels):
                atlas.set(x0 + x, y0 + y, tile.get(x, y))
        # replicate edge pixels into the padding (mipmap bleed guard)
        for i in range(pad):
            for j in range(tile_pixels):
                atlas.set(x0 - 1 - i, y0 + j, tile.get(0, j))
                atlas.set(x0 + tile_pixels + i, y0 + j, tile.get(tile_pixels - 1, j))
                atlas.set(x0 + j, y0 - 1 - i, tile.get(j, 0))
                atlas.set(x0 + j, y0 + tile_pixels + i, tile.get(j, tile_pixels - 1))
        for i in range(pad):
            for j in range(pad):
                atlas.set(x0 - 1 - j, y0 - 1 - i, tile.get(0, 0))
                atlas.set(x0 + tile_pixels + j, y0 - 1 - i, tile.get(tile_pixels - 1, 0))
                atlas.set(x0 - 1 - j, y0 + tile_pixels + i, tile.get(0, tile_pixels - 1))
                atlas.set(x0 + tile_pixels + j, y0 + tile_pixels + i,
                          tile.get(tile_pixels - 1, tile_pixels - 1))
        manifest["tiles"][name] = [col, row]
    return atlas, manifest


# ---------------------------------------------------------------------------
# Items
# ---------------------------------------------------------------------------


def build_items() -> dict[str, Canvas]:
    items = {
        "stick": gen_items.stick_item(),
        "coal": gen_items.round_item("#2b2b2b", 4.2),
        "charcoal": gen_items.round_item("#3a3a36", 4.2),
        "iron_ingot": gen_items.ingot("#e0e0e6", "#a8a8b2"),
        "gold_ingot": gen_items.ingot("#f8d84a", "#c9a227"),
        "copper_ingot": gen_items.ingot("#e07f4a", "#a85a2a"),
        "diamond": gen_items.gem("#4aedd9"),
        "emerald": gen_items.gem("#17dd62"),
        "lapis_lazuli": gen_items.gem("#2f4bb0"),
        "redstone": gen_items.dust_item("#d82b1f"),
        "glowstone_dust": gen_items.dust_item("#f0c14b"),
        "gunpowder": gen_items.dust_item("#8f8f8f"),
        "string": gen_items.string_item(),
        "feather": gen_items.feather_item(),
        "leather": gen_items.leather_item(),
        "bone": gen_items.bone_item(),
        "flint": gen_items.round_item("#6f6a66", 4.0),
        "clay_ball": gen_items.round_item("#a3a8b8", 4.0),
        "brick": gen_items.ingot("#a4644a", "#7a4432"),
        "paper": gen_items.paper_item(),
        "book": gen_items.book_item(),
        "wheat": gen_items.wheat_item(),
        "wheat_seeds": gen_items.seeds_item("#7fbf4a"),
        "sugar": gen_items.dust_item("#f2f0e8"),
        "egg": gen_items.egg_item(),
        "slimeball": gen_items.slimeball(),
        "snowball": gen_items.snowball(),
        "arrow": gen_items.arrow_item(),
        "bucket": gen_items.bucket_item(),
        "water_bucket": gen_items.bucket_item("#2f5fd0"),
        "lava_bucket": gen_items.bucket_item("#d8480f"),
        "flint_and_steel": gen_items.flint_and_steel(),
        "bow": gen_items.bow_item(),
        "shears": gen_items.shears_item(),
        "apple": gen_items.apple_item(False),
        "golden_apple": gen_items.apple_item(True),
        "bread": gen_items.bread_item(),
        "carrot": gen_items.vegetable_item("carrot"),
        "potato": gen_items.vegetable_item("potato"),
        "baked_potato": gen_items.vegetable_item("baked_potato"),
        "cookie": gen_items.vegetable_item("cookie"),
        "melon_slice": gen_items.vegetable_item("melon_slice"),
        "pumpkin_pie": gen_items.vegetable_item("pumpkin_pie"),
        "mushroom_stew": gen_items.vegetable_item("stew"),
        "rotten_flesh": gen_items.vegetable_item("rotten_flesh"),
        "porkchop": gen_items.meat_item(False, "porkchop"),
        "cooked_porkchop": gen_items.meat_item(True, "porkchop"),
        "beef": gen_items.meat_item(False, "beef"),
        "steak": gen_items.meat_item(True, "beef"),
        "chicken": gen_items.meat_item(False, "chicken"),
        "cooked_chicken": gen_items.meat_item(True, "chicken"),
        "mutton": gen_items.meat_item(False, "mutton"),
        "cooked_mutton": gen_items.meat_item(True, "mutton"),
        "bone_meal": gen_items.dust_item("#e8e4d8"),
        "string_twine": gen_items.string_item(),
    }
    for material in gen_items.TOOL_MATERIALS:
        for kind in gen_items.TOOL_KINDS:
            items[f"{material}_{kind}"] = gen_items.tool_item(kind, material)
    for material in ("leather", "iron", "gold", "diamond"):
        for kind in ("helmet", "chestplate", "leggings", "boots"):
            items[f"{material}_{kind}"] = gen_items.armor_item(kind, material)
    return items


def build_ui() -> dict[str, Canvas]:
    ui = {
        "crosshair": gen_items.crosshair(),
        "heart_full": gen_items.heart("full"),
        "heart_half": gen_items.heart("half"),
        "heart_empty": gen_items.heart("empty"),
        "hunger_full": gen_items.hunger_icon("full"),
        "hunger_half": gen_items.hunger_icon("half"),
        "hunger_empty": gen_items.hunger_icon("empty"),
        "bubble": gen_items.bubble_icon("full"),
        "hotbar_slot": gen_items.hotbar_slot(False),
        "hotbar_slot_selected": gen_items.hotbar_slot(True),
        "cloud": gen_items.cloud_texture(),
        "logo": gen_items.logo_texture(),
        "sun": gen_items.sun_texture(),
        "moon": gen_items.moon_texture(),
    }
    for stage in range(10):
        ui[f"break_{stage}"] = gen_items.break_stage(stage)
    # Launcher icons for the Android export (icon_192 + adaptive 432 pair).
    ui["icon_64"] = gen_items.launcher_logo(64)
    ui["icon_192"] = gen_items.launcher_logo(192)
    ui["icon_432_foreground"] = gen_items.launcher_logo(432, inset=64)
    ui["icon_432_background"] = gen_items.launcher_background(432)
    return ui


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def write_all(canvases: dict[str, Canvas], directory: str) -> None:
    ensure(directory)
    for name, canvas in canvases.items():
        canvas.save(os.path.join(directory, f"{name}.png"))


def do_textures(requested_tile=None, use_pack: bool = True) -> None:
    tiles, tile_pixels, source = resolve_tiles(requested_tile, use_pack)
    write_all(tiles, os.path.join(OUT, "generated", "blocks"))
    atlas, manifest = build_atlas(tiles, tile_pixels, source)
    atlas.save(os.path.join(OUT, "generated", "atlas.png"))
    with open(os.path.join(OUT, "generated", "atlas.json"), "w") as handle:
        json.dump(manifest, handle, indent=1, sort_keys=True)
    print(f"atlas: {len(tiles)} tiles, {manifest['size']}x{manifest['size']}px "
          f"({tile_pixels}px tiles, {source})")

    write_all(build_items(), os.path.join(OUT, "generated", "items"))
    write_all(build_ui(), os.path.join(OUT, "generated", "ui"))

    entity_dir = ensure(os.path.join(OUT, "generated", "entities"))
    skins = gen_items.skin_skin_library()
    entity_manifest = {}
    for mob, canvas in skins.items():
        canvas.save(os.path.join(entity_dir, f"{mob}.png"))
        entity_manifest[mob] = {
            key: [col * gt.TILE, row * gt.TILE, gt.TILE, gt.TILE]
            for key, (col, row) in gen_items.SKIN_TILES.items()
        }
    with open(os.path.join(OUT, "generated", "entities.json"), "w") as handle:
        json.dump(entity_manifest, handle, indent=1, sort_keys=True)
    print(f"entities: {len(skins)} mob skins")


def do_atlas(requested_tile=None, use_pack: bool = True) -> None:
    tiles, tile_pixels, source = resolve_tiles(requested_tile, use_pack)
    atlas, manifest = build_atlas(tiles, tile_pixels, source)
    atlas.save(os.path.join(OUT, "generated", "atlas.png"))
    with open(os.path.join(OUT, "generated", "atlas.json"), "w") as handle:
        json.dump(manifest, handle, indent=1, sort_keys=True)
    print(f"atlas: {len(tiles)} tiles, {manifest['size']}x{manifest['size']}px "
          f"({tile_pixels}px tiles, {source})")


def do_sounds() -> None:
    audio_dir = ensure(os.path.join(OUT, "audio"))
    for name, factory in gen_sounds.SOUNDS.items():
        sound = factory()
        sound.save(os.path.join(audio_dir, f"{name}.wav"))
    for name, factory in gen_sounds.MUSIC.items():
        sound = factory()
        sound.save(os.path.join(audio_dir, f"{name}.wav"), volume=0.75)
    print(f"audio: {len(gen_sounds.SOUNDS)} effects, {len(gen_sounds.MUSIC)} music loops")


def main(argv: list[str]) -> int:
    arguments = argv[1:]
    requested_tile = None
    use_pack: bool = True
    targets: list[str] = []
    index: int = 0
    while index < len(arguments):
        argument = arguments[index]
        if argument == "--tile" and index + 1 < len(arguments):
            requested_tile = int(arguments[index + 1])
            index += 2
            continue
        if argument == "--no-pack":
            use_pack = False
            index += 1
            continue
        targets.append(argument)
        index += 1

    targets = targets or ["textures", "sounds"]
    if "all" in targets:
        targets = ["textures", "sounds"]
    for target in targets:
        if target == "textures":
            do_textures(requested_tile, use_pack)
        elif target == "atlas":
            do_atlas(requested_tile, use_pack)
        elif target == "sounds":
            do_sounds()
        else:
            print(f"unknown target: {target}", file=sys.stderr)
            return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

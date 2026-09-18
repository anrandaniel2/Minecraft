# Using Minecraft texture packs

Blockcraft ships with its own generated pixel art (see `tools/gen_textures.py`),
but you can drop a real **Minecraft Bedrock** (or Java) texture pack on top of it
and play with the familiar art. Bedrock's textures are Mojang's copyrighted
assets, so they are not in this repository and the build never downloads them —
you import the copy you already own, locally, and only the resulting PNGs on
your own disk are used. The importer keeps third-party art out of git:
`assets/pack/` is ignored, and CI rebuilds the committed atlas only from the
generated art.

## Quick start

1. Get the pack's block textures onto your machine. Either
   * unpack a `.mcpack` / `.zip` resource pack, or
   * copy `textures/blocks/` out of an installed Bedrock client, or
   * point at a Java pack's `assets/minecraft/textures/block/` folder.
2. Import and rebuild the atlas, then run the game:

   ```bash
   # 32-pixel tiles straight out of a pack folder
   python3 tools/pack_import.py --pack ~/packs/MyPack --tile 32

   cd tools && python3 gen_assets.py all      # regenerates atlas.png at 32px
   ```

   `gen_assets.py` notices `assets/pack/pack.json` and packs those tiles instead
   of the generated ones, at the resolution the import used:

   ```
   pack: 121 imported tiles at 32px (from MyPack)
   atlas: 137 tiles, 768x768px (32px tiles, pack)
   ```

3. Start the project (or rebuild the APK) as usual. The chunk mesher reads the
   atlas manifest, so nothing else has to change.

To go back to the built-in art:

```bash
python3 tools/pack_import.py --clear
cd tools && python3 gen_assets.py all
```

## Commands

```
python3 tools/pack_import.py --pack DIR [--pack DIR ...] [--tile 16|32|64|128]
                             [--map FILE] [--list] [--clear]
```

| Option | Meaning |
| --- | --- |
| `--pack DIR` | Folder to scan for PNGs. Repeat it to search several packs; the first match wins. |
| `--tile N` | Resolution to normalise every tile to: `16`, `32`, `64` or `128`. Bedrock's default block textures are 16px, most HD packs are 32–128. |
| `--map FILE` | JSON object of extra `{"pack_file": "tile_name"}` pairs, for names the built-in table does not know. |
| `--list` | Report which of the game's tiles matched and which are still missing, then exit without writing. |
| `--clear` | Delete `assets/pack/` so the generated art is used again. |

Use `--list` first — it prints a coverage line such as `118/137 tiles matched`
plus the names that fell back to generated art.

## How matching works

The importer maps *file names* onto the game's tile names in three passes:

1. **Explicit map** — anything in `--map`.
2. **Built-in table** — the well-known Bedrock/Java names, including the
   generated families: `log_spruce` → `spruce_log_side`, `planks_birch` →
   `birch_planks`, `wool_colored_red` → `wool_red`, `flower_rose` →
   `flower_poppy`, `wheat_stage_3` → `wheat_3`, `hopper_inside` → `hopper_side`
   and so on.
3. **Normalisation** — lowercased, dashes to underscores, plus the usual
   decorations stripped: `_carried`, `_still`, `_flow`, `_on`, `_off`,
   `_normal`, `_mipmap`, `_animated`, and a leading `block_`/`texture_`.

Anything still unmatched keeps the game's generated tile, so a partial pack
(only `stone.png` and `dirt.png`, say) works fine — it just mixes art styles.

A custom `--map` file looks like this:

```json
{
  "my_custom_stone": "stone",
  "pack_grass_top_hd": "grass_top"
}
```

## Limits

* Only **block tiles** are imported (the 137-tile terrain atlas, `assets/pack/tiles/*.png`).
  Item icons, mob skins, GUI and sounds keep using the generated assets.
* PNGs must be 8-bit and non-interlaced; palette, greyscale, RGB, RGBA and
  greyscale+alpha are all understood, 1/2/4-bit and interlaced files are
  rejected with a clear message. Re-export those with any image editor
  (or `convert in.png -depth 8 -interlace none out.png`).
* Non-square images are centre-cropped to a square instead of failing.
* Animated textures (`.mcmeta` strips) import as their first frame — the game's
  atlas is static.
* Resolution is baked into the built atlas: mixing a 16px pack with `--tile 32`
  upscales the smaller tiles, which is expected but slightly soft.

## What is committed

| Path | In git? | Notes |
| --- | --- | --- |
| `assets/generated/**` | yes | Reproducible art, built by `tools/gen_assets.py`. CI rebuilds it and fails if it drifts. |
| `assets/pack/**` | no | Your imported pack tiles and `pack.json`. Ignored by git. |
| `tools/pack_import.py`, `tools/pngread.py` | yes | The importer and its stdlib-only PNG reader. |

Never commit an imported pack: the CI asset check runs `gen_assets.py all`
without `assets/pack/`, so a committed HD atlas would show up as drift, and the
artwork itself belongs to Mojang and the pack's author.

## Troubleshooting

* **`assets/generated/atlas.json is missing`** — run `cd tools && python3 gen_assets.py all` first; the importer reads the tile list from it.
* **Everything fell back to generated art** — check `--list` output; the pack folder usually needs to be the one holding the PNGs (`textures/blocks`), not its parent.
* **The game looks unchanged** — the atlas must be rebuilt after importing (`gen_assets.py all` or at least `gen_assets.py atlas`), and the manifest's `tile_pixels` should match the `--tile` value you imported.

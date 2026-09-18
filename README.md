# Blockcraft

An open-world voxel sandbox built with **Godot 4.7** (GDScript, 3D Mobile renderer).
It started from the [Godotcraft](https://github.com/Godot-Templates/Godotcraft) template idea —
walk around, mine blocks, place blocks — and grew into a full game: survival,
crafting, smelting, mobs, villages, redstone-ish logic, weather, day/night,
saving and LAN/internet multiplayer, with an Android APK produced by CI.

Everything in the repository is generated or written from scratch: the textures
and sound effects are produced by the Python tools in `tools/`, the block/item
registries are data-driven, and every script is plain GDScript with no external
addons.

<p align="center">
  <em>121 block types, 353 items, 95 recipes, 11 biomes, 10 mob types, 39 sounds,
  villages, dungeons, mineshafts and ENet multiplayer.</em>
</p>

---

## Table of contents

- [Feature tour](#feature-tour)
- [Controls](#controls)
- [Chat commands](#chat-commands)
- [Multiplayer](#multiplayer)
- [Building and running](#building-and-running)
- [Android APK from CI](#android-apk-from-ci)
- [How the code is organised](#how-the-code-is-organised)
- [The asset pipeline](#the-asset-pipeline)
- [Testing and CI checks](#testing-and-ci-checks)
- [Credits and licence](#credits-and-licence)

---

## Feature tour

### World

- **Streaming voxel world** — 16 × 128 × 16 chunks generated and meshed on
  worker threads with a per-frame time budget, so walking never hitches. Chunks
  stream in around the player, unload behind them, and only nearby chunks get
  collision shapes.
- **11 biomes** — plains, forest, taiga, snowy tundra, mountains, desert,
  savanna, jungle, swamp, ocean, beach — each with its own surface blocks,
  trees, plants, mob spawns and sky tint.
- **Terrain features** — hills, cliffs, overhangs, ravines, two tunnel systems
  plus cheese caverns, lava lakes below y = 11, ore bands for coal, iron,
  copper, gold, redstone, lapis, diamond and emerald, oceans, rivers and caves
  that open to the surface.
- **Structures** — villages (plaza, lamps, ring of houses, farms), dungeons with
  chests, mineshafts with supports and rails, desert wells, huts and boulders,
  all deterministic from the world seed.
- **Day/night cycle** — 20-minute days with sunrise/sunset palettes, moving sun
  and moon, a star dome at night, drifting clouds, and lighting that changes
  what spawns.
- **Weather** — clear, rain and thunder, with percussive lightning flashes,
  delayed thunder, biome-aware snow, and a rain ambience loop.
- **Flowing fluids** — water and lava spread, sea level fills oceans, water
  meeting lava makes cobblestone, lava makes obsidian, and crops/soil respond to
  water nearby.
- **Smooth voxel lighting** — sky light floods from above, block light comes from
  torches, lava and glowstone, both propagate through a flood-fill engine and
  are baked into vertex colours with ambient occlusion.

### Survival

- **Health, hunger and saturation** — hunger drains with activity, eating
  restores it, and regenerating health costs food. Fall damage, drowning,
  suffocation in lava, starvation and mob attacks all hurt.
- **Tools with durability and mining tiers** — hand, wood, stone, iron and
  diamond tiers decide what actually drops (a stone pickaxe cannot harvest
  diamond ore), tools wear out and break with a sound, and mining speed depends
  on the tool matching the block.
- **Armour** — four slots, 16 pieces, damage reduction plus durability wear.
- **Experience** — orbs from mining and mob kills, levels, and a HUD bar.
- **Farming** — hoe dirt into farmland, plant wheat/carrots/potatoes, crops grow
  through bone meal or patience, and ripen into a harvest.
- **Food chain** — raw meat from animals, coal-fueled furnaces that turn ore
  into ingots and raw meat into cooked meat.
- **Death and respawn** — inventory drops (unless "keep inventory" is on) and the
  player respawns at the world spawn three seconds later.
- **Beds** — three wool over three planks. Right-click one at night to sleep
  through to dawn and move your respawn point to the bed; it refuses while
  monsters are within eight blocks, so night is not a free pass.

### Mobs

Ten mob types, all driven by one AI with per-type stats:

| Passive | Hostile | Notes |
| --- | --- | --- |
| pig, cow, sheep, chicken, cat, villager | zombie, skeleton, creeper, spider | Zombies and skeletons burn in daylight |

- Wander, graze, flee when hurt, breed when fed, follow tempting items, and
  jump one-block obstacles.
- Zombies chase and hit, skeletons keep their distance and shoot arrows,
  creepers swell and detonate (terrain damage is a setting), spiders climb
  walls.
- **Villagers** live in villages, wear a profession (farmer, librarian,
  blacksmith, butcher, cleric, cartographer) and **trade** with you from a
  proper trade screen; each profession has its own offers and emerald prices.
- Spawn caps per category, biome and light-level aware spawning, daylight
  despawn for monsters, and mobs are saved with the world.

### Building and sandbox

- **120 block types** — stone family, dirt/grass/sand/gravel/clay, ores and
  metal blocks, four wood types (logs, planks, leaves, saplings), 16 wool
  colours, glass and panes, bricks, sandstone, quartz, prismarine, nether-ish
  blocks, workstations (crafting table, furnace, chest, dispenser, lever,
  pressure plates, redstone torch, piston, sticky piston, TNT, note block,
  torches, ladders, slabs, snow layers, farmland, crops).
- **Creative mode** — instant mining, flight (F), infinite palette in the
  inventory, and the same world as survival.
- **World-edit friendly** — chat commands for `/tp`, `/time`, `/weather`,
  `/give`, `/gamemode`, `/fly`, `/clear` and `/seed`; the debug overlay reports
  chunk, triangle and entity counts.
- **Redstone-ish logic** — wire power propagation (0–15), levers, pressure
  plates, redstone torches, pistons and sticky pistons, dispensers that shoot
  arrows or place water, note blocks, and TNT that can be primed by flint and
  steel or a dispenser.
- **Decorative detail** — block-break particles for ten effect kinds, footstep
  sounds per material, view bobbing, and a held-item viewmodel.

### Interface

- Crosshair, hotbar, hearts, hunger, armour, breath and XP bar.
- **Inventory with a recipe book** — 2×2 crafting in the backpack, 3×3 at a
  crafting table, shift-click transfers, cursor-stack drag and drop, and a
  recipe list that auto-fills the grid from what you are carrying.
- **Chest, furnace and dispenser screens** with live smelting progress, fuel
  gauge and a human-readable status line.
- **Pause menu** with settings, save, host/join multiplayer and quit.
- **Settings** — render distance, FOV, UI scale, max FPS, V-Sync, fullscreen,
  smooth lighting, view bobbing, particles, clouds, difficulty, default
  gamemode, auto-jump, keep inventory, mob griefing, autosave interval, mouse
  sensitivity, invert Y, touch controls and three volume sliders. Everything
  saves to `user://settings.cfg`.
- **Debug overlay (F3)** and **player list (Tab)**, chat with history, toasts,
  damage vignette, underwater tint, screenshots (F2) and on-screen touch
  controls for phones.

### Multiplayer

- ENet host/client for up to 8 players over LAN or the internet.
- Deterministic terrain means only **edits, containers and player state** cross
  the wire: the host sends the seed, the clock, every block edit and every
  container to joining players.
- Remote players are box-model avatars with name tags, interpolated at 12 state
  packets per second, plus a Tab player list and in-game chat.

### Saves

- Slot-based saves under `user://saves/<slot>/` with world metadata, a binary
  chunk-edit file, containers and entities.
- Autosave (default every 3 minutes), manual save from the pause menu, world
  list with play/copy/delete, and a seed field that accepts numbers or words.

---

## Controls

| Action | Key |
| --- | --- |
| Move | W A S D |
| Jump / swim up | Space |
| Sneak / swim down | Shift |
| Sprint | Ctrl |
| Attack / mine | Left mouse |
| Use / place / eat / trade | Right mouse |
| Pick block | Middle mouse |
| Hotbar | 1–9 or scroll |
| Inventory | E |
| Drop item | Q |
| Chat / commands | Enter |
| Pause | Esc |
| Toggle debug overlay | F3 |
| Player list | Tab |
| Toggle HUD | F1 |
| Screenshot | F2 |
| Toggle flight (creative) | F |
| Third person | F5 |

Gamepad (jump, sneak, inventory, drop, pause, debug, sticks for movement and
look) and touch controls (virtual stick, look area, jump/mine/place buttons)
are set up too — `Settings.touch_controls` selects `auto`, `on` or `off`.

## Chat commands

```
/help                              list commands
/tp <x> <y> <z>                    teleport
/time day|night                    jump the clock
/gamemode creative|survival        switch mode
/give <item> [count]               spawn items
/weather clear|rain|thunder        change the weather
/spawn                             return to the world spawn
/seed                              print the world seed
/fly                               toggle flight in creative
/clear                             empty the inventory
/kill                              die (and respawn)
/setblock <x> <y> <z> <block>      place a single block anywhere
/fill <x1> <y1> <z1> <x2> <y2> <z2> <block>
                                   world-edit box fill (8192 blocks max)
/summon <mob> [count]              spawn mobs next to you
/killmobs                          remove hostile mobs in a 30 block radius
/xp <amount>                       add experience
/share                             print the address friends can join on
```

## Multiplayer

1. **Host** — Main menu → Multiplayer → *Host new world*, or load any world and
   host it from the pause menu. The address to share is printed there and can be
   copied to the clipboard.
2. **Join** — Main menu → Multiplayer, type the host address and port (default
   `27015`), *Join*.
3. On a LAN, use the host's local IP (`192.168.x.x`). Over the internet, forward
   UDP 27015 on the host router, or use a VPN such as Tailscale/ZeroTier.

---

## Building and running

### Requirements

- **Godot 4.7** (any 4.x from 4.4 up usually works; the project is pinned to 4.7
  features and the Mobile renderer).
- **Python 3.10+** only if you want to regenerate the art, sound or atlas.

```bash
git clone <your fork>
cd Minecraft

# Optional: rebuild textures, items, atlas, sounds and music
cd tools && python3 gen_assets.py all && cd ..

# Run the game
godot --path .
```

Godot editor: **Import** → select `project.godot` → **Run**. The main scene is
`scenes/main_menu.tscn`; the game itself is `scenes/game.tscn`, which builds the
world, player and HUD in code.

### Exporting a desktop build

```bash
godot --headless --path . --import
godot --headless --path . --export-release "Linux" build/blockcraft.x86_64
```

`export_presets.cfg` ships with an **Android** preset and a **Linux** preset.
Press **Install Export Templates** once in the editor (or let CI do it) before
exporting.

## Android APK from CI

`.github/workflows/android.yml` builds a signed-with-debug-keys `.apk` on every
push to `main`, every pull request and on demand (**Actions → Android APK → Run
workflow**, where you can also pass a version name).

What the job does:

1. Installs JDK 17 and the Android SDK (platform-tools, build-tools 34,
   Android 34) straight from Google's download servers.
2. Downloads Godot 4.7.2 and the matching export templates.
3. Generates a debug keystore and points Godot's editor settings at the SDK and
   keystore.
4. Imports the project headlessly — which also acts as a full GDScript parse
   check — then exports the debug APK, attempts a release APK, verifies the
   archive with `aapt2 dump badging` and uploads `build/*.apk` as the
   `blockcraft-android` artifact.

To install it: download the artifact from the workflow run, copy it to an
Android device and open it (allow "install unknown apps" for your file manager
or browser). The APK targets `arm64-v8a`, needs Android 6.0+ and enables the
`internet`, `access_network_state`, `access_wifi_state`, `vibrate` and
`wake_lock` permissions for multiplayer.

Change `package/unique_name` in `export_presets.cfg` (or pass a version through
the workflow input) if you fork this and want your own package id.

## How the code is organised

```
project.godot            Godot project: autoloads, Mobile renderer, input notes
export_presets.cfg       Android + Linux export presets
scenes/
  main_menu.tscn         Main menu (world list, multiplayer, settings)
  game.tscn              In-game root; builds world/player/HUD from code
scripts/
  core/                  settings, registries, recipes, saves, scene routing,
                         game root, main menu, input map
  world/                 chunk storage, generator, structures, mesher, lighting,
                         world root, block ticking, redstone, day/night, weather,
                         containers
  entities/              mob AI + stats, box models, item drops, XP orbs, arrows,
                         primed TNT, falling blocks, villager trades
  player/                first/third-person controller, survival, inventory,
                         mining, placing, combat
  ui/                    HUD, inventory + recipe book, container screens, trade
                         screen, pause menu, settings
  fx/                    particle effects
  net/                   ENet multiplayer manager, remote player avatars
shaders/                 terrain, water, clouds and stars shaders
tools/                   the Python asset pipeline
assets/generated/         block tiles, item icons, HUD art, mob skins, atlas
assets/audio/             39 sound effects + 4 music loops (22 kHz mono WAV)
```

Data flow at a glance:

- `Registry` (autoload) builds `Blocks`, `Items` and `Recipes` at startup and
  caches every texture and audio stream, so nothing calls `load()` at runtime.
- `World` streams chunks, owns block ticking, redstone, day/night, weather and
  mobs, and exposes the block/raycast/container API everything else uses.
- `Player` owns the camera, inventory, survival stats and interaction; it emits
  signals (`died`, `inventory_changed`, `open_container_screen`, …) that the HUD
  and game root listen to.
- `MpManager` (autoload) mirrors block edits, container contents and player
  states between peers through ENet RPCs, and degrades to no-ops when it is not
  in a session.

## The asset pipeline

`tools/` is a dependency-free Python voxel-art and audio generator (no PIL, no
numpy — it writes PNG and WAV bytes directly).

```bash
cd tools
python3 gen_assets.py textures   # blocks, item icons, HUD art, mob skins
python3 gen_assets.py atlas      # pack the block tiles into one atlas
python3 gen_assets.py sounds     # 39 effects + 4 music loops
python3 gen_assets.py all        # everything above
```

- `pixelart.py` — PNG writer, drawing canvas, and a small DSP kit
  (oscillators, noise, chords, sequences) for the sound effects and music.
- `gen_textures.py` — block tiles, plants, cross sprites, wool, ores.
- `gen_items.py` — tools, armour, food, ingots, HUD widgets, mob skin sheets.
- `gen_sounds.py` — dig/step/place sounds, mob voices, UI clicks, explosion,
  rain, and four seamless music loops (menu, day, night, cave).
- `gen_assets.py` — the driver; also packs `atlas.png` + `atlas.json` and
  `entities.json`.

The generated art is committed, so the game runs without ever touching Python.
Textures are 16 × 16 with a 4-pixel padding in a 384 × 384 atlas; music and
effects are 22 kHz mono WAVs for a small repository.

## Testing and CI checks

- `.github/workflows/checks.yml` — parses every `.gd` file with `gdparse`,
  re-runs the whole asset pipeline to prove it is byte-for-byte reproducible,
  imports the project headlessly, loads the main scene looking for script
  errors and runs `tests/smoke_test.gd` (239 checks over the registries, the
  atlas manifests, recipe matching, terrain generation, mob/trade tables, the
  light engine and container serialisation).
- `.github/workflows/android.yml` — the APK build described above.
- Locally, `godot --headless --path . --import` catches the same script errors,
  `godot --headless --path . --script res://tests/smoke_test.gd` runs the smoke
  test, and `godot --path .` is the fastest way to play-test a change.

## Credits and licence

- Inspired by the **Godotcraft** template by [Godot-Templates](https://github.com/Godot-Templates/Godotcraft)
  (MIT) — the streaming-chunk, box-model and cloud/star-shader ideas started
  there. This project is a ground-up rewrite in GDScript with its own
  registries, world generator, UI, mobs, redstone, saving and networking.
- Not affiliated with Mojang or Minecraft; it is an original voxel game that
  borrows the visual language of the genre.
- Released under the **MIT licence** — see [LICENSE](LICENSE).

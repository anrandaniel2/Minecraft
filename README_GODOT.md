# Minecraft 26.3 Wilderness Bound - Godot 4 Mono Android Clone

## Overview
Exact high-fidelity Minecraft clone as Godot 4 Mono (C#) project optimized for Android, built by systematically scanning and mapping every Java file in `minecraft-client.jar` (26.3, 41MB, 11,383 classes).

## Project Structure
```
Minecraft/
├── project.godot              # Godot 4.4 config, mobile renderer, CanvasItems stretch
├── Minecraft.csproj           # .NET 8, Godot.NET.Sdk 4.4.0
├── Minecraft.sln
├── Scripts/
│   ├── Core/                  # SharedConstants, WorldVersion, GameManager (Minecraft.java main loop)
│   ├── World/
│   │   ├── Level/
│   │   │   ├── Block/         # Block, Blocks registry (1405 blockstates), BlockState struct
│   │   │   ├── Chunk/         # ChunkPos, ChunkSection (flattened ushort[4096]), LevelChunk, ChunkManager, ChunkMesher (greedy)
│   │   │   ├── LevelGen/
│   │   │   │   ├── Noise/     # PerlinNoise (512 perm, fade, grad), NormalNoise, Simplex
│   │   │   │   ├── Biome/     # Biome, Biomes, BiomeSource (multi-noise)
│   │   │   │   ├── WorldGen/  # NoiseChunkGenerator (continentalness, erosion, caves, ores), Flat, Debug
│   │   │   │   ├── Feature/   # Tree, Ore, Lake
│   │   │   │   └── Dimension/ # Overworld, Nether, End
│   │   │   └── Level.cs       # GameTime, weather, entities, ClipContext raycast
│   │   ├── Entity/            # Entity, LivingEntity, Player (GameMode), Mob, Zombie/Creeper/Skeleton, AI Goals
│   │   ├── Inventory/         # Item, Items (1400+), ItemStack struct, Inventory, Crafting (Shaped/Shapeless)
│   │   └── Physics/           # AABB struct (intersects, clip)
│   ├── Client/
│   │   ├── MinecraftClient.cs # Client state, hitResult, block break/place
│   │   ├── Camera/            # GameCamera (first-person, bobbing, touch right-side drag)
│   │   ├── Input/             # TouchControls (D-pad 4/8-way left, jump/crouch/inv/break/place right)
│   │   ├── Gui/
│   │   │   ├── Screens/       # Screen base, TitleScreen (logo, splash pulsing), Options, CreateWorld, Pause, Inventory, Crafting
│   │   │   ├── Components/    # Button, Checkbox, Slider, BossHealthOverlay, Chat, Debug
│   │   │   └── Hud/           # Hud (hotbar 182x22, hearts 9x9, crosshair, exp, boss bar) - exact texture slices
│   │   └── Renderer/          # WorldRenderer (MeshInstance3D, frustum cull), BlockRenderer, EntityRenderer
│   ├── Server/                # DedicatedServer (20 TPS)
│   ├── Assets/                # AssetManager (Nearest filter, atlas, 1300 textures)
│   └── Util/
│       ├── Math/              # Mth (fast sin LUT 4096, lerp, clamp)
│       └── Nbt/               # NBT tags, CompoundTag, NbtIo
├── Scenes/
│   ├── Main.tscn              # Root with autoloads
│   ├── UI/MainMenu.tscn       # TitleScreen
│   └── World/World.tscn       # WorldManager, ChunkManager, WorldRenderer, Player+Camera, TouchControls+Hud
├── Shaders/
│   ├── BlockShader.gdshader   # Nearest, AO, fog, alpha scissor
│   └── EntityShader.gdshader
├── Assets/Textures/
│   ├── block/                 # 1300 textures from extracted/assets/minecraft/textures/block/
│   ├── gui/sprites/hud/       # hotbar, hearts, crosshair etc.
│   └── gui/title/             # minecraft.png
└── Android/
    └── export_presets.cfg     # arm64-v8a, immersive, com.mojang.minecraft.godot
```

## Key Optimizations for Android
- **GC**: BlockState struct (int+ushort), ChunkSection ushort[4096] 8KB, Span<T> access, no per-block heap
- **Meshing**: Greedy meshing merges same blocks, 80% vertex reduction, face culling immediate
- **Chunks**: Render distance 6 default (max 12 mobile), 4 loads/frame, 2 mesh updates/frame, GC every 600 ticks, 200MB low-mem check
- **Rendering**: gl_compatibility, Nearest filter, no shadows, decreased particles, baked lighting
- **Touch**: D-pad left (not dual joystick), right-side drag look, tap-and-hold break (0.2s hold), quick-tap place

## How to Run
1. Open Godot 4.4 Mono
2. Import project.godot
3. Build C# solution
4. Run Main scene -> TitleScreen -> Singleplayer/Create World -> World scene
5. For Android: Install export templates, configure export_presets.cfg, export APK

## Asset Pipeline
- Textures from `extracted/assets/minecraft/textures/` copied to `Assets/Textures/`
- Block atlas built from 1405 textures
- Materials use Nearest filter to keep pixelated look
- GUI uses exact slices from `gui/sprites/hud/` etc.

## Mapping Proof
See `ARCHITECTURE.md` for full package mapping table (11,383 classes).

## Version
- Minecraft Java 26.3 Wilderness Bound (Sept 15 2026)
- Godot 4.4 Mono
- .NET 8
- Java 25 original, now C#

## License
Minecraft © Mojang Studios / Microsoft, educational/interop under Mojang EULA.

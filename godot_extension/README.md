# GraalVM Java → Godot GDExtension

**Godot requirement:** This project uses Godot 4.7.2’s built-in `VirtualJoystick`, so it requires Godot 4.7.2 or newer.

This is a **Linux x86_64** GDExtension project which compiles the usable Java
surface in `decompiled_sample/net/minecraft/client/Minecraft.java` into a GraalVM
Native Image shared library and loads it from Godot.

It is intentionally split into two shared objects:

- `bin/libminecraft_java.so` is produced from Java by `native-image --shared`.
- `bin/libminecraft_godot.so` is the small C GDExtension adapter. It exports
  `godot_gdextension_init`, creates the Graal isolate, and exposes a
  `MinecraftTouch` Godot class.

This split is important: Java stays Godot-free, while the adapter handles the
Godot C ABI. `libminecraft_godot.so` uses an `$ORIGIN` rpath, so it finds the
Java library next to itself after export.

> The repository has only a decompiled **sample** of Minecraft. This builds the
> sample integration/input surface, not the full Mojang client. Compiling the
> complete client would require its full source graph, runtime dependencies,
> resources, and a replacement for its LWJGL rendering platform.

## Touch API

The Java class contains generic, synchronized methods:

- `touchDown(pointerId, x, y, viewportWidth, viewportHeight)`
- `touchMove(pointerId, x, y, viewportWidth, viewportHeight)`
- `touchUp(pointerId)`
- `resetTouchControls()`
- `setVirtualJoystickMask(actionMask)`
- `getTouchMask()` and `getActiveTouchCount()`
- `submitRenderProtocolSmokeFrame()` — validates the Java → C RenderPearl
  command transport; it does not invoke Godot APIs from Java.

The mask uses these bits: `FORWARD=1`, `BACKWARD=2`, `LEFT=4`, `RIGHT=8`,
`JUMP=16`, `SNEAK=32`, `ACTIVE=64`.

`MinecraftTouch` exposes the equivalent snake-case methods to Godot. The full-screen demo scene uses Godot 4.7's built-in `VirtualJoystick` for movement and `TouchScreenButton` nodes for independent multi-touch jump and sneak actions. Dragging any non-button region on the right half of the screen emits relative camera-look input. `TouchControls.gd` forwards generic action bits and look deltas to the Java bridge, so Java remains Godot-free.

## Godot viewport resource renderer

`MinecraftGodotRenderer.gd` renders inside Godot's fullscreen main viewport. It
uses `MinecraftResourcePack.gd` to read the complete 26.3 client resource pack:

- blockstate selection;
- block-model parent inheritance and texture variables;
- model elements, element rotation, face geometry, and UVs; and
- original Minecraft PNG block textures using nearest-neighbour sampling.

It accepts engine-neutral block snapshots in this form:

```gdscript
renderer.apply_block_snapshot([
    {"block": "minecraft:stone", "x": 0, "y": 64, "z": 0},
])
```

The bootstrap terrain is a deterministic renderer smoke test, but it is built
from real client block IDs/models/textures rather than colored demo cubes. It
is replaced when a Java chunk/world adapter submits an authoritative snapshot.
This is substantial Godot-side resource rendering, **not yet a completed port
of every Blaze3D subsystem**: chunk extraction from the complete client,
section mesh batching, fluids, entities, UI, post-processing, and an Android
arm64 Java bridge remain separate work.

### Stage the complete client assets

Godot exports only files beneath `godot_extension/`; the authoritative asset
source remains `extracted/assets/minecraft`. Stage it before running or
exporting the project:

```bash
python3 tools/stage_minecraft_assets.py
```

The generated `godot_extension/minecraft_assets/` directory is ignored because
it is a reproducible copy of the complete versioned client payload. Both CI
workflows stage it automatically, so the Android APK packages the full client
resource namespace needed by the Godot renderer.

## Build

Install a GraalVM JDK with Native Image and GCC, then run from the repository
root:

```bash
export GRAALVM_HOME=/path/to/graalvm-community-openjdk-21
./godot_extension/build.sh
```

The script compiles only the two intentional Java sources. It writes:

```text
godot_extension/bin/libminecraft_java.so
godot_extension/bin/libminecraft_godot.so
godot_extension/build/generated/minecraft_java.h
```

The generated header and intermediate build directory are not committed.

### RenderPearl native mailbox boundary

`minecraft_render_submit_frame()` validates and stores an owned copy of a
completed Java command frame. The Godot `RenderingDevice` executor will use
`minecraft_render_take_latest_frame()` to atomically detach the newest frame,
pass it through the typed `MinecraftRenderCommandSink` decoder, then call
`minecraft_render_release_frame()`. The decoder verifies every payload length
and exposes only native numeric values and byte ranges to its sink callbacks;
it has no Godot dependency itself. This gives the Java render thread and the
Godot render thread clear ownership boundaries: a later Java submission cannot
change the byte frame currently being executed.

## Run in Godot

1. Run `python3 tools/stage_minecraft_assets.py`.
2. Build the libraries above.
3. Import/open `godot_extension/project.godot` in **Godot 4.7.2 or newer**.
4. Run the project on a touch device (or enable **Emulate Touch From Mouse** in
   Project Settings → Input Devices → Pointing).
5. Drag the left virtual joystick to move, use the multi-touch jump/sneak
   targets, and drag the right side of the screen to look around. The status
   text shows the input mask returned by the Java bridge.

The `.gdextension` file resolves `libminecraft_godot.so`; do not move the
companion Java `.so` out of `bin/`.

## Platform notes

The checked-in descriptor targets Linux x86_64 because `.so` is the requested
format. Native Image outputs are platform-specific. Build each target on that
platform and add the matching `macos.*` or `windows.*` library entry to
`minecraft.gdextension` when you need those exports.

### Android APK workflow

`.github/workflows/build-android-apk.yml` exports a Godot **4.7.2 Android
arm64 debug APK** and uploads it as `minecraft-godot-android-arm64-debug`.
It includes the Godot 4.7 built-in VirtualJoystick, movement actions, and the
jump/sneak controls.

The current GraalVM libraries are Linux x86_64 only, so Android intentionally
uses `MobileInputFallback.gd`; it does not pretend to run the desktop Java
client. The full viewport-port milestone must provide a separately built
Android arm64 GDExtension before `MinecraftTouch` can be enabled on Android.

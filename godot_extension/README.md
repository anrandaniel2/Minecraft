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

The mask uses these bits: `FORWARD=1`, `BACKWARD=2`, `LEFT=4`, `RIGHT=8`,
`JUMP=16`, `SNEAK=32`, `ACTIVE=64`.

`MinecraftTouch` exposes the equivalent snake-case methods to Godot. The full-screen demo scene uses Godot 4.7's built-in `VirtualJoystick` for movement and `TouchScreenButton` nodes for independent multi-touch jump and sneak actions. Dragging any non-button region on the right half of the screen emits relative camera-look input. `TouchControls.gd` forwards generic action bits and look deltas to the Java bridge, so Java remains Godot-free.

## Viewport renderer milestone

`MinecraftGodotRenderer.gd` is a Godot-native viewport renderer baseline: it
creates the world environment, directional lighting, voxel geometry, and the
camera-look contract used by the touch overlay. It renders inside Godot's main
viewport and stretches to fullscreen. It is the initial rendering target for
the recovered Minecraft client draw-command port; it is not a claim that the
complete Blaze3D renderer has already been replaced.

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

## Run in Godot

1. Build the libraries above.
2. Import/open `godot_extension/project.godot` in **Godot 4.7.2 or newer**.
3. Run the project on a touch device (or enable **Emulate Touch From Mouse** in
   Project Settings → Input Devices → Pointing).
4. Drag the left virtual joystick to move, use the multi-touch jump/sneak
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

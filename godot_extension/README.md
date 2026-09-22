# GraalVM Java → Godot GDExtension

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
- `getTouchMask()` and `getActiveTouchCount()`

The mask uses these bits: `FORWARD=1`, `BACKWARD=2`, `LEFT=4`, `RIGHT=8`,
`JUMP=16`, `SNEAK=32`, `ACTIVE=64`.

`MinecraftTouch` exposes the equivalent snake-case methods to Godot. The demo
scene's `TouchControls.gd` receives screen touch/drag events and calls that
class. Touches on the left half act as a movement pad. The bottom-right button
is jump, and the lower-middle-right button is sneak.

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
2. Import/open `godot_extension/project.godot` in **Godot 4.1 or newer**.
3. Run the project on a touch device (or enable **Emulate Touch From Mouse** in
   Project Settings → Input Devices → Pointing).
4. Press/drag the visual controls. The status text shows the mask returned by
   Java through the GDExtension bridge.

The `.gdextension` file resolves `libminecraft_godot.so`; do not move the
companion Java `.so` out of `bin/`.

## Platform notes

The checked-in descriptor targets Linux x86_64 because `.so` is the requested
format. Native Image outputs are platform-specific. Build each target on that
platform and add the matching `macos.*` or `windows.*` library entry to
`minecraft.gdextension` when you need those exports.

# Full Minecraft Client → Godot Viewport Port

This directory defines the **real** port target: the complete class tree in
`../extracted/`, not `decompiled_sample/` and not the small Java Native Image
input demo.

## Why a renderer port is required

The full client owns a desktop Blaze3D/LWJGL/GLFW graphics context. Loading it
as a library cannot make that context become a Godot `Viewport`. A real
in-viewport port must replace the desktop platform layer:

1. **Source recovery** — decompile the complete Java 25 class tree in CI. The
   checked-in `extracted/` directory has class files and resources, but no Java
   source to patch.
2. **Dependency resolution** — resolve every library and platform native from
   Mojang's 26.3 version metadata. They are not bundled in `minecraft-client.jar`.
3. **Renderer adapter** — translate/reimplement Blaze3D rendering, framebuffers,
   shaders, textures, buffers, and frame lifecycle on Godot's renderer. This is
   the work that places game pixels in a Godot `Viewport`.
4. **Platform adapters** — route Godot input, audio, window state, filesystem,
   clipboard, networking, and lifecycle into the recovered client.
5. **Android** — compile a separate Android `arm64-v8a` GDExtension with the
   Android NDK and provide Android-safe replacements for desktop-only native
   libraries. The Linux x86_64 `.so` files in `godot_extension/bin/` cannot run
   on Android.

`tools/full_client_inventory.py` is the phase-0 guard: it verifies that the
actual input is the full Java 25 class distribution. The `Recover Full Minecraft
Client Source` workflow is phase 1: it uses Java 25 and Vineflower to produce a
source-only CI artifact, verifies it has at least 10,000 `.java` files, and
keeps that large recovered source out of Git. Run the inventory from repository
root:

```bash
python3 tools/full_client_inventory.py
```

## Current milestone

The accompanying `godot_extension` now uses Godot **4.7.2**'s built-in
`VirtualJoystick`. It forwards standard Godot Input Map actions through the
native Java bridge. This gives the future full client port a single
engine-agnostic input contract, but it does **not** claim that the existing
Blaze3D desktop renderer is already a Godot viewport renderer.

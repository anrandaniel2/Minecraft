# Full Minecraft Client → Godot Viewport Port

This directory defines the **real** port target: the complete class tree in
`../extracted/`, not `decompiled_sample/` and not the small Java Native Image
input demo.

## Why a renderer backend port is required

The 26.3 client contains Blaze3D plus the modern `com.mojang.renderpearl` GPU
abstraction. Its stock OpenGL/Vulkan backends own native surfaces and
presentation; loading either as a library cannot make that surface become a
Godot `Viewport`. A real in-viewport port must replace that backend with a
Godot-owned offscreen render target.

[`renderpearl_backend/`](renderpearl_backend/) records the exact Java-25
RenderPearl ABI extracted from this client and defines the port boundary:
Minecraft's `LevelRenderer`/`GameRenderer` retain their RenderPearl calls, a
Java backend remains Godot-free, and only a native GDExtension adapter calls
Godot rendering APIs.

A real port proceeds in this order:

1. **Source recovery** — decompile the complete Java 25 class tree in CI. The
   checked-in `extracted/` directory has class files and resources, but no Java
   source to patch.
2. **Dependency resolution** — resolve every library and platform native from
   Mojang's 26.3 version metadata. They are not bundled in `minecraft-client.jar`.
3. **RenderPearl backend** — implement device, surface, texture, buffer, command
   encoder, render-pass and pipeline APIs over a Godot-owned offscreen target.
4. **Platform adapters** — route Godot input, audio, window state, filesystem,
   clipboard, networking, and lifecycle into the recovered client.
5. **Android** — compile a separate Android `arm64-v8a` GDExtension with the
   Android NDK and provide Android-safe replacements for desktop-only native
   libraries. The Linux x86_64 `.so` files in `godot_extension/bin/` cannot run
   on Android.

`tools/full_client_inventory.py` is the phase-0 guard: it verifies that the
actual input is the full Java 25 class distribution. The `Recover Full Minecraft
Client Source` workflow is phase 1: it uses Java 25 and Vineflower to produce a
source-only CI artifact, verifies it has at least 7,000 `.java` files (nested classes recover into their enclosing source file), and
keeps that large recovered source out of Git. Run the inventory from repository
root:

```bash
python3 tools/full_client_inventory.py
```

## Current milestone

The accompanying `godot_extension` uses Godot **4.7.2**'s built-in
`VirtualJoystick`, multi-touch action controls, fullscreen presentation, and a
resource-pack renderer that reads real Minecraft models/textures. It forwards
standard Godot Input Map actions through the native Java bridge.

The RenderPearl ABI manifest is now a CI-verified hard gate for the next
backend phase. It does **not** claim that the stock desktop OpenGL/Vulkan
backend can already render the complete client inside Godot.

# Minecraft 26.3 RenderPearl → Godot Backend

This is the implementation target for rendering the **complete** extracted
Minecraft client in a Godot viewport. It deliberately targets the renderer API
present in `extracted/`, rather than trying to launch Minecraft's existing
OpenGL/Vulkan window beside Godot.

## Actual 26.3 renderer seam

Minecraft 26.3 contains a modern render abstraction in
`com.mojang.renderpearl.api`. The authoritative Java-25 class ABI is recorded
in [`renderpearl-26.3-abi.json`](renderpearl-26.3-abi.json), generated directly
from the complete client payload by:

```bash
python3 tools/renderpearl_abi_inventory.py \
  --verify full_client_port/renderpearl_backend/renderpearl-26.3-abi.json
```

The Godot backend has to implement these client-owned interfaces:

| RenderPearl API | Godot-backed responsibility |
| --- | --- |
| `GpuDevice` | Device capabilities, texture/buffer/sampler allocation, command encoders, pipeline compilation. |
| `GpuSurface` | A Godot-owned offscreen target; no desktop native window or independent swapchain. |
| `CommandEncoder` | Buffer/texture uploads, copies, render-pass creation, queue submission. |
| `RenderPass` | Pipeline, uniform, vertex/index binding and draw/multi-draw commands. |
| `GpuBuffer` | CPU staging plus Godot GPU-buffer lifetime/range mapping. |
| `GpuTexture` / `GpuTextureView` / `GpuSampler` | Godot textures, views and sampling configuration. |
| `CompiledRenderPipeline` | Translated/compiled Minecraft shaders and fixed render state. |

The stock `renderpearl.backend.opengl` and `renderpearl.backend.vulkan`
packages must **not** be used as the Godot backend. They own their own device,
surface and presentation lifecycle. Reusing them would create a second renderer
or surface rather than placing game pixels inside Godot.

## Required boundary

```text
Complete Minecraft client
    LevelRenderer / GameRenderer / Blaze3D
                 │
                 ▼
      RenderPearl API interfaces
                 │
                 ▼
   GodotRenderPearlBackend (Java, no Godot imports)
                 │ native command ABI
                 ▼
   GDExtension C/C++ platform adapter (Godot APIs live here)
                 │
                 ▼
 Godot RenderingDevice + offscreen SubViewport texture
                 │
                 ▼
        fullscreen Godot viewport
```

The Java backend must call a neutral native command ABI. Only the
GDExtension/platform layer may call Godot APIs. This preserves the project's
Java/Godot separation and makes an Android arm64 implementation possible.

## Native command-stream foundation

`godot_extension/include/minecraft_render_abi.h` and
`godot_extension/src/minecraft_render_abi.c` now define the first executable
boundary for this backend. The ABI has versioned, 8-byte-aligned packets for
resource lifetime/upload, pipeline compilation, render-pass state and draw
operations. It validates complete frame/pass nesting before a future Godot
executor is permitted to touch GPU resources. The native side owns a
thread-safe frame mailbox, so a Java game/render thread can submit a validated
copy while the Godot render thread later atomically detaches an owned snapshot
for one-time packet execution. A newer Java submission can therefore never
mutate or free the frame currently being executed by Godot.

`java/net/minecraft/godot/renderpearl/RenderCommandWriter.java` now encodes
this stream in Java without any Godot imports; its protocol test is compiled in
full-client preflight CI. `GodotGpuDevice` now creates extracted 26.3 resource
adapters and `GodotCommandEncoder` instances using this writer rather than
talking to Godot directly. The C GDExtension will consume it and map packets to
Godot. The native `MinecraftRenderCommandSink` decoder now checks exact packet
payload layouts and dispatches typed fields to a future Godot sink; it still has
no Godot calls of its own. This is intentionally not an OpenGL/Vulkan
context-sharing layer.

## Implementation order

1. **Build input** — recover the complete Java 25 source graph in CI and resolve
   Mojang runtime dependencies. The small `decompiled_sample/` Native Image
   demo is not a substitute for this step.
2. **Platform-neutral boot** — replace the stock `Window`/native-surface and
   desktop event bootstrap with a Godot lifecycle adapter.
3. **Minimal RenderPearl device** — implement `GpuDevice`, resources,
   `CommandEncoder`, and `GpuSurface` for an offscreen Godot target; validate
   clear, texture upload, triangle and indexed draw.
4. **Pipeline translation** — map RenderPearl vertex formats, blend/depth/cull
   states and Minecraft shader inputs onto Godot rendering resources.
5. **Game renderer integration** — point the recovered client's renderer at the
   backend, then validate chunk terrain, entities, GUI, particles, fluids and
   post processing incrementally.
6. **Android** — compile the Java and GDExtension layers for `arm64-v8a`; the
   existing Linux `.so` files cannot be packaged as the Android backend.

## Current code status

The checked-in Godot renderer loads complete Minecraft models/textures and is a
working viewport/resource fallback. It is **not** this RenderPearl backend.

The first Java resource-adapter implementations now exist for the exact
extracted `GpuBuffer`, `GpuTexture`, `GpuTextureView`, and `GpuSampler`
interfaces. They own Godot-neutral handles, buffer mapping/staging storage,
metadata, mip-range checks and resource lifetime; CI compiles and smoke-tests
them against the real Java-25 classes under `extracted/`.

`GodotGpuDevice` and `GodotGpuSurface` now implement the extracted 26.3 device
and surface interfaces. The device reports explicit portable capabilities,
allocates the existing resource adapters, updates command-frame dimensions from
a FIFO Godot-owned surface configuration, and emits encoders through the
neutral transport. The surface tracks configure/acquire/present lifecycles but
intentionally rejects `blitFromTexture`: presenting into Godot needs the next
native `RenderingDevice` packet executor. Pipeline translation is equally
explicit: `compilePipeline` returns a failed future rather than pretending a
Minecraft shader compiled. These adapters are an API/lifecycle seam, not a
claim that command execution or Minecraft terrain is already routed through
the backend.

`GodotCommandEncoder` and `GodotRenderPass` now record descriptor-backed
single-color render passes, buffer uploads, pipeline/buffer/scissor state, and
direct indexed/non-indexed draws to the neutral command stream. Submission is
abstracted through the Godot-free `RenderCommandTransport`.
`GodotNativeRenderCommandTransport` is now the GraalVM implementation: it pins
the encoded Java byte array and calls `minecraft_render_submit_frame`, where
the C GDExtension validates and copies it into the native frame mailbox. A
native-image smoke entry is exercised in Godot headless CI. Unsupported
operations fail explicitly rather than being lost.

The manifest and CI checks remain hard gates so API assumptions cannot silently
drift while `GpuDevice`, texture uploads/uniforms, pipeline translation, and
the native Godot executor are added.

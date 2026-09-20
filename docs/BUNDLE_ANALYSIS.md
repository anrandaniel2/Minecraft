# What is inside `eaglercraft-26.2-0.6.html`

| Block (`<script id=…>`)      | Decoded size | Content                                             |
| ---------------------------- | -----------: | --------------------------------------------------- |
| `eag-inline-decoder`         |     0.2 MB   | brotli decoder (wasm, wasm-bindgen)                 |
| `eag-inline-wasm-br`         |   102 MB     | `classes.wasm` – the game client, TeaVM **WasmGC**  |
| `eag-inline-mesh-wasm-br`    |    18 MB     | `mesh-worker.wasm` – chunk meshing isolate          |
| `eag-inline-server-wasm-br`  |    43 MB     | `server-worker.wasm` – integrated server isolate    |
| `eag-inline-assets`          |   6.6 MB     | `assets.epk`                                        |
| `eag-inline-sounds`          |    26 MB     | `sounds.epk`                                        |
| 6 plain `<script>` blocks    |    98 KB     | loader – **readable, not obfuscated** (see `loader-source/`) |

* The JS is unminified apart from two vendored libraries (wasm-bindgen glue, TeaVM runtime).
* The WASM modules have **no `name` section** – symbols are stripped. The game is
  Java → TeaVM → WasmGC; the correct way to change game code is to rebuild from
  the EaglerCraft Java sources, not to patch this binary.
* Rendering is WebGL 2 from inside `classes.wasm`. Browsers expose no Vulkan
  API; on Android the WebView's ANGLE layer translates WebGL → Vulkan/GLES.

## Why the single-file layout is slow, and what the host does about it

Every launch, the stock page:

1. `atob()`s 75 MB of base64 text on the main thread (chunked with `setTimeout`),
2. brotli-decompresses 163 MB of WASM **in JavaScript/WASM**, single-threaded,
3. hands `WebAssembly.compile()` an `ArrayBuffer` (no streaming, no code cache – a
   `Response` synthesised from memory is not cacheable).
4. ships with `singleThreadMode: true`, so the mesh and server workers never start.

`src/bundle_unpacker.cpp` (C++) performs steps 1–2 **once**, natively and on a
thread pool (≈0.6 s for 195 MB on a 2-core CI runner vs. tens of seconds in JS on a
phone), writes real files, and emits a 167 KB `index.html` whose fetch shim
falls through to the loopback server. Consequences:

* `WebAssembly.compileStreaming()` works → compilation overlaps the download.
* `Cache-Control: immutable` on the wasm/epk → Chromium keeps the *compiled*
  machine code across launches (second launch skips compilation entirely).
* `singleThreadMode` is flipped to `false` and the server sends
  COOP/COEP → cross-origin-isolated context → mesh + server workers run on
  their own cores.
* Peak JS heap drops by ~250 MB (no base64 string + decoded copy + brotli output
  all alive at once).

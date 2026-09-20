# EaglerCraft on Godot (Android)

A **mobile-only Godot 4.5 project** that runs the single-file EaglerCraft
build (`eaglercraft-26.2-0.6.html`) inside a hardware-accelerated environment
on Android. All project logic is written in **C++** (GDExtension) – there is no
GDScript or C# in this repository.

```
┌───────────────────────────────────────────────────────────────────┐
│ Android Activity (Godot, Vulkan "Forward Mobile", threaded render) │
│                                                                    │
│   ┌────────────────────────────────────────────────────────────┐   │
│   │ android.webkit.WebView  (LAYER_TYPE_HARDWARE, GPU process) │   │
│   │      http://127.0.0.1:<port>/eaglercraft.html              │   │
│   │      WebGL2 → ANGLE/GLES on the device GPU                  │   │
│   └────────────────────────────────────────────────────────────┘   │
│                    ▲ HTTP keep-alive                               │
│   ┌────────────────┴───────────────────────────────────────────┐   │
│   │ EaglerHost (C++ GDExtension)                                │   │
│   │  • extraction thread: res://web → user://web                │   │
│   │  • LocalHttpServer: acceptor + N worker threads, loopback   │   │
│   │  • JavaClassWrapper bridge to the Android UI thread          │   │
│   └────────────────────────────────────────────────────────────┘   │
└───────────────────────────────────────────────────────────────────┘
```

## Requirements met

| Requirement          | How                                                                                                          |
| -------------------- | ------------------------------------------------------------------------------------------------------------ |
| Runs in Godot        | `EaglerHost` node (`main.tscn`) hosts the HTML in an Android `WebView` created from C++ via `JavaClassWrapper`. |
| Hardware accelerated | `android:hardwareAccelerated="true"`, `WebView.setLayerType(LAYER_TYPE_HARDWARE)`, WebGL via the GPU process. |
| Multithreaded        | Godot `thread_model=2` (separate render thread), a bundle-extraction thread, and a thread-pool HTTP server. |
| Vulkan               | `rendering_method="mobile"` + `rendering_device/driver.android="vulkan"` with OpenGL fallback disabled.       |
| Mobile only          | Export preset targets Android only (arm64-v8a + armeabi-v7a, minSdk 24).                                      |
| C++ only             | `src/*.cpp` – nothing else contains logic. Build: `SConstruct` + `godot-cpp` submodule.                       |
| APK via Actions      | `.github/workflows/build-apk.yml` compiles the extension for all ABIs and exports a signed APK.               |
| Completely offline   | The 75 MB single-file bundle (assets, sounds, WASM, worker code all inlined) ships inside the APK and is served from `127.0.0.1`. No remote URLs in the bundle; the network-security-config has **no trust anchors** and forbids cleartext except loopback; the C++ host injects a JS guard that rejects any non-loopback `fetch`/XHR/WebSocket and reports `navigator.onLine=false`. Worlds are saved in the WebView's IndexedDB. |

## Repository layout

```
project.godot            Vulkan / mobile / threaded renderer settings
main.tscn                Single EaglerHost node
eaglerhost.gdextension   Library manifest
export_presets.cfg       Android export preset (Gradle build)
SConstruct               Builds libeaglerhost.*.so with godot-cpp
build_profile.json       Trims godot-cpp to the classes we use (faster CI)
src/
  local_http_server.*    Multithreaded loopback static server (pure C++)
  eagler_host.*          Godot node: extraction, server, WebView, lifecycle
  register_types.*       GDExtension entry point
tests/http_server_test.cpp   Host-side test for the server (run in CI)
web/                     Put eaglercraft.html here (see web/README.md)
.github/workflows/       APK compiler
```

## The game bundle

`web/eaglercraft.html` (EaglerCraft 26.2-0.6, single-file build) is committed
in the repo; it was fetched from the Dropbox share by
`.github/workflows/fetch-bundle.yml`. To update it, change `web/BUNDLE_URL`
(or run that workflow manually with a URL) – it downloads and commits the new
file. Everything the game needs is inside that one HTML file, so the APK works
with airplane mode on. Multiplayer (which needs relay servers) is naturally
unavailable offline; singleplayer/LAN-less play is what this build targets.

## Building locally

```bash
git submodule update --init --recursive
pip install scons
export ANDROID_HOME=~/Android/Sdk            # must contain ndk/28.1.13356709
scons platform=android arch=arm64 target=template_release -j8
scons platform=android arch=arm32 target=template_release -j8
# then open the project in Godot 4.5 and export the "Android" preset
```

A Linux build (`scons platform=linux target=template_debug`) is supported only
so the project opens in the desktop editor; the WebView is Android-only.

## Runtime API (from the node)

`get_base_url()`, `get_state()`, `get_server_port()`,
`get_server_worker_count()`, `get_requests_served()`, `reload()`,
`evaluate_javascript(js)`, signals `server_started`, `webview_ready`,
`host_error`.

## Notes / limitations

* The WebView's WebGL context is what renders Minecraft; Godot's own Vulkan
  swapchain sits underneath it. EaglerCraft is JavaScript/WebGL and cannot be
  linked against Vulkan directly, so Vulkan is used for the host surface and
  Chromium's GPU process handles WebGL through the device driver
  (ANGLE-on-Vulkan on most modern Android devices).
* Requires a device with Android 7.0+ and an up-to-date Android System WebView.

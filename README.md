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

## Startup optimisation (native unpack)

On first launch the C++ host converts the 75 MB single-file HTML into
`classes.wasm`, `mesh-worker.wasm`, `server-worker.wasm`, `assets.epk`,
`sounds.epk` and a 167 KB `index.html` (multithreaded base64 + brotli in C++,
~0.6 s). The WebView then stream-compiles the WASM, caches the compiled code
between launches, and the game's mesh/server **workers are enabled** (the
stock file ships single-threaded). Details: `docs/BUNDLE_ANALYSIS.md`.
Toggle with the `native_unpack` / `enable_game_workers` properties.

## Repository layout

```
project.godot            Vulkan / mobile / threaded renderer settings
main.tscn                Single EaglerHost node
eaglerhost.gdextension   Library manifest
export_presets.cfg       Android export preset (Gradle build)
SConstruct               Builds libeaglerhost.*.so with godot-cpp
build_profile.json       Trims godot-cpp to the classes we use (faster CI)
src/
  bundle_unpacker.*      Native single-file → multi-file converter (brotli, threads)
  local_http_server.*    Multithreaded loopback static server (pure C++)
  eagler_host.*          Godot node: extraction, server, WebView, lifecycle
  register_types.*       GDExtension entry point
tests/                   Host-side tests for server + unpacker (run in CI)
thirdparty/brotli        Google brotli decoder (submodule)
docs/                    Bundle analysis + extracted loader JS for reference
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

## Exporting from a clone (desktop or Android editor)

`bin/android/*.so` and `bin/linux/*.so` are **committed** (CI rebuilds and
pushes them on every change to `src/`), so you can open the project in Godot
4.5 and export / one-click-run straight away – no NDK, no Gradle, no C++
toolchain needed on your machine. If the extension fails to load, check that
those files exist in your checkout (`git pull`).

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

## In-app updates

The `AppUpdater` node (C++, `src/app_updater.*`, child of `EaglerHost` in
`main.tscn`) makes installed builds self-updating:

1. On start (and every `auto_check_interval_hours`) it asks
   `https://api.github.com/repos/<repository>/releases` for the newest release
   whose asset matches `asset_pattern` (`*.apk`). With `allow_prerelease = true`
   the rolling **`nightly`** pre-release that every push publishes is eligible;
   set it to `false` to follow only tagged `vX.Y.Z` releases.
2. If it is newer than the running `versionName`, a banner is injected into the
   game page: **Update / Later**.
3. **Update** streams the APK to the app's cache dir, checks the `.sha256`
   sidecar, then **Install** hands it to `PackageInstaller`. Android 8+ asks
   once to allow installs from this app (`REQUEST_INSTALL_PACKAGES`).

Only `api.github.com`, `github.com` and `*.githubusercontent.com` are allowed
by the network-security-config for this; the game itself remains offline.

**Signing.** An update installs only if it is signed with the same key as the
installed build. CI therefore always produces a *release* APK signed with a
stable key: your `RELEASE_KEYSTORE_BASE64/_USER/_PASSWORD` secrets if set,
otherwise the dev key it generates once and commits to `ci/release.keystore`
(see `ci/README.md`). Switching keys requires one manual reinstall.

**Versions.** CI stamps `version/name` (`config/version` from `project.godot`
+ `.<run number>` for branch builds, or the `vX.Y.Z` tag) and a monotonically
increasing `version/code` into the export before building, so every build is
an upgrade over the previous one.

## Diagnosing a stuck loading screen

The unpacked page carries a tiny diagnostics bridge: the bundle's own boot
stages (`window.__eaglerCrashJournal`), boot percentages, `console.error`/
`warn`, uncaught errors and unhandled promise rejections are forwarded to the
native host and printed to logcat as `[EaglerHost/page] …`. If the game has
not reported `game-ready` after 30 s the host asks the page for a full dump
(last 40 boot-log lines + journal); after 90 s it reloads once in the
bundle's single-thread safe mode (`?singlethread`, workers off).

```
adb logcat -s godot:* | grep -E "EaglerHost|AppUpdater"
```

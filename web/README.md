# `web/` – the EaglerCraft bundle

* `eaglercraft.html` – EaglerCraft 26.2-0.6 single-file build (all assets,
  sounds and WASM inlined as base64). Packed into the APK, extracted once to
  `user://web/` and served to the WebView by the in-process loopback server.
  **No network access is required at runtime.**
* `BUNDLE_URL` – where `fetch-bundle.yml` downloads the file from. Change it and
  push (or dispatch the workflow) to update the bundle.
* `index_placeholder.html` – shown only if the bundle is missing.

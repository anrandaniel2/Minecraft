# `web/` – the EaglerCraft bundle

Everything in this folder is packed into the APK, extracted to
`user://web/` on first launch, and served to the WebView by the built-in
multithreaded HTTP server (`src/local_http_server.cpp`).

## Put the game here

Download `eaglercraft-26.2-0.6.html` from the MediaFire link and save it as:

```
web/eaglercraft.html
```

(the file name is configured on the `EaglerHost` node in `main.tscn` via
`html_resource_path`). The single-file EaglerCraft build embeds its assets,
so nothing else is required. If you use a multi-file build (`classes.js`,
`assets.epk`, …), drop them next to the HTML – the whole folder is served.

The CI workflow can also fetch the file for you: set the repository variable
`EAGLERCRAFT_HTML_URL` (or the secret of the same name) to a **direct**
download URL and it will be placed at `web/eaglercraft.html` before export.

`eaglercraft.html` is git-ignored on purpose (it is ~10 MB+ and not ours to
redistribute); `index_placeholder.html` is what you see if it is missing.

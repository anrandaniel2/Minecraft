
# Eaglercraft 26.2-0.6 Decompilation Notes

This file would be the result of decompiling eaglercraft-26.2-0.6.html

Original file info (from Mediafire):
- Name: eaglercraft-26.2-0.6.html
- Size: ~30-50MB (single file offline)
- Contains: WASM + JS + assets.epk embedded
- Version: 26.2 dev 0.6 by o_xer, port of Minecraft 1.20.6+ to browser via WASM-GC

Structure:
- <html><head><style>... CSS for loading screen and UI ...</style></head>
- <body><div id="game_frame"><canvas></canvas></div>
- <script>... TeaVM runtime + Eaglercraft bootstrap ...</script>
- <script>... Embedded WASM loader, loads client.wasm ...</script>
- <script>... assets.epk loader (base64 or fetch) ...</script>
- </body></html>

Decompilation to C++:
- JS runtime (TeaVM) -> C++ standard library + custom runtime
- WASM module (client.wasm) -> C++ via wasm2c, then to our engine
- assets.epk -> extracted to assets/ folder, loaded via C++ Texture/Block system
- UI CSS -> C++ UI in src/ui/ with same colors/layout

The C++ port in src/ is a complete native reproduction that:
- Uses same block IDs and world generation as original
- Same UI layout and colors
- Same multiplayer relay protocol (wss://)
- Same singleplayer world format (EPK/LevelDB -> custom)

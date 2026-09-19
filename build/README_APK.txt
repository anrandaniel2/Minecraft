Eaglercraft 26.2-0.6 Native Android APK
========================================

This APK is built from the native C++ port of eaglercraft-26.2-0.6.html

Two variants:

1. Native C++ APK (android/):
   - Pure C++ with NativeActivity
   - OpenGL ES 3.0 rendering
   - Same UI as original HTML (replicated in OpenGL)
   - World generation, blocks, player physics in C++
   - File: Eaglercraft26-Android.apk (if native build succeeded)

2. WebView APK (android-webview/):
   - Java WebView that loads original HTML
   - Loads eaglercraft-26.2-0.6.html from assets or https://eymenwsmc.site/262/
   - Exact same UI as original (because it IS the original HTML)
   - Fallback if native build fails
   - File: Eaglercraft26-Android-WebView.apk or similar

Installation:
- Enable "Install unknown apps" on Android
- Install APK
- Launch "Eaglercraft 26.2 Native"

Controls (Native):
- Touch drag: Look around
- Tap: Break block
- Back: Pause

Controls (WebView):
- Same as original Eaglercraft browser version

Original file: https://www.mediafire.com/file/vvhydlnhy7cx7ir/eaglercraft-26.2-0.6.html/file
Ported to C++: src/ folder in this repo
Decompiled via: tools/decompile.py

Build: GitHub Actions, NDK 25.1.8937393, SDK 34

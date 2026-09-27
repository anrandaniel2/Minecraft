#!/usr/bin/env bash
# Link the Android arm64 GDExtension around an already-built extracted-client
# Graal image. Native-image itself is built on an AArch64 host; this small C
# step runs on the x86_64 Android packaging runner with the NDK cross compiler.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXTENSION_DIR="$ROOT/godot_extension"
BIN_DIR="${MINECRAFT_OUTPUT_BIN_DIR:-$EXTENSION_DIR/bin}"
GENERATED_DIR="${MINECRAFT_GENERATED_DIR:-$EXTENSION_DIR/build/android/generated}"
ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
ANDROID_API_LEVEL="${ANDROID_API_LEVEL:-30}"

if [[ -z "$ANDROID_NDK_HOME" || ! -d "$ANDROID_NDK_HOME" ]]; then
  echo "ANDROID_NDK_HOME must point at the Android NDK" >&2
  exit 1
fi
if [[ ! -f "$BIN_DIR/libminecraft_java.so" || ! -f "$GENERATED_DIR/minecraft_java.h" ]]; then
  echo "Android Graal image and generated header are required before linking the bridge" >&2
  exit 1
fi

TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64"
CC="${ANDROID_CC:-$TOOLCHAIN/bin/aarch64-linux-android${ANDROID_API_LEVEL}-clang}"
if [[ ! -x "$CC" ]]; then
  echo "Missing Android arm64 clang: $CC" >&2
  exit 1
fi

mkdir -p "$BIN_DIR"
"$CC" -std=c11 -O2 -fPIC -shared -Wall -Wextra -Werror -D_GNU_SOURCE -DANDROID \
  -I"$GENERATED_DIR" \
  -I"$EXTENSION_DIR/include" \
  "$EXTENSION_DIR/src/godot_bridge.c" \
  "$EXTENSION_DIR/src/minecraft_render_abi.c" \
  "$EXTENSION_DIR/src/minecraft_render_executor.c" \
  "$EXTENSION_DIR/src/minecraft_render_native_state.c" \
  -L"$BIN_DIR" -lminecraft_java -ldl -pthread \
  -o "$BIN_DIR/libminecraft_godot.so"

# Android uses the Godot viewport for presentation. This SDL3 ABI stub lets
# Minecraft's Window object exist without creating a second Android window.
"$CC" -std=c11 -O2 -fPIC -shared -Wall -Wextra -Werror -D_GNU_SOURCE -DANDROID \
  "$EXTENSION_DIR/src/sdl3_viewport_stub.c" \
  -o "$BIN_DIR/libSDL3.so"

file "$BIN_DIR/libminecraft_java.so" "$BIN_DIR/libminecraft_godot.so" "$BIN_DIR/libSDL3.so"
readelf -h "$BIN_DIR/libminecraft_java.so" | grep -q 'AArch64'
readelf -h "$BIN_DIR/libminecraft_godot.so" | grep -q 'AArch64'
readelf -h "$BIN_DIR/libSDL3.so" | grep -q 'AArch64'
readelf -d "$BIN_DIR/libminecraft_godot.so" | grep -q 'libminecraft_java.so'

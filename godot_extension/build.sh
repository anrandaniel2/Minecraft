#!/usr/bin/env bash
# Build the Java Native Image library and the Godot C-ABI adapter for Linux x86_64.
# Requirements: GraalVM JDK 25+ with native-image, GCC, and standard libc headers.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXTENSION_DIR="$ROOT/godot_extension"
GRAALVM_HOME="${GRAALVM_HOME:-}"

if [[ -z "$GRAALVM_HOME" ]]; then
  if command -v native-image >/dev/null 2>&1; then
    GRAALVM_HOME="$(cd "$(dirname "$(command -v native-image)")/.." && pwd)"
  else
    echo "GRAALVM_HOME must point to a GraalVM JDK containing native-image." >&2
    exit 1
  fi
fi

JAVA="$GRAALVM_HOME/bin/java"
JAVAC="$GRAALVM_HOME/bin/javac"
NATIVE_IMAGE="$GRAALVM_HOME/bin/native-image"
for tool in "$JAVA" "$JAVAC" "$NATIVE_IMAGE" gcc; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Missing build tool: $tool" >&2; exit 1; }
done

BUILD_DIR="$EXTENSION_DIR/build"
CLASSES="$BUILD_DIR/classes"
NATIVE_DIR="$BUILD_DIR/native"
GENERATED_DIR="$BUILD_DIR/generated"
BIN_DIR="$EXTENSION_DIR/bin"
rm -rf "$BUILD_DIR"
mkdir -p "$CLASSES" "$NATIVE_DIR" "$GENERATED_DIR" "$BIN_DIR"
rm -f "$BIN_DIR"/libminecraft_godot.so "$BIN_DIR"/libminecraft_java.so

"$JAVAC" -d "$CLASSES" \
  "$ROOT/decompiled_sample/net/minecraft/client/Minecraft.java" \
  "$EXTENSION_DIR/java/MinecraftNativeEntrypoints.java"

"$NATIVE_IMAGE" \
  --shared \
  --no-fallback \
  -O2 \
  -cp "$CLASSES" \
  -H:+UnlockExperimentalVMOptions \
  -H:Name=minecraft_java \
  -H:Path="$NATIVE_DIR"

# Native Image 21 emits minecraft_java.so (without a lib prefix) plus a
# minecraft_java.h that includes its graal_isolate*.h siblings. Keep the
# runtime bundle conventionally named libminecraft_java.so for the linker.
JAVA_LIBRARY="$NATIVE_DIR/minecraft_java.so"
JAVA_HEADER="$NATIVE_DIR/minecraft_java.h"
[[ -f "$JAVA_LIBRARY" && -f "$JAVA_HEADER" ]] || {
  echo "native-image did not produce minecraft_java.so and minecraft_java.h." >&2
  exit 1
}
cp "$NATIVE_DIR"/*.h "$GENERATED_DIR/"
cp "$JAVA_LIBRARY" "$BIN_DIR/libminecraft_java.so"

gcc -std=c11 -O2 -fPIC -shared -Wall -Wextra -Werror \
  -I"$EXTENSION_DIR/include" \
  -I"$GENERATED_DIR" \
  "$EXTENSION_DIR/src/godot_bridge.c" \
  "$EXTENSION_DIR/src/minecraft_render_abi.c" \
  -L"$BIN_DIR" -lminecraft_java -pthread \
  -Wl,-rpath,'$ORIGIN' -Wl,-z,origin \
  -o "$BIN_DIR/libminecraft_godot.so"

if command -v strip >/dev/null 2>&1; then
  strip --strip-unneeded "$BIN_DIR/libminecraft_godot.so" || true
fi

echo "Built:"
ls -lh "$BIN_DIR"/*.so
ldd "$BIN_DIR/libminecraft_godot.so"

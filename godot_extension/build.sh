#!/usr/bin/env bash
# Build the extracted Minecraft 26.3 client into libminecraft_java.so.
#
# This script does not compile decompiled_sample. The published binaries are
# replaced only after native-image succeeds, so a failed run leaves the previous
# libraries in place.
#
# Requirements: GraalVM JDK 25 with native-image, GCC, Python 3, and the class
# jars listed by tools/fetch_minecraft_libraries.py.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXTENSION_DIR="$ROOT/godot_extension"
GRAALVM_HOME="${GRAALVM_HOME:-}"

if [[ -z "$GRAALVM_HOME" ]]; then
  if command -v native-image >/dev/null 2>&1; then
    GRAALVM_HOME="$(cd "$(dirname "$(command -v native-image)")/.." && pwd)"
  else
    echo "GRAALVM_HOME must point to a GraalVM JDK 25 containing native-image." >&2
    exit 1
  fi
fi

JAVA="$GRAALVM_HOME/bin/java"
JAVAC="$GRAALVM_HOME/bin/javac"
NATIVE_IMAGE="$GRAALVM_HOME/bin/native-image"
for tool in "$JAVA" "$JAVAC" "$NATIVE_IMAGE" gcc python3; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Missing build tool: $tool" >&2; exit 1; }
done

BUILD_DIR="$EXTENSION_DIR/build"
CLASSES="$BUILD_DIR/classes"
OVERLAY="$BUILD_DIR/overlay"
NATIVE_DIR="$BUILD_DIR/native"
GENERATED_DIR="$BUILD_DIR/generated"
BIN_DIR="$EXTENSION_DIR/bin"
LIBRARY_DIR="$EXTENSION_DIR/native-image/libraries"
CLASSPATH_FILE="$LIBRARY_DIR/classpath.txt"
ADAPTER_DIR="$ROOT/full_client_port/renderpearl_backend/java/net/minecraft/godot/renderpearl"

if [[ ! -f "$ROOT/extracted/net/minecraft/client/Minecraft.class" ]]; then
  echo "extracted/net/minecraft/client/Minecraft.class is missing." >&2
  exit 1
fi
if [[ ! -f "$ROOT/extracted/net/minecraft/client/main/Main.class" ]]; then
  echo "extracted client Main class is missing." >&2
  exit 1
fi
if [[ ! -f "$CLASSPATH_FILE" ]]; then
  echo "Missing $CLASSPATH_FILE. Run tools/fetch_minecraft_libraries.py first." >&2
  exit 1
fi

mkdir -p "$CLASSES" "$OVERLAY" "$NATIVE_DIR" "$GENERATED_DIR" "$BIN_DIR"
rm -rf "$CLASSES" "$OVERLAY" "$NATIVE_DIR"
mkdir -p "$CLASSES" "$OVERLAY" "$NATIVE_DIR"

python3 "$ROOT/tools/redirect_graphics_backend.py" \
  --source "$ROOT/extracted/net/minecraft/client/PreferredGraphicsApi.class" \
  --output "$OVERLAY/net/minecraft/client/PreferredGraphicsApi.class"
python3 - "$OVERLAY/net/minecraft/client/PreferredGraphicsApi.class" << 'PY'
import pathlib, sys
data = pathlib.Path(sys.argv[1]).read_bytes()
if b"net/minecraft/godot/renderpearl/GodotGpuBackend" not in data:
    raise SystemExit("graphics overlay does not point at GodotGpuBackend")
if b"com/mojang/renderpearl/backend/opengl/GlBackend" in data:
    raise SystemExit("graphics overlay still references GlBackend")
PY

LIBRARY_CP="$(paste -sd: "$CLASSPATH_FILE")"
COMPILE_CP="$ROOT/extracted:$LIBRARY_CP"

"$JAVAC" -d "$CLASSES" -cp "$COMPILE_CP" \
  "$ADAPTER_DIR/RenderCommandProtocol.java" \
  "$ADAPTER_DIR/RenderCommandWriter.java" \
  "$ADAPTER_DIR/RenderCommandTransport.java" \
  "$ADAPTER_DIR/GodotNativeRenderCommandTransport.java" \
  "$ADAPTER_DIR/GodotRenderResourceRegistry.java" \
  "$ADAPTER_DIR/GodotGpuBuffer.java" \
  "$ADAPTER_DIR/GodotGpuTexture.java" \
  "$ADAPTER_DIR/GodotGpuTextureView.java" \
  "$ADAPTER_DIR/GodotGpuSampler.java" \
  "$ADAPTER_DIR/GodotCompiledRenderPipeline.java" \
  "$ADAPTER_DIR/GodotRenderPass.java" \
  "$ADAPTER_DIR/GodotCommandEncoder.java" \
  "$ADAPTER_DIR/GodotGpuSurface.java" \
  "$ADAPTER_DIR/GodotGpuDevice.java" \
  "$ADAPTER_DIR/GodotGpuBackend.java" \
  "$EXTENSION_DIR/java/ExtractedClientLauncher.java" \
  "$EXTENSION_DIR/java/ExtractedClientInput.java" \
  "$EXTENSION_DIR/java/MinecraftNativeEntrypoints.java"

if [[ -f "$CLASSES/net/minecraft/client/Minecraft.class" ]]; then
  echo "Build compiled a replacement Minecraft.class. Refusing to image it." >&2
  exit 1
fi

python3 "$ROOT/tools/package_extracted_client.py" \
  --source "$ROOT/extracted" \
  --output "$BUILD_DIR/extracted-client.jar"
IMAGE_CP="$OVERLAY:$CLASSES:$BUILD_DIR/extracted-client.jar:$LIBRARY_CP"
# The JVM probe's agent config is optional. A partial trace has crashed image
# building, so it is only used when explicitly requested.
CONFIG_DIR="$BUILD_DIR/native-image-config"
CONFIG_ARGS=()
if [[ "${MINECRAFT_USE_NATIVE_IMAGE_CONFIG:-}" == 1 && -d "$CONFIG_DIR" && -n "$(find "$CONFIG_DIR" -type f -print -quit)" ]]; then
  CONFIG_ARGS+=("-H:ConfigurationFileDirectories=$CONFIG_DIR")
fi

"$NATIVE_IMAGE" \
  --shared \
  --no-fallback \
  -O2 \
  -cp "$IMAGE_CP" \
  -H:+UnlockExperimentalVMOptions \
  -H:+ReportExceptionStackTraces \
  -H:Name=minecraft_java \
  -H:Path="$NATIVE_DIR" \
  -H:IncludeResources='version\.json|pack\.mcmeta|assets/.*|data/.*' \
  --initialize-at-build-time=minecraft.nativeimage.MinecraftNativeEntrypoints \
  --initialize-at-run-time=net.minecraft,com.mojang,org.lwjgl,io.netty,com.google,it.unimi,org.apache,org.slf4j,org.joml,com.ibm,org.jcraft,at.yawk,net.java,joptsimple,com.azure,com.microsoft,org.jspecify,com.github \
  -J-Xmx6g \
  "${CONFIG_ARGS[@]}"

JAVA_LIBRARY="$NATIVE_DIR/minecraft_java.so"
JAVA_HEADER="$NATIVE_DIR/minecraft_java.h"
[[ -f "$JAVA_LIBRARY" && -f "$JAVA_HEADER" ]] || {
  echo "native-image did not produce minecraft_java.so and minecraft_java.h." >&2
  exit 1
}

python3 - "$JAVA_LIBRARY" << 'PY'
import pathlib, sys
data = pathlib.Path(sys.argv[1]).read_bytes()
required = (
    b"ExtractedClientLauncher",
    b"GodotGpuBackend",
    b"net.minecraft.client.main.Main",
)
missing = [item.decode() for item in required if item not in data]
if missing:
    raise SystemExit("extracted client markers missing from native image: " + ", ".join(missing))
if b"touch input surface ready" in data:
    raise SystemExit("sample client banner leaked into the extracted native image")
print("native image contains the extracted client and GodotGpuBackend")
PY

cp "$NATIVE_DIR"/*.h "$GENERATED_DIR/"
install -m 755 "$JAVA_LIBRARY" "$BIN_DIR/libminecraft_java.so"

gcc -std=c11 -O2 -fPIC -shared -Wall -Wextra -Werror \
  -I"$GENERATED_DIR" \
  -I"$EXTENSION_DIR/include" \
  "$EXTENSION_DIR/src/godot_bridge.c" \
  "$EXTENSION_DIR/src/minecraft_render_abi.c" \
  "$EXTENSION_DIR/src/minecraft_render_executor.c" \
  "$EXTENSION_DIR/src/minecraft_render_native_state.c" \
  -L"$BIN_DIR" -lminecraft_java -ldl -pthread \
  -Wl,-rpath,'$ORIGIN' -Wl,-z,origin \
  -o "$BIN_DIR/libminecraft_godot.so"

if command -v strip >/dev/null 2>&1; then
  strip --strip-unneeded "$BIN_DIR/libminecraft_godot.so" || true
fi

echo "Built extracted client libraries:"
ls -lh "$BIN_DIR"/*.so
ldd "$BIN_DIR/libminecraft_godot.so"

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
# ClientBootstrap initializes VulkanFeatureSets before any device exists. The
# extracted initializer reflects on LWJGL structs that native-image does not
# expose. This overlay keeps the class linkable without that reflection. The
# Godot backend does not query the sets.
"$JAVAC" -d "$OVERLAY" -cp "$ROOT/extracted:$(paste -sd: "$CLASSPATH_FILE")" \
  "$EXTENSION_DIR/java/com/mojang/renderpearl/backend/vulkan/VulkanFeatureSets.java" \
  "$EXTENSION_DIR/java/com/mojang/blaze3d/platform/SdlDebug.java" \
  "$EXTENSION_DIR/java/org/lwjgl/system/JNI.java"
python3 - "$OVERLAY/org/lwjgl/system/JNI.class" << 'PY'
import pathlib, sys
data = pathlib.Path(sys.argv[1]).read_bytes()
if b"GODOT_JNI_OVERLAY" not in data:
    raise SystemExit("JNI overlay was not compiled into the image classpath")
if b"JNIBindingsImpl" in data or b"ffmGenerate" in data:
    raise SystemExit("JNI overlay still generates a hidden FFM class")
print("JNI overlay uses native methods, not FFM class generation")
PY
python3 - "$ROOT/godot_extension/native-image/libraries" << 'PY'
import pathlib, sys, zipfile
root = pathlib.Path(sys.argv[1])
removed = []
for jar in root.glob("lwjgl-3*.jar"):
    if jar.name.startswith("lwjgl-3") and "natives" not in jar.name:
        with zipfile.ZipFile(jar, "r") as archive:
            names = [name for name in archive.namelist() if name.endswith("org/lwjgl/system/JNI.class")]
        if not names:
            continue
        temp = jar.with_suffix(".jar.tmp")
        with zipfile.ZipFile(jar, "r") as source, zipfile.ZipFile(temp, "w") as target:
            for info in source.infolist():
                if info.filename.endswith("org/lwjgl/system/JNI.class"):
                    removed.append(f"{jar.name}:{info.filename}")
                    continue
                target.writestr(info, source.read(info.filename))
        temp.replace(jar)
if not removed:
    raise SystemExit("LWJGL jar has no JNI class to replace with the native-method overlay")
print("removed versioned JNI classes:", ", ".join(removed))
PY
python3 - "$OVERLAY/com/mojang/renderpearl/backend/vulkan/VulkanFeatureSets.class" << 'PY'
import pathlib, sys
data = pathlib.Path(sys.argv[1]).read_bytes()
if b"org/lwjgl/vulkan/VkPhysicalDeviceFeatures2" in data:
    raise SystemExit("Vulkan feature overlay still reflects on LWJGL structs")
PY
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
  "$ADAPTER_DIR/GodotGpuFence.java" \
  "$ADAPTER_DIR/GodotGpuQueryPool.java" \
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
python3 - "$CLASSPATH_FILE" << 'PY'
import pathlib, sys, zipfile
bad = []
for line in pathlib.Path(sys.argv[1]).read_text().splitlines():
    if not line:
        continue
    with zipfile.ZipFile(line) as archive:
        names = [name for name in archive.namelist() if name.endswith("package-info.class")]
        if names:
            bad.append(f"{line}: {', '.join(names)}")
if bad:
    raise SystemExit("package-info classes still on the native-image classpath:\n" + "\n".join(bad))
print("classpath has no package-info classes")
PY
IMAGE_CP="$OVERLAY:$CLASSES:$BUILD_DIR/extracted-client.jar:$LIBRARY_CP"
# The JVM probe's agent config is optional. A partial trace has crashed image
# building, so it is only used when explicitly requested.
CONFIG_DIR="$BUILD_DIR/native-image-config"
CONFIG_ARGS=()
if [[ "${MINECRAFT_USE_NATIVE_IMAGE_CONFIG:-}" == 1 && -d "$CONFIG_DIR" && -n "$(find "$CONFIG_DIR" -type f -print -quit)" ]]; then
  CONFIG_ARGS+=("-H:ConfigurationFileDirectories=$CONFIG_DIR")
fi
# LWJGL defines org.lwjgl.system.JNIBindingsImpl at runtime. Native image rejects
# that unless the JVM probe captured the exact bytecode. Do not pass the rest of
# the agent trace; a partial reflect config has crashed image builds.
PREDEFINED_DIR="$BUILD_DIR/predefined-classes"
if [[ -f "$CONFIG_DIR/predefined-classes-config.json" ]]; then
  rm -rf "$PREDEFINED_DIR"
  mkdir -p "$PREDEFINED_DIR"
  cp "$CONFIG_DIR/predefined-classes-config.json" "$PREDEFINED_DIR/"
  if [[ -d "$CONFIG_DIR/agent-extracted-predefined-classes" ]]; then
    cp -a "$CONFIG_DIR/agent-extracted-predefined-classes" "$PREDEFINED_DIR/"
  fi
  CONFIG_ARGS+=("-H:ConfigurationFileDirectories=$PREDEFINED_DIR")
  echo "predefined classes:"
  find "$PREDEFINED_DIR" -type f -printf '%p %s\n'
fi
# JNI native methods are linked from liblwjgl.so at runtime. Register the class
# so a missing JNI lookup is reported instead of failing the image build.
CONFIG_ARGS+=("-H:ConfigurationFileDirectories=$EXTENSION_DIR/native-image/jni")

MEM_KB="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
HEAP_MB="$(( MEM_KB / 1024 - 2048 ))"
if [[ "$HEAP_MB" -lt 6144 ]]; then
  HEAP_MB=6144
fi
if [[ "$HEAP_MB" -gt 12288 ]]; then
  HEAP_MB=12288
fi
echo "native-image heap ${HEAP_MB} MB (MemTotal ${MEM_KB} KB)"
set +e
"$NATIVE_IMAGE" \
  --shared \
  --no-fallback \
  -O2 \
  --parallelism=1 \
  -cp "$IMAGE_CP" \
  -H:+UnlockExperimentalVMOptions \
  -H:+ReportExceptionStackTraces \
  -H:Name=minecraft_java \
  -H:Path="$NATIVE_DIR" \
  -H:IncludeResources='version\.json|pack\.mcmeta|assets/.*|data/.*' \
  --initialize-at-build-time=minecraft.nativeimage.MinecraftNativeEntrypoints \
  --initialize-at-run-time=net.minecraft,com.mojang,org.lwjgl,io.netty,com.google,it.unimi,org.apache,org.slf4j,org.joml,com.ibm,org.jcraft,at.yawk,net.java,joptsimple,com.azure,com.microsoft,org.jspecify,com.github \
  -J-Xmx"${HEAP_MB}m" \
  "${CONFIG_ARGS[@]}"
image_status=$?
set -e
echo "native-image exit ${image_status}"
find "$NATIVE_DIR" -maxdepth 2 -type f -printf 'artifact %p %s\n' || true
if [[ "$image_status" -ne 0 ]]; then
  echo "Error: native-image exited ${image_status}" >&2
  exit "$image_status"
fi

if [[ ! -f "$NATIVE_DIR/minecraft_java.so" && -f "$NATIVE_DIR/libminecraft_java.so" ]]; then
  JAVA_LIBRARY="$NATIVE_DIR/libminecraft_java.so"
else
  JAVA_LIBRARY="$NATIVE_DIR/minecraft_java.so"
fi
if [[ ! -f "$JAVA_LIBRARY" ]]; then
  echo "Error: native-image did not produce minecraft_java.so" >&2
  exit 1
fi
if [[ -f "$NATIVE_DIR/minecraft_java.h" ]]; then
  cp "$NATIVE_DIR"/*.h "$GENERATED_DIR/"
elif [[ -f "$NATIVE_DIR/libminecraft_java.h" ]]; then
  cp "$NATIVE_DIR"/*.h "$GENERATED_DIR/"
  cp "$NATIVE_DIR/libminecraft_java.h" "$GENERATED_DIR/minecraft_java.h"
else
  echo "Error: native-image did not produce minecraft_java.h; using fallback declarations" >&2
  cp "$EXTENSION_DIR/include/minecraft_java.h" "$GENERATED_DIR/minecraft_java.h"
fi
python3 "$ROOT/tools/verify_extracted_native_image.py" "$JAVA_LIBRARY"
install -m 755 "$JAVA_LIBRARY" "$BIN_DIR/libminecraft_java.so"

gcc -std=c11 -O2 -fPIC -shared -Wall -Wextra -Werror -D_GNU_SOURCE \
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

#!/usr/bin/env python3
"""Verify that an Android APK is a real Godot/C# build containing actual game assets.

This exists because earlier CI runs released hand-made 2.4KB "placeholder" APKs
(text files named libgodot_android.so / godot-pck-placeholder.txt) whenever the
real Godot export failed. Any APK that fails these checks must never be
published.

Usage: verify_android_apk.py <path-to-apk>
"""
from __future__ import annotations

import os
import struct
import sys
import zipfile

MIN_APK_BYTES = 8 * 1024 * 1024        # real builds are 30-100 MB; placeholders are ~2 KB
MIN_ASSETS_TOTAL_BYTES = 4 * 1024 * 1024  # game data (textures, scenes, .NET assemblies)
MIN_LARGEST_ASSET_BYTES = 100 * 1024
MIN_ENGINE_SO_BYTES = 500 * 1024       # libgodot_android.so is many MB
MIN_DOTNET_SO_BYTES = 100 * 1024
MIN_CLASSES_DEX_BYTES = 2 * 1024
FORBIDDEN_ABI_PREFIXES = (
    "lib/armeabi-v7a/",
    "lib/x86/",
    "lib/x86_64/",
)
PLACEHOLDER_MARKERS = ("placeholder", "dummy", "example.so", "godot-pck-placeholder")
DOTNET_SO_HINTS = ("mono", "hostfxr", "coreclr", "hostpolicy", "systemio", "netcore")


def fail(errors: list[str]) -> None:
    print("\nAPK VERIFICATION FAILED:")
    for e in errors:
        print(f"  - {e}")
    sys.exit(1)


def main() -> None:
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    path = sys.argv[1]
    errors: list[str] = []

    if not os.path.isfile(path):
        fail([f"APK not found: {path}"])

    size = os.path.getsize(path)
    print(f"APK: {path}\nSize: {size} bytes ({size / 1e6:.1f} MB)")
    if size < MIN_APK_BYTES:
        errors.append(f"APK is only {size} bytes (< {MIN_APK_BYTES}) - this is a placeholder, not a real build")

    with open(path, "rb") as f:
        if f.read(2) != b"PK":
            errors.append("file is not a ZIP/APK archive")

    try:
        z = zipfile.ZipFile(path)
    except zipfile.BadZipFile as e:
        fail(errors + [f"cannot open APK as zip: {e}"])

    with z:
        infos = z.infolist()
        names = [i.filename for i in infos]
        print(f"Entries: {len(names)}")

        for n in names:
            low = n.lower()
            for marker in PLACEHOLDER_MARKERS:
                if marker in low:
                    errors.append(f"placeholder marker {marker!r} found in entry name: {n}")

        # AndroidManifest
        manifest = [i for i in infos if i.filename == "AndroidManifest.xml"]
        if not manifest:
            errors.append("AndroidManifest.xml missing")
        elif manifest[0].file_size < 400:
            errors.append(f"AndroidManifest.xml suspiciously small ({manifest[0].file_size} bytes)")

        # Real dex bytecode (not a 108-byte text stub)
        dex = [i for i in infos if i.filename.startswith("classes") and i.filename.endswith(".dex")]
        if not dex:
            errors.append("classes*.dex missing")
        else:
            biggest_dex = max(dex, key=lambda i: i.file_size)
            if biggest_dex.file_size < MIN_CLASSES_DEX_BYTES:
                errors.append(f"largest classes*.dex is only {biggest_dex.file_size} bytes")
            with z.open(biggest_dex) as df:
                if df.read(4) != b"dex\n":
                    errors.append(f"{biggest_dex.filename} does not start with DEX magic")

        # Native libs: arm64 only, real ELF binaries
        for prefix in FORBIDDEN_ABI_PREFIXES:
            bad = [n for n in names if n.startswith(prefix)]
            if bad:
                errors.append(f"forbidden ABI entries present ({prefix}): {bad[:5]}")

        arm64_sos = [i for i in infos if i.filename.startswith("lib/arm64-v8a/") and i.filename.endswith(".so")]
        if len(arm64_sos) < 2:
            errors.append(f"expected several lib/arm64-v8a/*.so entries (engine + .NET runtime), found {len(arm64_sos)}")
        engine_sos = [i for i in arm64_sos if "godot" in i.filename.lower()]
        if not engine_sos:
            errors.append("no lib/arm64-v8a/*godot*.so engine library found")
        elif max(i.file_size for i in engine_sos) < MIN_ENGINE_SO_BYTES:
            errors.append("engine .so is too small to be a real Godot binary")

        dotnet_sos = [i for i in arm64_sos if any(h in i.filename.lower() for h in DOTNET_SO_HINTS)]
        if not dotnet_sos:
            errors.append(
                "no .NET/Mono runtime .so found under lib/arm64-v8a/ "
                f"(entries: {[i.filename for i in arm64_sos][:10]}) - C# game would not run"
            )
        else:
            if max(i.file_size for i in dotnet_sos) < MIN_DOTNET_SO_BYTES:
                errors.append(".NET/Mono runtime .so is too small to be real")

        for so in arm64_sos:
            with z.open(so) as sf:
                if sf.read(4) != b"\x7fELF":
                    errors.append(f"{so.filename} is not a real ELF shared object")
        if len(arm64_sos) >= 2 and max(i.file_size for i in arm64_sos) < MIN_ENGINE_SO_BYTES:
            errors.append("largest native library is too small to be real")

        # Actual game assets (packed resources: textures, scenes, .NET assemblies)
        assets = [i for i in infos if i.filename.startswith("assets/") and not i.is_dir()]
        assets_total = sum(i.file_size for i in assets)
        print(f"assets/: {len(assets)} files, {assets_total / 1e6:.1f} MB total")
        if assets_total < MIN_ASSETS_TOTAL_BYTES:
            errors.append(f"assets/ only {assets_total} bytes total - real game data is missing")
        if not assets or max(i.file_size for i in assets) < MIN_LARGEST_ASSET_BYTES:
            errors.append("no large asset file (pck/assemblies) found under assets/")

        # Compiled C# must be shipped as managed assemblies - if raw game source
        # ends up in the APK the C# export plugin failed (e.g. solution not found)
        # and the game would not run.
        assemblies = [i for i in assets if i.filename.endswith(".dll")]
        if not assemblies:
            errors.append(
                "no managed .dll assemblies under assets/ (the C# game code is not embedded; "
                "dotnet publish output is missing)"
            )
        leaked_sources = [i for i in assets if i.filename.endswith(".cs") and i.file_size > 16]
        if leaked_sources:
            errors.append(
                f"{len(leaked_sources)} raw .cs source files were packed into assets/ instead of "
                f"compiled assemblies (e.g. {leaked_sources[0].filename}) - C# export plugin failed"
            )

        # Signed
        signed = [n for n in names if n.startswith("META-INF/") and n.endswith((".RSA", ".EC", ".DSA"))]
        if not signed:
            errors.append("APK is not signed (no META-INF/*.RSA|EC|DSA)")

        print("\nLargest entries:")
        for i in sorted(infos, key=lambda i: -i.file_size)[:15]:
            print(f"  {i.file_size:>12,}  {i.filename}")

    if errors:
        fail(errors)

    print("\nAPK VERIFICATION PASSED: real build with actual assets, arm64-v8a only.")


if __name__ == "__main__":
    main()

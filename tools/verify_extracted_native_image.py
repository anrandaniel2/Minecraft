#!/usr/bin/env python3
"""Fail if a native library is not the extracted Minecraft 26.3 client."""

from __future__ import annotations

import pathlib
import sys

IMAGE_MARKER = b"extracted-minecraft-26.3-client"
SAMPLE_BANNER = b"touch input surface ready"
# A JDK-only shared image is far smaller than the extracted client.
MIN_BYTES = 30_000_000
CLASS_MARKERS = (
    b"ExtractedClientLauncher",
    b"GodotGpuBackend",
    b"net.minecraft.client.main.Main",
    b"net/minecraft/client/main/Main",
)


def contains_text(data: bytes, text: bytes) -> bool:
    if text in data:
        return True
    return text.decode().encode("utf-16le") in data


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: verify_extracted_native_image.py LIB", file=sys.stderr)
        return 2
    path = pathlib.Path(sys.argv[1])
    data = path.read_bytes()
    if SAMPLE_BANNER in data or SAMPLE_BANNER.decode().encode("utf-16le") in data:
        print("Error: sample client banner is still in the native library", file=sys.stderr)
        return 1
    if len(data) < MIN_BYTES:
        print(
            f"Error: native library is only {len(data)} bytes; extracted client was not imaged",
            file=sys.stderr,
        )
        return 1
    if not contains_text(data, IMAGE_MARKER):
        print(
            f"Error: extracted-client marker missing from {path} ({len(data)} bytes)",
            file=sys.stderr,
        )
        return 1
    if not any(contains_text(data, marker) for marker in CLASS_MARKERS):
        print(
            "Error: extracted client class names missing from native image",
            file=sys.stderr,
        )
        return 1
    if b"minecraft_bootstrap" not in data:
        print("Error: minecraft_bootstrap export missing from native image", file=sys.stderr)
        return 1
    print(f"{path} is the extracted client ({len(data)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

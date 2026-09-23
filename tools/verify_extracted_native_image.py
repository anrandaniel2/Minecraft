#!/usr/bin/env python3
"""Fail if the published native library is still the sample client."""

from __future__ import annotations

import pathlib
import sys

REQUIRED = (
    b"ExtractedClientLauncher",
    b"GodotGpuBackend",
    b"net.minecraft.client.main.Main",
)
SAMPLE_BANNER = b"touch input surface ready"


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: verify_extracted_native_image.py LIB", file=sys.stderr)
        return 2
    data = pathlib.Path(sys.argv[1]).read_bytes()
    missing = [item.decode() for item in REQUIRED if item not in data]
    if missing:
        print("extracted client markers missing: " + ", ".join(missing), file=sys.stderr)
        return 1
    if SAMPLE_BANNER in data:
        print("sample client banner is still in the native library", file=sys.stderr)
        return 1
    print(f"{sys.argv[1]} is the extracted client ({len(data)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

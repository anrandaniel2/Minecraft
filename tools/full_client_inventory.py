#!/usr/bin/env python3
"""Inventory the actual extracted Minecraft client input for the renderer port.

This intentionally reads `extracted/`, never `decompiled_sample/`: the latter
is only a small source demonstration. The inventory is dependency-free so it
can run in CI before a Java toolchain is installed.
"""
from __future__ import annotations

import argparse
import json
import struct
from collections import Counter
from pathlib import Path


def class_major(path: Path) -> int:
    with path.open("rb") as stream:
        header = stream.read(8)
    if len(header) != 8 or header[:4] != b"\xca\xfe\xba\xbe":
        raise ValueError(f"not a Java class file: {path}")
    return struct.unpack(">H", header[6:8])[0]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--client-root", default="extracted", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    root: Path = args.client_root
    classes = sorted(root.rglob("*.class"))
    if not classes:
        raise SystemExit(f"No .class files found in {root}; extract minecraft-client.jar first.")

    majors = Counter(class_major(path) for path in classes)
    packages = Counter(path.relative_to(root).parts[0] for path in classes)
    inventory = {
        "client_root": str(root),
        "class_count": len(classes),
        "java_source_count": sum(1 for _ in root.rglob("*.java")),
        "class_file_major_versions": dict(sorted(majors.items())),
        "top_level_class_packages": dict(sorted(packages.items())),
        "required_port_layers": [
            "full Java 25 source generated from this bytecode",
            "Minecraft external dependency and native-library resolver",
            "Blaze3D/LWJGL-to-Godot RenderingDevice renderer replacement",
            "Godot input/audio/filesystem platform adapters",
            "Android arm64 Godot GDExtension and Android-safe assets",
        ],
    }
    print(json.dumps(inventory, indent=2, sort_keys=True))
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(inventory, indent=2, sort_keys=True) + "\n")

    # Minecraft 26.3 is Java 25, whose class-file major is 69.
    if set(majors) != {69}:
        raise SystemExit(f"Expected Java 25 class-file major 69, got {sorted(majors)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

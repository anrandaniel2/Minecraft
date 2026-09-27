#!/usr/bin/env python3
"""Lock the actual Minecraft 26.3 RenderPearl API used by the Godot backend.

The complete client is distributed in ``extracted/`` as Java 25 bytecode.  A
Godot renderer must target the API that is really present in that bytecode, not
an assumed legacy GLFW-only Blaze3D API.  This dependency-free class-file
reader extracts the RenderPearl interfaces that a future Godot GPU backend must
implement and can verify the checked-in ABI manifest in CI.
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CLASSES = ROOT / "extracted"
DEFAULT_MANIFEST = ROOT / "full_client_port" / "renderpearl_backend" / "renderpearl-26.3-abi.json"

# These are the platform-facing seam between Minecraft's retained renderer and
# the new Godot backend. They are intentionally all loaded from extracted/.
TARGET_CLASSES = (
    "com/mojang/renderpearl/api/device/GpuDevice",
    "com/mojang/renderpearl/api/device/GpuSurface",
    "com/mojang/renderpearl/api/commands/CommandEncoder",
    "com/mojang/renderpearl/api/commands/RenderPass",
    "com/mojang/renderpearl/api/buffers/GpuBuffer",
    "com/mojang/renderpearl/api/textures/GpuTexture",
    "com/mojang/renderpearl/api/textures/GpuTextureView",
    "com/mojang/renderpearl/api/textures/GpuSampler",
    "com/mojang/renderpearl/api/pipeline/CompiledRenderPipeline",
)

EXPECTED_METHODS = {
    "com/mojang/renderpearl/api/device/GpuDevice": {
        "createSurface",
        "createCommandEncoder",
        "createTexture",
        "createBuffer",
        "compilePipeline",
    },
    "com/mojang/renderpearl/api/device/GpuSurface": {
        "configure",
        "acquireNextTexture",
        "blitFromTexture",
        "present",
    },
    "com/mojang/renderpearl/api/commands/CommandEncoder": {
        "createRenderPass",
        "submit",
        "writeToBuffer",
        "writeToTexture",
        "copyBufferToTexture",
    },
    "com/mojang/renderpearl/api/commands/RenderPass": {
        "setPipeline",
        "setVertexBuffer",
        "setIndexBuffer",
        "draw",
        "drawIndexed",
    },
}


class ClassFormatError(ValueError):
    """Raised for a malformed class file."""


class Reader:
    def __init__(self, data: bytes, path: Path) -> None:
        self.data = data
        self.path = path
        self.offset = 0

    def read_u1(self) -> int:
        return self._unpack(">B", 1)

    def read_u2(self) -> int:
        return self._unpack(">H", 2)

    def read_u4(self) -> int:
        return self._unpack(">I", 4)

    def read_bytes(self, size: int) -> bytes:
        if self.offset + size > len(self.data):
            raise ClassFormatError(f"truncated class file: {self.path}")
        value = self.data[self.offset : self.offset + size]
        self.offset += size
        return value

    def _unpack(self, fmt: str, size: int) -> int:
        return struct.unpack(fmt, self.read_bytes(size))[0]


def skip_attributes(reader: Reader) -> None:
    for _ in range(reader.read_u2()):
        reader.read_u2()  # attribute_name_index
        reader.read_bytes(reader.read_u4())


def parse_class(path: Path) -> dict[str, Any]:
    reader = Reader(path.read_bytes(), path)
    if reader.read_u4() != 0xCAFEBABE:
        raise ClassFormatError(f"not a Java class file: {path}")
    minor = reader.read_u2()
    major = reader.read_u2()

    constant_pool: list[Any] = [None]
    index = 1
    count = reader.read_u2()
    while index < count:
        tag = reader.read_u1()
        if tag == 1:  # CONSTANT_Utf8
            size = reader.read_u2()
            constant_pool.append((tag, reader.read_bytes(size).decode("utf-8", "replace")))
        elif tag in (3, 4):  # Integer, Float
            reader.read_u4()
            constant_pool.append((tag, None))
        elif tag in (5, 6):  # Long, Double consume two slots
            reader.read_u4()
            reader.read_u4()
            constant_pool.extend(((tag, None), None))
            index += 1
        elif tag in (7, 8, 16, 19, 20):  # Class, String, MethodType, Module, Package
            constant_pool.append((tag, reader.read_u2()))
        elif tag in (9, 10, 11, 12, 17, 18):  # refs, NameAndType, dynamic
            constant_pool.append((tag, (reader.read_u2(), reader.read_u2())))
        elif tag == 15:  # MethodHandle
            constant_pool.append((tag, (reader.read_u1(), reader.read_u2())))
        else:
            raise ClassFormatError(f"unknown constant-pool tag {tag} in {path}")
        index += 1

    def utf8(pool_index: int) -> str:
        entry = constant_pool[pool_index]
        if not entry or entry[0] != 1:
            raise ClassFormatError(f"invalid UTF-8 constant {pool_index} in {path}")
        return entry[1]

    def class_name(pool_index: int) -> str:
        entry = constant_pool[pool_index]
        if not entry or entry[0] != 7:
            raise ClassFormatError(f"invalid class constant {pool_index} in {path}")
        return utf8(entry[1])

    access_flags = reader.read_u2()
    this_class = class_name(reader.read_u2())
    super_class_index = reader.read_u2()
    super_class = class_name(super_class_index) if super_class_index else None
    interfaces = [class_name(reader.read_u2()) for _ in range(reader.read_u2())]

    fields: list[dict[str, Any]] = []
    for _ in range(reader.read_u2()):
        field_access = reader.read_u2()
        fields.append(
            {
                "access": field_access,
                "name": utf8(reader.read_u2()),
                "descriptor": utf8(reader.read_u2()),
            }
        )
        skip_attributes(reader)

    methods: list[dict[str, Any]] = []
    for _ in range(reader.read_u2()):
        method_access = reader.read_u2()
        methods.append(
            {
                "access": method_access,
                "name": utf8(reader.read_u2()),
                "descriptor": utf8(reader.read_u2()),
            }
        )
        skip_attributes(reader)
    skip_attributes(reader)

    return {
        "path": str(path),
        "version": {"major": major, "minor": minor},
        "access": access_flags,
        "name": this_class,
        "super": super_class,
        "interfaces": interfaces,
        "fields": fields,
        "methods": methods,
    }


def build_manifest(classes_root: Path) -> dict[str, Any]:
    classes: list[dict[str, Any]] = []
    for class_name in TARGET_CLASSES:
        path = classes_root / f"{class_name}.class"
        if not path.is_file():
            raise FileNotFoundError(f"required RenderPearl API class is missing: {path}")
        parsed = parse_class(path)
        method_names = {method["name"] for method in parsed["methods"]}
        missing = EXPECTED_METHODS.get(class_name, set()) - method_names
        if missing:
            raise ClassFormatError(f"{class_name} misses expected methods: {', '.join(sorted(missing))}")
        # The source path is environment-specific and not part of the ABI lock.
        parsed.pop("path")
        classes.append(parsed)

    majors = {entry["version"]["major"] for entry in classes}
    if majors != {69}:  # Java 25
        raise ClassFormatError(f"RenderPearl classes are not Java 25 bytecode: {sorted(majors)}")

    return {
        "schema": 1,
        "minecraft_version": "26.3",
        "java_class_major": 69,
        "classes": classes,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--classes", type=Path, default=DEFAULT_CLASSES, help="root containing com/mojang class files")
    parser.add_argument("--output", type=Path, help="write generated manifest to this path")
    parser.add_argument("--verify", type=Path, help="compare against an existing manifest")
    args = parser.parse_args()

    manifest = build_manifest(args.classes.resolve())
    formatted = json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(formatted, encoding="utf-8")
    if args.verify:
        expected = args.verify.read_text(encoding="utf-8")
        if expected != formatted:
            print(
                f"RenderPearl ABI manifest differs from extracted client: {args.verify}. "
                "Regenerate it with --output after reviewing the backend impact.",
                file=sys.stderr,
            )
            return 1
    if not args.output and not args.verify:
        print(formatted, end="")
    print(f"Validated RenderPearl ABI: {len(manifest['classes'])} API classes from Minecraft 26.3", file=sys.stderr)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ClassFormatError, FileNotFoundError, OSError, struct.error) as error:
        print(f"RenderPearl ABI inventory failed: {error}", file=sys.stderr)
        raise SystemExit(1)

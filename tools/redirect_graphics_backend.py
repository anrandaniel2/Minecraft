#!/usr/bin/env python3
"""Point Minecraft's default graphics backend at GodotGpuBackend.

The extracted client does not use ServiceLoader. PreferredGraphicsApi.getBackendsToTry
constructs GlBackend and VulkanBackend directly. The GlBackend class-name constant is
the same length as GodotGpuBackend, so the default (non-Vulkan) slot can be redirected
by an in-place UTF-8 replacement. The extracted class is left untouched; the result is
a classpath overlay that must be listed before extracted/.
"""

from __future__ import annotations

import argparse
import pathlib
import sys

SOURCE_NAME = "com/mojang/renderpearl/backend/opengl/GlBackend"
TARGET_NAME = "net/minecraft/godot/renderpearl/GodotGpuBackend"


def redirect(source: bytes) -> bytes:
    if len(SOURCE_NAME) != len(TARGET_NAME):
        raise SystemExit("backend class names must stay the same UTF-8 length")
    encoded_source = SOURCE_NAME.encode("utf-8")
    encoded_target = TARGET_NAME.encode("utf-8")
    # The class-name constant and the matching field descriptor both contain this
    # byte sequence. Both are the same length after the rename, so either one
    # replacement is enough and both must move together.
    occurrences = source.count(encoded_source)
    if occurrences != 2:
        raise SystemExit(
            f"expected the GlBackend name and descriptor, found {occurrences} occurrences"
        )
    if encoded_target in source:
        return source
    return source.replace(encoded_source, encoded_target)


def verify(class_bytes: bytes) -> None:
    if not class_bytes.startswith(b"\xca\xfe\xba\xbe"):
        raise SystemExit("redirected file is not a Java class")
    if SOURCE_NAME.encode("utf-8") in class_bytes:
        raise SystemExit("GlBackend reference survived redirection")
    if class_bytes.count(TARGET_NAME.encode("utf-8")) != 2:
        raise SystemExit("GodotGpuBackend name and descriptor were not both written")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        type=pathlib.Path,
        default=pathlib.Path("extracted/net/minecraft/client/PreferredGraphicsApi.class"),
    )
    parser.add_argument(
        "--output",
        type=pathlib.Path,
        default=pathlib.Path(
            "full_client_port/renderpearl_backend/overlay/net/minecraft/client/PreferredGraphicsApi.class"
        ),
    )
    args = parser.parse_args()
    redirected = redirect(args.source.read_bytes())
    verify(redirected)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(redirected)
    print(f"wrote {args.output} ({len(redirected)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

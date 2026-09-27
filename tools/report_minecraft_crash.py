#!/usr/bin/env python3
"""Print a compact Minecraft crash-report excerpt for a CI annotation."""

from __future__ import annotations

import pathlib
import sys

SKIP = {".git", "extracted", "decompiled_sample", "node_modules", ".gradle"}


def interesting(line: str) -> bool:
    text = line.strip()
    if not text:
        return False
    if text.startswith("Description:") or text.startswith("Caused by") or text.startswith("java."):
        return True
    if text.startswith("at net.minecraft.") or text.startswith("at com.mojang."):
        return True
    return any(token in text for token in ("Exception", "Game crashed", "submission failed", "Unsupported"))


def find_reports(roots: list[pathlib.Path]) -> list[pathlib.Path]:
    found: list[pathlib.Path] = []
    for root in roots:
        if not root.exists():
            continue
        for directory in walk(root, 0):
            if directory.name != "crash-reports":
                continue
            found.extend(path for path in directory.iterdir() if path.is_file())
    return found


def walk(directory: pathlib.Path, depth: int):
    if depth > 4 or not directory.is_dir():
        return
    yield directory
    try:
        children = list(directory.iterdir())
    except OSError:
        return
    for child in children:
        if child.name in SKIP or not child.is_dir():
            continue
        yield from walk(child, depth + 1)


def main() -> int:
    roots = [pathlib.Path(argument) for argument in sys.argv[1:]] or [pathlib.Path(".")]
    reports = find_reports(roots)
    if not reports:
        print("CRASH_FILE none")
        return 0
    newest = max(reports, key=lambda path: path.stat().st_mtime)
    print(f"CRASH_FILE {newest}")
    lines = newest.read_text(errors="replace").splitlines()
    printed = 0
    for line in lines:
        if not interesting(line):
            continue
        print("CRASH_LINE " + line.strip()[:220])
        printed += 1
        if printed >= 40:
            break
    if printed == 0:
        for line in lines[:12]:
            print("CRASH_LINE " + line.strip()[:220])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

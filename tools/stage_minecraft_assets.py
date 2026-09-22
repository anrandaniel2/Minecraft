#!/usr/bin/env python3
"""Stage the complete Minecraft client resource pack inside the Godot project.

The checked-in ``extracted/`` directory is the authoritative 26.3 client
payload. Godot exports only files below its project root, so an export needs a
copy of the *complete* client asset namespace under ``godot_extension``.

The destination is deliberately ignored by Git: it is reproducible from the
versioned client payload and should never create a duplicate resource pack in
the repository history.
"""

from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = REPOSITORY_ROOT / "extracted" / "assets" / "minecraft"
DEFAULT_DESTINATION = REPOSITORY_ROOT / "godot_extension" / "minecraft_assets" / "minecraft"


def file_count(directory: Path) -> int:
    return sum(1 for path in directory.rglob("*") if path.is_file())


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE, help="Minecraft asset namespace to copy")
    parser.add_argument("--destination", type=Path, default=DEFAULT_DESTINATION, help="Godot resource-pack destination")
    args = parser.parse_args()

    source = args.source.resolve()
    destination = args.destination.resolve()
    if not source.is_dir():
        parser.error(f"Minecraft asset namespace is missing: {source}")
    if destination == source or source in destination.parents:
        parser.error("destination must not be the source directory or a child of it")

    if destination.exists():
        shutil.rmtree(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(source, destination, copy_function=shutil.copy2)

    source_files = file_count(source)
    destination_files = file_count(destination)
    if source_files == 0 or destination_files != source_files:
        raise RuntimeError(
            f"incomplete resource staging: source has {source_files} files, "
            f"destination has {destination_files}"
        )

    print(f"Staged {destination_files:,} Minecraft resource-pack files")
    print(f"  source:      {source}")
    print(f"  destination: {destination}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

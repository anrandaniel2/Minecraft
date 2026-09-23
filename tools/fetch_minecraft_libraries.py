#!/usr/bin/env python3
"""Download the Minecraft 26.3 runtime libraries required by the extracted client.

The lock file is the Linux x86_64 subset of the 26.3 version manifest. Class
jars go on the native-image classpath. Native jars are extracted for LWJGL, but
their bundled libSDL3 is discarded so the Godot viewport stub remains the SDL
that Window loads.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import shutil
import ssl
import urllib.request
import zipfile


def download(url: str, destination: pathlib.Path, expected_sha1: str, size: int) -> None:
    if destination.is_file() and destination.stat().st_size == size:
        digest = hashlib.sha1(destination.read_bytes()).hexdigest()
        if digest == expected_sha1:
            print(f"cached {destination.name}")
            return
    destination.parent.mkdir(parents=True, exist_ok=True)
    print(f"fetch {url}")
    request = urllib.request.Request(url, headers={"User-Agent": "minecraft-godot-native-image"})
    with urllib.request.urlopen(request, context=ssl.create_default_context(), timeout=120) as response:
        destination.write_bytes(response.read())
    digest = hashlib.sha1(destination.read_bytes()).hexdigest()
    if digest != expected_sha1:
        raise SystemExit(f"sha1 mismatch for {destination}: {digest} != {expected_sha1}")


def extract_natives(jar_path: pathlib.Path, natives_dir: pathlib.Path) -> None:
    with zipfile.ZipFile(jar_path) as archive:
        for info in archive.infolist():
            if info.is_dir() or not info.filename.endswith(".so"):
                continue
            name = pathlib.PurePosixPath(info.filename).name
            if name.startswith("libSDL"):
                print(f"skip bundled {name} from {jar_path.name}")
                continue
            target = natives_dir / name
            target.write_bytes(archive.read(info))
            target.chmod(0o755)
            print(f"extracted {name}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--lock",
        type=pathlib.Path,
        default=pathlib.Path("godot_extension/native-image/26.3-libraries.json"),
    )
    parser.add_argument(
        "--libraries",
        type=pathlib.Path,
        default=pathlib.Path("godot_extension/native-image/libraries"),
    )
    parser.add_argument(
        "--natives",
        type=pathlib.Path,
        default=pathlib.Path("godot_extension/bin/natives"),
    )
    parser.add_argument(
        "--sdl-stub",
        type=pathlib.Path,
        default=pathlib.Path("godot_extension/bin/libSDL3.so"),
    )
    args = parser.parse_args()
    lock = json.loads(args.lock.read_text())
    if lock.get("version") != "26.3":
        raise SystemExit("library lock is not for Minecraft 26.3")
    classpath = []
    args.libraries.mkdir(parents=True, exist_ok=True)
    args.natives.mkdir(parents=True, exist_ok=True)
    for library in lock["libraries"]:
        destination = args.libraries / pathlib.PurePosixPath(library["path"]).name
        download(library["url"], destination, library["sha1"], library["size"])
        if library["native"]:
            extract_natives(destination, args.natives)
        else:
            classpath.append(destination.resolve())
    if args.sdl_stub.is_file():
        stub = args.natives / "libSDL3.so"
        shutil.copy2(args.sdl_stub, stub)
        stub.chmod(0o755)
        print(f"installed SDL stub at {stub}")
    classpath_file = args.libraries / "classpath.txt"
    classpath_file.write_text("\n".join(str(path) for path in classpath) + "\n")
    print(f"wrote {classpath_file} ({len(classpath)} class jars)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

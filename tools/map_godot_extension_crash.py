#!/usr/bin/env python3
"""Map Godot crash offsets in libminecraft_godot.so to local symbols."""

import re
import subprocess
import sys


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: map_godot_extension_crash.py LOG LIBRARY", file=sys.stderr)
        return 2
    log_path, library = sys.argv[1:]
    log = open(log_path, "r", errors="replace").read()
    offsets = sorted(
        {int(item, 16) for item in re.findall(r"libminecraft_godot\.so\+([0-9a-fA-F]+)", log)}
    )
    symbols = []
    for line in subprocess.check_output(["nm", "-n", library], text=True, errors="replace").splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[1] in "tT":
            symbols.append((int(parts[0], 16), parts[2]))
    if not offsets:
        print("no extension crash offsets")
        return 0
    for offset in offsets:
        previous = None
        for address, name in symbols:
            if address > offset:
                print(f"+{offset:x} inside {previous}")
                break
            previous = f"{name}+{address:x}"
        else:
            print(f"+{offset:x} after {previous}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

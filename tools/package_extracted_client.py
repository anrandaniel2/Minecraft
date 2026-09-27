#!/usr/bin/env python3
"""Pack the extracted client for native-image without broken package-info classes."""

from __future__ import annotations

import argparse
import pathlib
import zipfile


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=pathlib.Path, default=pathlib.Path("extracted"))
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    written = 0
    skipped = 0
    with zipfile.ZipFile(args.output, "w") as archive:
        for path in args.source.rglob("*"):
            if not path.is_file():
                continue
            relative = path.relative_to(args.source).as_posix()
            if relative.startswith("META-INF/") or relative.endswith("package-info.class"):
                skipped += 1
                continue
            archive.write(path, relative)
            written += 1
    print(f"wrote {args.output} ({written} files, skipped {skipped})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

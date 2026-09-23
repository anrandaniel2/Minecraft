#!/usr/bin/env python3
"""Print native-image failure lines as GitHub Actions error annotations."""

from __future__ import annotations

import pathlib
import sys

TOKENS = ("Error:", "error:", "Exception", "Fatal", "Caused by", "unknown option", "Missing")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: report_native_image_failure.py LOG", file=sys.stderr)
        return 2
    lines = pathlib.Path(sys.argv[1]).read_text(errors="replace").splitlines()
    picked = [line for line in lines if any(token in line for token in TOKENS)]
    selected = picked[-20:] or lines[-20:]
    print("::error::extracted client native-image failed")
    for line in selected:
        sanitized = line.replace("\r", "").replace("%", "%%")[:400]
        print(f"::error::{sanitized}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

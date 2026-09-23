#!/usr/bin/env python3
"""Print the native-image log tail as one GitHub Actions error annotation.

GitHub keeps only the first few workflow annotations. Emitting one line per
log row hid the real failure behind Graal's recommendations banner.
"""

from __future__ import annotations

import pathlib
import sys

TAIL_LINES = 30
MAX_CHARS = 3500


def sanitize(text: str) -> str:
    return (
        text.replace("\r", "")
        .replace("\n", " ")
        .replace("%", "%%")
        .replace("::", " ")
    )


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: report_native_image_failure.py LOG", file=sys.stderr)
        return 2
    lines = pathlib.Path(sys.argv[1]).read_text(errors="replace").splitlines()
    tail = [sanitize(line)[:240] for line in lines[-TAIL_LINES:]]
    message = "TAIL " + " || ".join(tail)
    if len(message) > MAX_CHARS:
        message = message[-MAX_CHARS:]
    print(f"::error::{message}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

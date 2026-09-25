#!/usr/bin/env python3
"""Print the native-image log tail as one GitHub Actions error annotation.

GitHub keeps only the first few workflow annotations. Emitting one line per
log row hid the real failure behind Graal's recommendations banner.
"""

from __future__ import annotations

import pathlib
import sys

TAIL_LINES = 50
MAX_CHARS = 3500
# A mixed tail of JAVA_GUI_WAIT lines hid the loading-screen log. These markers
# are kept even when they are older than the last 50 rows.
DIAGNOSTIC_MARKERS = (
    "MINECRAFT_GD_CLIENT",
    "MINECRAFT_GD_RELOAD",
    "MINECRAFT_GD_STACK",
    "JAVA_GUI_MISSING",
    "JAVA_GUI_COMMANDS",
)


def sanitize(text: str) -> str:
    return (
        text.replace("\r", "")
        .replace("\n", " ")
        .replace("%", "%%")
        .replace("::", " ")
    )


def diagnostic_lines(lines: list[str]) -> list[str]:
    selected: list[str] = []
    for marker in DIAGNOSTIC_MARKERS:
        matched = [line for line in lines if marker in line]
        selected.extend(matched[-8:])
    return selected


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: report_native_image_failure.py LOG", file=sys.stderr)
        return 2
    lines = pathlib.Path(sys.argv[1]).read_text(errors="replace").splitlines()
    diagnostics = diagnostic_lines(lines)
    if not diagnostics:
        chosen = lines[-TAIL_LINES:]
    else:
        # Diagnostics go last. The annotation keeps the end of the message,
        # and a mixed JAVA_GUI_WAIT tail must not push them out.
        chosen = lines[-8:] + diagnostics
    tail = [sanitize(line)[:240] for line in chosen]
    message = "TAIL " + " || ".join(tail)
    if len(message) > MAX_CHARS:
        message = message[-MAX_CHARS:]
    print(f"::error::{message}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

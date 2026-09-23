#!/usr/bin/env python3
"""Fix UTF-8 mojibake across website sources using ftfy."""
from __future__ import annotations

import sys
from pathlib import Path

import ftfy

ROOT = Path(__file__).resolve().parents[1]
EXTS = {".html", ".js", ".css", ".mjs", ".json", ".md", ".txt", ".svg"}
SKIP_DIRS = {"node_modules", "dist", ".git"}


def should_skip(rel: Path) -> bool:
    return any(part in SKIP_DIRS for part in rel.parts)


def main() -> int:
    changed = []
    for path in sorted(ROOT.rglob("*")):
        if not path.is_file() or path.suffix.lower() not in EXTS:
            continue
        rel = path.relative_to(ROOT)
        if should_skip(rel):
            continue
        raw = path.read_bytes()
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            text = raw.decode("utf-8", errors="replace")

        fixed = ftfy.fix_text(text)
        if fixed == text:
            continue

        # Preserve existing newline style
        nl = "\r\n" if "\r\n" in text else "\n"
        out = fixed.replace("\r\n", "\n").replace("\n", nl)
        path.write_bytes(out.encode("utf-8"))
        changed.append(rel.as_posix())

    print(f"fixed {len(changed)} files")
    for p in changed:
        print(f"  {p}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

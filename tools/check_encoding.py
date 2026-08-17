"""Fail if double-UTF-8 or euro mojibake remains in site sources."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCAN = [ROOT / 'index.html', *(ROOT / 'src').glob('*.js')]
EURO_JUNK = 'â‚¬'.encode('utf-8')
DOUBLE_E = bytes([0xC3, 0x83, 0xC2, 0xA9])
ARROW_JUNK = 'â†“'.encode('utf-8')


def main() -> int:
    bad = []
    for path in SCAN:
        data = path.read_bytes()
        issues = []
        if DOUBLE_E in data:
            issues.append('double-encoded-e')
        if EURO_JUNK in data:
            issues.append('euro-mojibake')
        if ARROW_JUNK in data:
            issues.append('arrow-mojibake')
        # Ã leftover (U+00C3 as character) often signals mojibake
        text = data.decode('utf-8', errors='replace')
        if 'Ã' in text:
            issues.append(f'A-tilde×{text.count("Ã")}')
        if issues:
            bad.append(f'{path.relative_to(ROOT)}: {", ".join(issues)}')

    if bad:
        print('ENCODING GUARD FAILED')
        for line in bad:
            print(' ', line)
        return 1

    print('ENCODING GUARD OK')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

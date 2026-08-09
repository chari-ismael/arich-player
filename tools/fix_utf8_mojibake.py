"""Repair double-UTF-8 and euro mojibake in website sources."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGETS = [
    ROOT / 'src' / 'config.js',
    ROOT / 'src' / 'i18n.js',
    ROOT / 'index.html',
]

# € UTF-8 misread as cp1252 then re-saved as UTF-8
EURO_JUNK = 'â‚¬'  # U+00E2 U+201A U+00AC
# Common double-encoded sequences (UTF-8 bytes interpreted as latin-1, re-encoded)
DOUBLE_MAP = {
    'Ã©': 'é', 'Ã¨': 'è', 'Ãª': 'ê', 'Ã«': 'ë',
    'Ã ': 'à', 'Ã¡': 'á', 'Ã¢': 'â', 'Ã¤': 'ä',
    'Ã§': 'ç', 'Ã®': 'î', 'Ã¯': 'ï', 'Ã´': 'ô',
    'Ã¶': 'ö', 'Ã¹': 'ù', 'Ã»': 'û', 'Ã¼': 'ü',
    'Ã\u00a0': 'à', 'Ã\u00a9': 'é', 'Ã\u00a8': 'è',
    'Ã\u00aa': 'ê', 'Ã\u00a7': 'ç', 'Ã\u00b4': 'ô',
    'Ã‰': 'É', 'Ã€': 'À', 'Ã‡': 'Ç',
    'Â©': '©', 'Â·': '·', 'Â°': '°', 'Â«': '«', 'Â»': '»',
    'Â€': '€',
    'â€™': '\u2019', 'â€˜': '\u2018', 'â€œ': '\u201c', 'â€': '\u201d',
    'â€”': '—', 'â€“': '–', 'â€¦': '…', 'â†’': '→',
}


def undo_double_utf8(text: str) -> str:
    """If the whole string is double-encoded, reverse once."""
    try:
        return text.encode('latin-1').decode('utf-8')
    except (UnicodeEncodeError, UnicodeDecodeError):
        return text


def fix_text(text: str) -> str:
    # Prefer wholesale undo when it produces fewer mojibake markers
    candidate = undo_double_utf8(text)
    if candidate.count('Ã') < text.count('Ã') and EURO_JUNK not in candidate:
        # wholesale worked for accents; still scrub euro if any slipped
        text = candidate
    else:
        for bad, good in sorted(DOUBLE_MAP.items(), key=lambda x: -len(x[0])):
            text = text.replace(bad, good)
    text = text.replace(EURO_JUNK, '€')
    # Second pass for any remaining double-map leftovers
    for bad, good in sorted(DOUBLE_MAP.items(), key=lambda x: -len(x[0])):
        text = text.replace(bad, good)
    text = text.replace(EURO_JUNK, '€')
    return text


def has_corruption(data: bytes) -> bool:
    if bytes([0xC3, 0x83, 0xC2, 0xA9]) in data:  # double é
        return True
    if EURO_JUNK.encode('utf-8') in data:
        return True
    return False


def main() -> None:
    for path in TARGETS:
        if not path.exists():
            print('skip', path)
            continue
        raw = path.read_bytes()
        text = raw.decode('utf-8')
        fixed = fix_text(text)
        path.write_text(fixed, encoding='utf-8', newline='\n')
        after = path.read_bytes()
        print(
            f'{path.relative_to(ROOT)}: '
            f'corrupt_before={has_corruption(raw)} '
            f'corrupt_after={has_corruption(after)} '
            f'A_tilde={fixed.count("Ã")} euro_junk={fixed.count(EURO_JUNK)}'
        )


if __name__ == '__main__':
    main()

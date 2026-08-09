"""Fix main-branch site encoding so Vite/parse5 can build."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FILES = [ROOT / 'index.html', ROOT / 'src' / 'i18n.js']

MOJIBAKE = {
    'Ã©': 'é', 'Ã¨': 'è', 'Ãª': 'ê', 'Ã«': 'ë',
    'Ã ': 'à', 'Ã¡': 'á', 'Ã¢': 'â', 'Ã¤': 'ä',
    'Ã§': 'ç', 'Ã®': 'î', 'Ã¯': 'ï', 'Ã´': 'ô',
    'Ã¶': 'ö', 'Ã¹': 'ù', 'Ã»': 'û', 'Ã¼': 'ü',
    'Ã‰': 'É', 'Ã€': 'À', 'Ã‡': 'Ç',
    'Â©': '©', 'Â·': '·', 'Â°': '°', 'Â«': '«', 'Â»': '»',
    'â€™': "'", 'â€˜': "'", 'â€œ': '"', 'â€': '"',
    'â€”': '—', 'â€“': '–', 'â€¦': '…', 'â†’': '→',
    'ðŸš€': '',  # emoji junk if any
}


def sanitize(text: str) -> str:
    # Drop C0/C1 controls (except whitespace) — parse5 rejects them
    out = []
    for ch in text:
        o = ord(ch)
        if ch in '\n\r\t' or (o >= 32 and not (0x7F <= o <= 0x9F)):
            out.append(ch)
        elif o == 0x90:
            out.append('-')  # was likely box-drawing in comments
        # else drop
    text = ''.join(out)
    text = text.replace('\ufffd', '')
    for bad, good in sorted(MOJIBAKE.items(), key=lambda x: -len(x[0])):
        text = text.replace(bad, good)
    # Normalize mangled HTML comment banners like "--- HERO ---"
    text = text.replace('----', '---')
    return text


def main() -> None:
    for path in FILES:
        if not path.exists():
            print('skip missing', path)
            continue
        text = path.read_text(encoding='utf-8')
        fixed = sanitize(text)
        illegal = sum(
            1 for c in fixed
            if (ord(c) < 32 and c not in '\n\r\t') or (0x7F <= ord(c) <= 0x9F)
        )
        path.write_text(fixed, encoding='utf-8', newline='\n')
        print(f'{path.name}: illegal={illegal} mojibake_left={fixed.count("Ã")}')


if __name__ == '__main__':
    main()

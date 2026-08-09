import re
from pathlib import Path

DIR = Path(__file__).resolve().parents[1] / 'public'
FIXES = {
    'auth.html': (
        'Connexion et compte ARICH Player — gérez votre licence et vos playlists.',
        'noindex, follow',
    ),
    'manage-playlist.html': (
        'Espace compte ARICH Player — playlists et appareils.',
        'noindex, nofollow',
    ),
    'admin.html': ('Administration ARICH Player.', 'noindex, nofollow'),
    'tv-login.html': ('Connexion TV ARICH Player.', 'noindex, follow'),
    'tv-pair.html': ('Associer une TV à ARICH Player.', 'noindex, follow'),
    'watch.html': ('Watch Together — ARICH Player.', 'noindex, nofollow'),
    'privacy-policy.html': (
        'Politique de confidentialité d’ARICH Player. Données, cookies, droits RGPD.',
        'index, follow',
    ),
    'data-deletion.html': (
        'Demande de suppression des données personnelles ARICH Player (RGPD).',
        'index, follow',
    ),
}

for name, (desc, robots) in FIXES.items():
    path = DIR / name
    text = path.read_text(encoding='utf-8')
    text = re.sub(
        r'<meta name="description" content="[^"]*"\s*/?>',
        f'<meta name="description" content="{desc}" />',
        text,
        count=1,
    )
    text = re.sub(
        r'<meta name="robots" content="[^"]*"\s*/?>',
        f'<meta name="robots" content="{robots}" />',
        text,
        count=1,
    )
    path.write_text(text, encoding='utf-8')
    print('fixed', name)

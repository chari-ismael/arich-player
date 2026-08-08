from PIL import Image, ImageDraw, ImageFont
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / 'public'
src = Image.open(ROOT / 'logo-fg.png').convert('RGBA')


def square_icon(size, pad_ratio=0.12):
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    inner = int(size * (1 - pad_ratio * 2))
    logo = src.copy()
    logo.thumbnail((inner, inner), Image.Resampling.LANCZOS)
    x = (size - logo.width) // 2
    y = (size - logo.height) // 2
    canvas.paste(logo, (x, y), logo)
    return canvas


for s in (16, 32, 48, 180, 192, 512):
    im = square_icon(s, pad_ratio=0.1 if s >= 180 else 0.08)
    if s == 16:
        im.save(ROOT / 'favicon-16x16.png', optimize=True)
    elif s == 32:
        im.save(ROOT / 'favicon-32x32.png', optimize=True)
        im.save(ROOT / 'favicon.png', optimize=True)
    elif s == 48:
        im.save(ROOT / 'favicon-48x48.png', optimize=True)
    elif s == 180:
        bg = Image.new('RGBA', (s, s), (13, 16, 23, 255))
        logo = square_icon(s, 0.14)
        bg.alpha_composite(logo)
        bg.convert('RGB').save(ROOT / 'apple-touch-icon.png', optimize=True, quality=92)
    elif s == 192:
        im.save(ROOT / 'icon-192.png', optimize=True)
    elif s == 512:
        im.save(ROOT / 'icon-512.png', optimize=True)

icos = [square_icon(s) for s in (16, 32, 48)]
icos[0].save(ROOT / 'favicon.ico', format='ICO', sizes=[(16, 16), (32, 32), (48, 48)])

W, H = 1200, 630
og = Image.new('RGB', (W, H), (13, 16, 23))
for r, a in ((420, 28), (280, 40), (160, 55)):
    layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    cx, cy = 280, 315
    ld.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(197, 138, 42, a))
    og = Image.alpha_composite(og.convert('RGBA'), layer).convert('RGB')

draw = ImageDraw.Draw(og)
mark = square_icon(280, 0.08)
og.paste(mark, (110, (H - mark.height) // 2), mark)
draw = ImageDraw.Draw(og)

font_bold = font_reg = font_small = ImageFont.load_default()
for bold, reg in (
    (r'C:\Windows\Fonts\segoeuib.ttf', r'C:\Windows\Fonts\segoeui.ttf'),
    (r'C:\Windows\Fonts\arialbd.ttf', r'C:\Windows\Fonts\arial.ttf'),
):
    if Path(bold).exists() and Path(reg).exists():
        font_bold = ImageFont.truetype(bold, 72)
        font_reg = ImageFont.truetype(reg, 34)
        font_small = ImageFont.truetype(reg, 26)
        break

tx = 470
draw.rectangle([tx, 170, tx + 64, 176], fill=(197, 138, 42))
draw.text((tx, 190), 'ARICH Player', fill=(240, 239, 236), font=font_bold)
draw.text((tx, 290), 'Le cinéma, chez vous.', fill=(212, 160, 74), font=font_reg)
draw.text((tx, 345), 'Sans le bruit.', fill=(240, 239, 236), font=font_reg)
draw.text(
    (tx, 430),
    'Lecteur IPTV · Android & Android TV · Xtream & M3U',
    fill=(160, 158, 152),
    font=font_small,
)

og.save(ROOT / 'og-image.jpg', quality=88, optimize=True)
og.save(ROOT / 'og-image.png', optimize=True)
print('generated SEO assets in', ROOT)

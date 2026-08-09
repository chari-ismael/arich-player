from PIL import Image, ImageDraw, ImageFont
from pathlib import Path

out = Path(r"c:\Users\Ismael\iptv_player\website\public\email")
mark = Image.open(out / "arich-mark.png").convert("RGBA")

size = 240
radius = 48
bg = (13, 16, 23, 255)  # #0D1017

mask = Image.new("L", (size, size), 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
base = Image.new("RGBA", (size, size), bg)
plate = Image.composite(base, Image.new("RGBA", (size, size), (0, 0, 0, 0)), mask)

inset = 20
inner = size - inset * 2
m = mark.copy()
m.thumbnail((inner, inner), Image.Resampling.LANCZOS)
ox = (size - m.width) // 2
oy = (size - m.height) // 2
plate.paste(m, (ox, oy), m)

icon_path = out / "arich-email-icon.png"
plate.convert("RGB").save(icon_path, "PNG", optimize=True)
print("wrote", icon_path, icon_path.stat().st_size)

bw, bh = 640, 200
banner = Image.new("RGB", (bw, bh), (240, 239, 236))
icon = plate.resize((120, 120), Image.Resampling.LANCZOS).convert("RGB")
ix, iy = 48, (bh - 120) // 2
banner.paste(icon, (ix, iy))

draw = ImageDraw.Draw(banner)
font = font_sm = None
for fp in (
    r"C:\Windows\Fonts\segoeuib.ttf",
    r"C:\Windows\Fonts\arialbd.ttf",
    r"C:\Windows\Fonts\arial.ttf",
):
    try:
        font = ImageFont.truetype(fp, 54)
        font_sm = ImageFont.truetype(fp, 22)
        break
    except OSError:
        pass
if font is None:
    font = font_sm = ImageFont.load_default()

text_x = ix + 120 + 28
draw.text((text_x, iy + 22), "ARICH", fill=(13, 16, 23), font=font)
draw.text((text_x, iy + 86), "Player", fill=(138, 133, 124), font=font_sm)

banner_path = out / "arich-email-header.png"
banner.save(banner_path, "PNG", optimize=True)
print("wrote", banner_path, banner_path.stat().st_size)

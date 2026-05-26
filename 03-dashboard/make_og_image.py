"""Generate the 1200×630 PNG used as the dashboard's Open Graph preview.

LinkedIn, Twitter, WhatsApp, Discord, Slack, etc. all read the OG image when a
link is shared. Standard size is 1200×630 px.

Usage:
    pip install Pillow
    python make_og_image.py
    # → writes og-image.png next to this script

To refresh the live dashboard's preview, copy the new PNG to the Netlify-watched
repo root and redeploy (`update_netlify_split.sh` already handles that copy).
"""
import os
from PIL import Image, ImageDraw, ImageFont

OUT = os.path.join(os.path.dirname(__file__) or '.', 'og-image.png')
W, H = 1200, 630
INK    = '#0f1e2d'
MUTED  = '#64748b'
ACCENT = '#c8202b'


def load_font(size: int, bold: bool = False):
    """Best-effort font loader. Falls back to PIL's default if no TTF found."""
    candidates_bold = [
        '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
        '/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf',
        '/System/Library/Fonts/Supplemental/Arial Bold.ttf',
    ]
    candidates_reg = [
        '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
        '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf',
        '/System/Library/Fonts/Supplemental/Arial.ttf',
    ]
    for p in (candidates_bold if bold else candidates_reg):
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def main():
    img = Image.new('RGB', (W, H), '#ffffff')
    d = ImageDraw.Draw(img)

    # Top stripe — Indonesia red
    d.rectangle([(0, 0), (W, 8)], fill=ACCENT)

    eyebrow = load_font(20, True)
    d.text((72, 88), 'SEKILAS KETENAGAKERJAAN INDONESIA',
           fill=MUTED, font=eyebrow, spacing=8)

    title = load_font(58, True)
    d.text((72, 132), "Two decades of Indonesia's", fill=INK, font=title)
    d.text((72, 202), "labour market — in one place.", fill=INK, font=title)

    sub = load_font(30, True)
    d.text((72, 296), 'Dasbor interaktif pasar tenaga kerja Indonesia, 2002–2024.',
           fill=INK, font=sub)

    hi = load_font(22)
    d.text((72, 360), 'Sakernas BPS · 17 sektor · 34 provinsi · 22 tahun snapshot',
           fill=MUTED, font=hi)
    d.text((72, 396), 'Upah · informalitas · okupasi · transformasi struktural',
           fill=MUTED, font=hi)

    foot_label = load_font(16, True)
    foot_url   = load_font(22, True)
    d.text((72, H - 92), 'EXPLORE', fill=ACCENT, font=foot_label)
    d.text((72, H - 62), 'ketenagakerjaan-indonesia.netlify.app',
           fill=INK, font=foot_url)

    # Right side: big "5" with description
    num = load_font(120, True)
    small_b = load_font(22, True)
    small   = load_font(20)
    nx = 880
    d.text((nx,      H - 220), '5',                  fill=ACCENT, font=num)
    d.text((nx + 96, H - 160), 'snapshot years',      fill=INK,   font=small_b)
    d.text((nx + 96, H - 130), 'with ICLS-17',        fill=MUTED, font=small)
    d.text((nx + 96, H - 105), 'informality data',    fill=MUTED, font=small)

    d.line([(72, H - 32), (W - 72, H - 32)], fill='#cbd5e1', width=1)

    img.save(OUT, 'PNG', optimize=True)
    print(f'Wrote {OUT} ({os.path.getsize(OUT) / 1024:.1f} KB)')


if __name__ == '__main__':
    main()

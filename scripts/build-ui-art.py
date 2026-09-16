"""Rebuild UI98's original, local-only wood/paper textures and inked brass icons.
Build-time dependencies: Pillow, numpy, cairosvg. No runtime dependency or web asset.
Usage: python scripts/build-ui-art.py
PNG/VTEX files are committed so installation does not require Python packages.
"""
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
import cairosvg

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'content/dota_addons/dota2_rpg/panorama/images/custom_game/fantasy_ui'
OUT.mkdir(parents=True, exist_ok=True)
rng = np.random.default_rng(98)
# Horizontal walnut grain, gently wavy growth rings and dark seams. Tileable X.
w, h = 1024, 512
y, x = np.mgrid[:h, :w].astype(float)
warp = y + 3*np.sin(x*2*np.pi/w) + 1.8*np.sin(x*6*np.pi/w + y*.04)
gr = np.sin(warp*1.9 + 2*np.sin(warp*.11))
fine = np.sin(warp*5.7 + np.sin(x*8*np.pi/w))
noise = rng.normal(0, 1.7, (h,w))
shade = 3*gr + 1.5*fine + 2*np.sin(warp*.08) + noise
wood = np.stack([48+shade*1.4, 30+shade*.93, 19+shade*.59],axis=-1)
for seam in [0,128,256,384,511]:
    wood[max(0,seam-1):seam+2] *= .5
    if seam+3 < h: wood[seam+2:seam+3] += 6
Image.fromarray(np.clip(wood,0,255).astype('uint8')).save(OUT/'wood.png')
y, x = np.mgrid[:512,:512].astype(float)
noise = rng.normal(0,1.8,(512,512)) + 1.3*np.sin(x*.03+y*.09)
edge = np.maximum(abs(x-256),abs(y-256))/256
shade = noise - edge**8*12
paper = np.stack([203+shade,179+shade,136+shade],axis=-1)
Image.fromarray(np.clip(paper,0,255).astype('uint8')).save(OUT/'parchment.png')
# Source paths are intentionally slightly irregular: a hand-inked brass look,
# not emoji glyphs, external icon fonts or screenshots with baked-in labels.
paths = {
 'trigger': 'M18 42 L17 19 Q32 9 47 19 L46 42 L37 51 L36 30 L28 30 L27 51 Z M20 23 L27 25 M37 25 L44 23 M32 13 L32 24',
 'target': 'M32 9 L32 20 M32 44 L32 55 M9 32 L20 32 M44 32 L55 32 M48 32 A16 16 0 1 1 16 32 A16 16 0 1 1 48 32 M36 32 A4 4 0 1 1 28 32 A4 4 0 1 1 36 32',
 'priority': 'M18 53 L18 12 M20 14 Q30 8 40 16 L50 14 L46 33 Q34 38 21 30 M13 53 L24 53',
 'action': 'M32 32 Q12 10 37 12 Q54 14 50 29 M32 32 Q56 14 53 38 Q49 56 34 51 M32 32 Q52 55 27 53 Q8 49 14 34 M32 32 Q10 50 11 25 Q15 8 29 14',
 'trophy': 'M22 13 L43 13 L41 31 Q39 39 32 39 Q24 38 23 31 Z M22 17 L13 17 L15 27 Q17 32 24 32 M43 17 L51 17 L49 27 Q47 32 40 32 M32 39 L32 48 M24 48 L40 48 L42 53 L22 53 Z',
 'hourglass': 'M21 11 L43 11 M21 53 L43 53 M23 12 L24 22 Q25 27 32 32 Q40 37 40 44 L40 52 M41 12 L40 22 Q38 28 32 32 Q24 37 24 44 L24 52 M25 19 L39 19 M26 46 L32 39 L38 46 Z M12 23 L19 27 M9 30 L18 32 M12 37 L19 36',
 'scroll': 'M17 14 Q9 14 10 23 L17 23 M17 14 L45 14 Q51 14 50 23 L44 23 L44 45 Q45 53 53 49 Q56 43 50 42 L22 42 Q15 42 16 49 M17 14 L16 46 M21 23 L39 23 M21 29 L37 29 M21 35 L33 35',
 'health': 'M32 51 L14 33 Q4 15 20 14 Q28 13 32 22 Q38 9 48 16 Q60 26 47 38 Z M18 31 L25 31 L28 25 L33 39 L38 29 L46 29',
 'mana': 'M32 10 Q24 25 18 34 Q12 53 32 54 Q53 53 47 35 Z M23 36 Q18 45 29 47',
 'battle': 'M15 12 L35 31 L32 35 L12 16 Z M49 12 L29 32 L33 36 L52 16 Z M22 35 L33 46 M18 48 L27 40 M31 46 L36 41 M41 35 L30 47 M38 42 L46 51 M41 33 L46 38',
 'clock': 'M51 33 A19 19 0 1 1 13 33 A19 19 0 1 1 51 33 M32 21 L32 34 L42 39 M32 9 L32 15 M27 9 L37 9',
 'rune': 'M32 8 L52 31 L32 56 L12 31 Z M32 18 L42 31 L32 45 L22 31 Z M32 25 L32 37 M27 31 L37 31',
 'crown': 'M14 23 L23 31 L32 15 L42 31 L51 22 L45 46 L19 46 Z M20 40 L45 40 M30 16 A2 2 0 1 1 34 16 A2 2 0 1 1 30 16',
}
for name, path in paths.items():
    source = ('<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 64 64">'
        '<defs><linearGradient id="ink" x2="0" y2="1"><stop stop-color="#f6d892"/>'
        '<stop offset="1" stop-color="#b98643"/></linearGradient></defs>'
        '<path d="'+path+'" fill="none" stroke="#130c06" stroke-width="5.3" stroke-linecap="round" stroke-linejoin="round"/>'
        '<path d="'+path+'" fill="none" stroke="url(#ink)" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"/>'
        '<path d="'+path+'" fill="none" stroke="#ffe8b1" opacity=".32" transform="translate(-.45,-.5)" stroke-width=".7" stroke-linecap="round"/>'
        '</svg>')
    (OUT/(name+'.svg')).write_text(source, encoding='utf-8')
    cairosvg.svg2png(bytestring=source.encode(), write_to=str(OUT/(name+'.png')), output_width=128, output_height=128)
# A transparent bronze corner: four rotations are made once, not per frame.
im = Image.new('RGBA',(128,128)); d=ImageDraw.Draw(im)
d.line([(5,123),(5,5),(123,5)],fill='#160f09',width=10)
d.line([(5,123),(5,5),(123,5)],fill='#a1773e',width=4)
d.line([(14,115),(14,14),(115,14)],fill='#d4ad65',width=2)
d.polygon([(5,39),(39,5),(36,27),(27,36)],fill='#b58b49',outline='#efcf8c')
d.polygon([(14,14),(32,16),(21,28)],fill='#31534c',outline='#dabf7c')
for i,n in enumerate(['tl','bl','br','tr']): im.rotate(i*90).save(OUT/('corner_'+n+'.png'))
# Explicit Source 2 texture descriptors, matching the repository's existing format.
template=(OUT.parent/'rpg_loading_art_png.vtex').read_text(encoding='utf-8')
for png in OUT.glob('*.png'):
    (OUT/(png.stem+'_png.vtex')).write_text(template.replace('./rpg_loading_art.png','./'+png.name),encoding='utf-8')
print('Wrote',len(list(OUT.glob('*.png'))),'PNG assets and matching VTEX descriptors to',OUT)

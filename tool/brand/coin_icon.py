"""Generate the Genzeb coin icon SVGs (glyphs baked in as paths).

Styled after the Ethiopian 10-cent coin: brass, raised rim, struck ge,
meadow, legend along the bottom arc. macOS only (reads the Kefa font).

    python3 -m venv .venv && .venv/bin/pip install fonttools
    .venv/bin/python tool/brand/coin_icon.py assets/icon
    # render each SVG to a 1024 PNG with headless Chrome, e.g.
    chrome --headless=new --hide-scrollbars --default-background-color=00000000 \
      --window-size=1024,1024 --screenshot=icon.png file://$PWD/assets/icon/genzeb_icon.svg
    dart run flutter_launcher_icons

tool/brand/feature_graphic.html renders the 1024x500 Play feature graphic
(--window-size=1024,500 --allow-file-access-from-files).
"""
import math, random, sys, os
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.boundsPen import BoundsPen

OUT = sys.argv[1] if len(sys.argv) > 1 else '.'
font = TTFont('/System/Library/Fonts/Supplemental/KefaIII.ttf')
gs = font.getGlyphSet()
cmap = font.getBestCmap()


def glyph(ch):
    name = cmap[ord(ch)]
    pen = SVGPathPen(gs)
    gs[name].draw(pen)
    bp = BoundsPen(gs)
    gs[name].draw(bp)
    return pen.getCommands(), bp.bounds, gs[name].width


def placed(ch, cx, cy, height):
    """Glyph path centred on (cx, cy) with the given ink height."""
    d, (x0, y0, x1, y1), _ = glyph(ch)
    s = height / (y1 - y0)
    tx = cx - (x0 + x1) / 2 * s
    ty = cy + (y0 + y1) / 2 * s
    return f'<path d="{d}" transform="translate({tx:.1f} {ty:.1f}) scale({s:.4f} {-s:.4f})"/>'


def arc_text(text, radius, size, centre_deg=90, spacing=1.08):
    """Lay glyphs along the bottom arc, reading left to right, upright."""
    widths = []
    for ch in text:
        _, (x0, y0, x1, y1), adv = glyph(ch)
        widths.append(adv * size / 1000 * spacing)
    total = sum(widths)
    # angle measured clockwise from +x; bottom of circle is 90deg. Text runs
    # right-to-left in angle so it reads left to right along the bottom.
    ang = centre_deg + math.degrees(total / 2 / radius)
    out = []
    for ch, w in zip(text, widths):
        mid = ang - math.degrees(w / 2 / radius)
        a = math.radians(mid)
        x, y = radius * math.cos(a), radius * math.sin(a)
        rot = mid - 90
        d, (x0, y0, x1, y1), adv = glyph(ch)
        s = size / 1000
        out.append(
            f'<path d="{d}" transform="translate({x:.1f} {y:.1f}) rotate({rot:.2f}) '
            f'translate({-adv * s / 2:.1f} 0) scale({s:.4f} {-s:.4f})"/>')
        ang -= math.degrees(w / radius)
    return '\n'.join(out)


def grass(seed=11):
    """Tufts fanning out along a low arc, like the meadow on the 10-cent coin."""
    rnd = random.Random(seed)
    blades = []
    for deg in range(35, 146, 11):
        a = math.radians(deg)
        bx, by = 300 * math.cos(a), 300 * math.sin(a) - 95
        k = 0.65 + 0.35 * math.sin(a)
        n = rnd.randint(5, 7)
        for i in range(n):
            t = (i - (n - 1) / 2) / ((n - 1) / 2)
            h = rnd.uniform(55, 95) * k * (1 - 0.35 * abs(t))
            w = rnd.uniform(3.2, 4.8)
            x = bx + t * 14 + rnd.uniform(-3, 3)
            tipx, tipy = x + t * 34 + rnd.uniform(-6, 6), by - h
            cx, cy = x + t * 4, by - h * 0.6
            blades.append(
                f'<path d="M{x - w:.1f} {by:.1f} Q{cx - w * 0.4:.1f} {cy:.1f} {tipx:.1f} {tipy:.1f} '
                f'Q{cx + w * 0.4:.1f} {cy:.1f} {x + w:.1f} {by:.1f} Z"/>')
    return '\n'.join(blades)


def coin(extra=''):
    ge = placed('ገ', 8, -40, 430)
    legend = arc_text('ገንዘብ', 342, 104, spacing=1.12)
    blades = grass()
    lathe = '\n'.join(
        f'<circle r="{r}" fill="none" stroke="{"#FFF1C4" if i % 2 else "#7A5418"}" '
        f'stroke-width="1" opacity=".07"/>' for i, r in enumerate(range(20, 392, 6)))
    return f"""
<circle r="440" fill="url(#rim)"/>
<circle r="440" fill="none" stroke="url(#rimEdge)" stroke-width="6"/>
<circle r="404" fill="url(#bevel)"/>
<circle r="394" fill="url(#field)"/>
<g>{lathe}</g>
<g filter="url(#sunk)" fill="#C8963C"><circle r="366" fill="none" stroke="#C8963C" stroke-width="5"/></g>
<g filter="url(#struckFine)" fill="#D9A94C">{blades}</g>
<g filter="url(#struckFine)" fill="#D9A94C" stroke="#D9A94C" stroke-width="14">{legend}</g>
{extra}
<g filter="url(#struck)" fill="#E2B458" stroke="#E2B458" stroke-width="26">{ge}</g>
<circle r="394" fill="url(#sheen)" style="mix-blend-mode:screen"/>
<circle r="440" fill="url(#rimSheen)" style="mix-blend-mode:screen"/>
<g transform="translate(-248 -300)" fill="#FFFDF2">
  <path d="M0 -58 C4 -8 8 -4 58 0 C8 4 4 8 0 58 C-4 8 -8 4 -58 0 C-8 -4 -4 -8 0 -58Z" opacity=".95"/>
  <circle r="10"/>
</g>
"""


def struck(fid, blur, scale, shadow):
    """Sculpted relief: lit from the top-left like a coin under a lamp."""
    return f"""<filter id="{fid}" x="-20%" y="-20%" width="140%" height="140%" color-interpolation-filters="sRGB">
 <feGaussianBlur in="SourceAlpha" stdDeviation="{blur}" result="bump"/>
 <feDiffuseLighting in="bump" surfaceScale="{scale}" diffuseConstant="1.15" lighting-color="#FFFFFF" result="diff">
  <feDistantLight azimuth="225" elevation="42"/></feDiffuseLighting>
 <feSpecularLighting in="bump" surfaceScale="{scale}" specularConstant="1.3" specularExponent="18" lighting-color="#FFF6D6" result="spec">
  <feDistantLight azimuth="225" elevation="38"/></feSpecularLighting>
 <feComposite in="SourceGraphic" in2="diff" operator="arithmetic" k1="1.35" result="lit"/>
 <feComposite in="lit" in2="SourceAlpha" operator="in" result="litIn"/>
 <feComposite in="spec" in2="SourceAlpha" operator="in" result="specIn"/>
 <feOffset in="bump" dx="{shadow}" dy="{shadow * 1.3:.1f}" result="off"/>
 <feFlood flood-color="#3E2806" flood-opacity=".75"/>
 <feComposite in2="off" operator="in" result="shadow"/>
 <feMerge><feMergeNode in="shadow"/><feMergeNode in="litIn"/><feMergeNode in="specIn"/></feMerge>
</filter>"""


DEFS = f"""<defs>
<linearGradient id="rim" x1=".15" y1=".05" x2=".85" y2=".95">
 <stop offset="0" stop-color="#FFF0B8"/><stop offset=".3" stop-color="#E7BC5E"/>
 <stop offset=".62" stop-color="#B7862F"/><stop offset=".8" stop-color="#F0CD78"/>
 <stop offset="1" stop-color="#6A4510"/></linearGradient>
<linearGradient id="rimEdge" x1="0" y1="0" x2="1" y2="1">
 <stop offset="0" stop-color="#FFF8DC"/><stop offset=".5" stop-color="#A57526"/>
 <stop offset="1" stop-color="#4A300A"/></linearGradient>
<linearGradient id="bevel" x1="0" y1="0" x2="1" y2="1">
 <stop offset="0" stop-color="#5E3F0E"/><stop offset=".5" stop-color="#B8893A"/>
 <stop offset="1" stop-color="#FFE6A0"/></linearGradient>
<radialGradient id="field" cx=".36" cy=".3" r=".8">
 <stop offset="0" stop-color="#F4CF74"/><stop offset=".45" stop-color="#D9A546"/>
 <stop offset=".8" stop-color="#B7832E"/><stop offset="1" stop-color="#946622"/></radialGradient>
<linearGradient id="sheen" x1="0" y1="0" x2="1" y2="1">
 <stop offset="0" stop-color="#FFFFFF" stop-opacity="0"/><stop offset=".28" stop-color="#FFFFFF" stop-opacity="0"/>
 <stop offset=".36" stop-color="#FFF6D8" stop-opacity=".32"/><stop offset=".44" stop-color="#FFFFFF" stop-opacity="0"/>
 <stop offset=".52" stop-color="#FFF6D8" stop-opacity=".14"/><stop offset=".58" stop-color="#FFFFFF" stop-opacity="0"/>
 </linearGradient>
<radialGradient id="rimSheen" cx=".3" cy=".22" r=".35">
 <stop offset="0" stop-color="#FFFFFF" stop-opacity=".35"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient>
<radialGradient id="glow" cx=".5" cy=".46" r=".62">
 <stop offset="0" stop-color="#7C86FF"/><stop offset=".55" stop-color="#4E5AE8"/>
 <stop offset="1" stop-color="#3440C4"/></radialGradient>
{struck('struck', 7, 9, 7)}
{struck('struckFine', 2.5, 5, 3)}
<filter id="sunk" x="-5%" y="-5%" width="110%" height="110%">
 <feGaussianBlur in="SourceAlpha" stdDeviation="2" result="b"/>
 <feDiffuseLighting in="b" surfaceScale="-4" diffuseConstant="1.1" lighting-color="#FFF">
  <feDistantLight azimuth="225" elevation="40"/></feDiffuseLighting>
 <feComposite in="SourceGraphic" operator="arithmetic" k1="1.3"/>
 <feComposite in2="SourceAlpha" operator="in"/>
</filter>
<filter id="drop" x="-20%" y="-20%" width="140%" height="140%">
 <feGaussianBlur stdDeviation="22"/></filter>
</defs>"""


def svg(body, bg=None, size=1024):
    rect = f'<rect width="{size}" height="{size}" fill="{bg}"/>' if bg else ''
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" '
            f'viewBox="0 0 {size} {size}">{DEFS}{rect}{body}</svg>\n')


def shadow(r, dy):
    return (f'<circle cx="512" cy="{512 + dy}" r="{r}" fill="#141A66" opacity=".6" filter="url(#drop)"/>')


c = coin()
os.makedirs(OUT, exist_ok=True)
# Full icon: coin on a lit indigo field (iOS, legacy Android, Play Store).
open(f'{OUT}/genzeb_icon.svg', 'w').write(
    svg(shadow(436, 26) + f'<g transform="translate(512 512)">{c}</g>', 'url(#glow)'))
# Adaptive foreground: coin inside the 66/108 safe circle (r ~ 313 of 1024).
k = 312 / 440
open(f'{OUT}/genzeb_icon_foreground.svg', 'w').write(
    svg(shadow(436 * k, 18) + f'<g transform="translate(512 512) scale({k:.4f})">{c}</g>'))
# Bare coin, transparent, for in-app / marketing use.
open(f'{OUT}/genzeb_coin.svg', 'w').write(
    svg(f'<g transform="translate(512 512) scale({500 / 440:.4f})">{c}</g>'))
print('ok')

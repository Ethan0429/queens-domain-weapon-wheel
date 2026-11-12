"""Generates the UI artwork in Mods/HatchlingsWeaponWheel/Assets.

Requires Pillow and NumPy:  py -3 -m pip install pillow numpy
Run from anywhere:          py -3 tools/generate_assets.py

All sizes below are in the 1920x1080 layout units used by Scripts/ui.lua.
Textures are rendered at SS pixels per layout unit so they stay crisp at 1440p
and are only mildly minified at 1080p (imported textures have no mipmaps).
Geometry that must line up with ui.lua is marked "ui.lua".
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, '..', 'Mods', 'HatchlingsWeaponWheel', 'Assets')
SS = 1.5
RNG = np.random.default_rng(7)


def hexc(h):
    return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], float) / 255


# Palette: blackened iron, aged brass, ember highlight, verdigris for "equipped".
IRON0 = hexc('#080908')
IRON1 = hexc('#141512')
IRON2 = hexc('#22231f')
IRON3 = hexc('#2e2e29')
BRASS_D = hexc('#6e5a36')
BRASS = hexc('#b4955c')
BRASS_L = hexc('#e8d29e')
EMBER = hexc('#f0b45a')
EMBER_D = hexc('#7a5426')
VERD = hexc('#5fb8a4')
VERD_D = hexc('#1d3a34')
BLACK = hexc('#000000')
WHITE = hexc('#ffffff')


def lerp(a, b, t):
    t = np.asarray(t, float)
    return a * (1 - t)[..., None] + b * t[..., None]


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


class Canvas:
    def __init__(self, w, h, scale=SS):
        self.s = scale
        self.W, self.H = int(round(w * scale)), int(round(h * scale))
        self.w, self.h = self.W / scale, self.H / scale
        self.p = np.zeros((self.H, self.W, 4))
        ys, xs = np.mgrid[0:self.H, 0:self.W]
        self.x = (xs + .5) / scale
        self.y = (ys + .5) / scale

    def cov(self, d):
        """Anti-aliased coverage of a signed distance field (layout units)."""
        return np.clip(.5 - d * self.s, 0, 1)

    def line(self, d, width):
        return self.cov(np.abs(d) - width / 2)

    def paint(self, color, alpha):
        a = np.clip(np.broadcast_to(alpha, (self.H, self.W)), 0, 1)[..., None]
        c = np.broadcast_to(color, (self.H, self.W, 3))
        self.p = np.concatenate([c * a, a], axis=2) + self.p * (1 - a)

    def grain(self, mask, amount):
        n = RNG.normal(0, 1, (self.H, self.W))
        img = Image.fromarray(np.uint8(np.clip(n * 40 + 128, 0, 255)))
        from PIL import ImageFilter
        n = (np.asarray(img.filter(ImageFilter.GaussianBlur(.6)), float) - 128) / 40
        light = np.clip(n, 0, None) * amount * mask
        dark = np.clip(-n, 0, None) * amount * mask
        self.paint(WHITE, light)
        self.paint(BLACK, dark)

    def save(self, name):
        a = self.p[..., 3:4]
        rgb = np.where(a > 1e-6, self.p[..., :3] / np.maximum(a, 1e-6), 0)
        img = np.uint8(np.clip(np.concatenate([rgb, a], 2), 0, 1) * 255 + .5)
        Image.fromarray(img, 'RGBA').save(os.path.join(OUT, name + '.png'), optimize=True)


def rrect(c, x, y, w, h, r):
    """Signed distance to a rounded rectangle (layout units)."""
    cx, cy = x + w / 2, y + h / 2
    qx = np.abs(c.x - cx) - (w / 2 - r)
    qy = np.abs(c.y - cy) - (h / 2 - r)
    return np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - r


def diamond(c, cx, cy, r):
    return (np.abs(c.x - cx) + np.abs(c.y - cy) - r) / math.sqrt(2)


def poly_mask(c, pts, outline=0):
    """Supersampled polygon coverage; outline grows the shape by that many units."""
    k = 4
    img = Image.new('L', (c.W * k, c.H * k), 0)
    d = ImageDraw.Draw(img)
    sp = [(px * c.s * k, py * c.s * k) for px, py in pts]
    d.polygon(sp, fill=255)
    if outline:
        d.line(sp + [sp[0]], fill=255, width=int(round(outline * 2 * c.s * k)), joint='curve')
    return np.asarray(img.resize((c.W, c.H), Image.LANCZOS), float) / 255


def metal(c, theta, lo=BRASS_D, hi=BRASS_L):
    """Brass lit from the top-left; theta is the screen angle of each pixel."""
    light = .5 + .5 * np.cos(theta - math.radians(-135))
    return lerp(lo, hi, light ** 1.3)


# ---------------------------------------------------------------- wheel --
WHEEL_R = 400          # sector textures are 800x800 (ui.lua)
SECTOR_IN, SECTOR_OUT = 192, 372
SECTOR_GAP = 6


def sector(n, state):
    c = Canvas(2 * WHEEL_R, 2 * WHEEL_R)
    x, y = c.x - WHEEL_R, c.y - WHEEL_R
    r = np.hypot(x, y)
    phi = np.arctan2(x, -y)                       # 0 at 12 o'clock, clockwise
    if n > 1:
        h = math.pi / n
        side = r * np.sin(np.clip(np.abs(phi) - h, -math.pi / 2, math.pi / 2)) + SECTOR_GAP / 2
    else:
        side = np.full_like(r, -1e9)
    d = np.maximum.reduce([side, SECTOR_IN - r, r - SECTOR_OUT])
    inside = c.cov(d)
    t = np.clip((r - SECTOR_IN) / (SECTOR_OUT - SECTOR_IN), 0, 1)
    band = inside * smooth(SECTOR_OUT - 7, SECTOR_OUT - 5, r)
    inner_shadow = inside * (1 - smooth(0, 34, r - SECTOR_IN))
    if state == 'hover':
        glow = np.exp(-(np.maximum(d, 0) / 11) ** 2) * (d > 0)
        c.paint(EMBER, .42 * glow)
        c.paint(lerp(hexc('#3a2a12'), hexc('#7c5a2a'), t ** 1.2), .94 * inside)

        c.paint(hexc('#ffd690'), .16 * inside * t ** 2.5)
        c.paint(BLACK, .35 * inner_shadow)
        c.paint(BRASS_L, .9 * c.line(d + 1.1, 1.1))
        c.paint(lerp(EMBER, BRASS_L, smooth(SECTOR_OUT - 7, SECTOR_OUT, r)), .95 * band)
    elif state == 'current':
        c.paint(lerp(hexc('#0f1d1a'), hexc('#1e3a34'), t), .9 * inside)

        c.paint(BLACK, .35 * inner_shadow)
        c.paint(VERD, .55 * c.line(d + 1.1, 1))
        c.paint(VERD, .9 * inside * smooth(SECTOR_OUT - 5, SECTOR_OUT - 4, r))
    else:
        c.paint(lerp(hexc('#11120f'), hexc('#24241f'), t), .88 * inside)

        c.paint(BLACK, .4 * inner_shadow)
        c.paint(BRASS_D, .55 * c.line(d + 1.1, 1))
        c.paint(BRASS_D, .25 * c.line(r - (SECTOR_OUT - 16), .8) * inside)
        c.paint(lerp(BRASS_D, BRASS, .4), .75 * inside * smooth(SECTOR_OUT - 4, SECTOR_OUT - 3, r))
    c.save(f'sector-{state + "-" if state != "base" else ""}{n}')


def backplate():
    R = 440                                         # 880x880 (ui.lua)
    c = Canvas(2 * R, 2 * R)
    x, y = c.x - R, c.y - R
    r = np.hypot(x, y)
    theta = np.arctan2(y, x)
    phi = np.arctan2(x, -y)
    c.paint(BLACK, .62 * (1 - smooth(372, 438, r)))
    c.paint(IRON0, .5 * c.cov(r - 384))
    # Rim: lit brass ring with a fine companion line.
    c.paint(metal(c, theta), .95 * c.line(r - 389, 3))
    c.paint(BRASS_D, .8 * c.line(r - 396, 1))
    # Engraved ticks: minor every 6 degrees, major every 30.
    def ticks(step, r0, r1, width, color, alpha):
        a = phi - np.round(phi / step) * step
        d = np.maximum(np.abs(r * np.sin(a)) - width / 2, np.maximum(r0 - r, r - r1))
        c.paint(color, alpha * c.cov(d))
    ticks(math.radians(6), 401, 407, .9, BRASS_D, .7)
    ticks(math.radians(30), 400, 414, 1.4, BRASS, .9)
    for k in range(4):
        a = k * math.pi / 2
        cx, cy = R + math.sin(a) * 422, R - math.cos(a) * 422
        dd = diamond(c, cx, cy, 9)
        c.paint(BLACK, .6 * c.cov(diamond(c, cx, cy, 11)))
        c.paint(metal(c, theta), c.cov(dd))
        c.paint(IRON0, .9 * c.cov(diamond(c, cx, cy, 3.5)))
    c.paint(BRASS_D, .7 * c.line(r - 185, 1.2))
    c.save('wheel-backplate')


def hub():
    R = 180                                         # 360x360; ring outer radius 168 (ui.lua)
    c = Canvas(2 * R, 2 * R)
    x, y = c.x - R, c.y - R
    r = np.hypot(x, y)
    theta = np.arctan2(y, x)
    phi = np.arctan2(x, -y)
    c.paint(BLACK, .55 * (1 - smooth(160, 179, r)))
    disc = c.cov(r - 160)
    c.paint(lerp(hexc('#060706'), hexc('#1c1d19'), smooth(20, 160, r)), .97 * disc)
    c.grain(disc, .02)
    c.paint(BRASS_D, .5 * c.line(r - 146, 1))
    a = phi - np.round(phi / math.radians(15)) * math.radians(15)
    dots = np.hypot(r * np.sin(a), r * np.cos(a) - 153) - 1.6
    c.paint(BRASS_D, .75 * c.cov(dots))
    ring = c.cov(np.abs(r - 164) - 4)
    c.paint(metal(c, theta), ring)
    c.paint(BRASS_L, .5 * c.line(r - 167.3, .8))
    c.paint(BLACK, .7 * c.line(r - 160.2, .9))
    c.save('hub')

    g = Canvas(260, 260)
    rr = np.hypot(g.x - 130, g.y - 130)
    g.paint(EMBER, .3 * np.exp(-(rr / 62) ** 2))
    g.save('hub-glow')

    # Direction pointer: a brass chevron just outside the hub, rotated by ui.lua.
    p = Canvas(400, 400)
    pts = [(200, 200 - 192), (200 + 13, 200 - 172), (200, 200 - 177), (200 - 13, 200 - 172)]
    p.paint(BLACK, .7 * poly_mask(p, pts, outline=1.4))
    pr = np.hypot(p.x - 200, p.y - 200)
    p.paint(lerp(EMBER, BRASS_L, smooth(172, 192, pr)), poly_mask(p, pts))
    p.save('pointer')


def vignette():
    c = Canvas(480, 270, 1)
    u = (c.x - 240) / 240
    v = (c.y - 135) / 135
    rr = np.sqrt(u * u + v * v * .85)
    c.paint(hexc('#050605'), .5 + .4 * smooth(.25, 1.25, rr))
    c.save('vignette')


def divider(name, w, h):
    c = Canvas(w, h)
    cx, cy = w / 2, h / 2
    u = np.abs(c.x - cx) / (w / 2)
    fade = (1 - smooth(.55, 1, u)) * smooth(0, 1, (np.abs(c.x - cx) - 15) / 4)
    c.paint(BRASS, .85 * fade * c.line(c.y - cy, 1.1))
    theta = np.arctan2(c.y - cy, c.x - cx)
    c.paint(BLACK, .6 * c.cov(diamond(c, cx, cy, 10)))
    c.paint(metal(c, theta), c.cov(diamond(c, cx, cy, 8)))
    c.paint(IRON0, c.cov(diamond(c, cx, cy, 3)))
    for sx in (-1, 1):
        px = cx + sx * 30
        c.paint(BRASS, c.cov(diamond(c, px, cy, 3.2)))
    c.save(name)


def pips():
    for on in (False, True):
        c = Canvas(22, 22)
        d = diamond(c, 11, 11, 6.5)
        if on:
            c.paint(EMBER, .45 * np.exp(-(np.maximum(d, 0) / 3) ** 2))
            c.paint(lerp(BRASS_L, EMBER, smooth(5, 17, c.y)), c.cov(d))
        else:
            c.paint(IRON1, .9 * c.cov(d))
            c.paint(BRASS_D, c.line(d + .5, 1.1))
        c.save('pip-on' if on else 'pip')


def keycap(w, h=30):
    c = Canvas(w, h)
    d = rrect(c, .5, .5, w - 1, h - 1, 5)
    c.paint(BLACK, .5 * c.cov(rrect(c, .5, 1.5, w - 1, h - 1, 5)))
    c.paint(lerp(hexc('#302f2a'), hexc('#191917'), smooth(0, h, c.y)), .96 * c.cov(d))
    c.paint(BLACK, .5 * c.cov(d) * smooth(h - 5, h - 1, c.y))
    c.paint(BRASS_D, c.line(d + .6, 1.2))
    c.paint(WHITE, .08 * c.line(c.y - 2.2, .8) * c.cov(d + 3))
    c.save(f'key-{w}')


def cursor():
    c = Canvas(27, 36, 3)
    pts = [(2.5, 2), (2.5, 28.5), (8.8, 22.8), (13.2, 32.5), (17.6, 30.6), (13.3, 21.2), (21.6, 21.2)]
    c.paint(BLACK, .45 * poly_mask(c, [(px + 1, py + 1.5) for px, py in pts], outline=1.8))
    c.paint(hexc('#0b0b0a'), poly_mask(c, pts, outline=1.5))
    c.paint(lerp(BRASS_L, BRASS, smooth(2, 32, c.y)), poly_mask(c, pts))
    c.save('cursor')


# --------------------------------------------------------------- editor --
PANEL_X, PANEL_Y, PANEL_W, PANEL_H = 240, 110, 1440, 860   # ui.lua
PANEL_M = 28                                                # shadow margin baked around the panel


def panel():
    m = PANEL_M
    c = Canvas(PANEL_W + 2 * m, PANEL_H + 2 * m)
    d = rrect(c, m, m, PANEL_W, PANEL_H, 6)
    inside = c.cov(d)
    c.paint(BLACK, .6 * np.exp(-(np.maximum(d, 0) / 13) ** 2) * (1 - inside))
    c.paint(lerp(hexc('#1b1c18'), hexc('#0e0f0d'), smooth(m, m + PANEL_H, c.y)), .965 * inside)
    c.grain(inside, .018)
    glow = np.exp(-((c.x - m - PANEL_W / 2) / 640) ** 2 - ((c.y - m) / 200) ** 2)
    c.paint(hexc('#4a3f28'), .22 * glow * inside)
    c.paint(BRASS_D, c.line(d + .8, 1.6))
    c.paint(BRASS, .3 * c.line(d + 7.5, 1))
    # Corner brackets with a diamond rivet.
    for sx, sy in ((0, 0), (1, 0), (0, 1), (1, 1)):
        cx = m + (PANEL_W - 13 if sx else 13)
        cy = m + (PANEL_H - 13 if sy else 13)
        dx = 1 if not sx else -1
        dy = 1 if not sy else -1
        arm_h = np.maximum(np.abs(c.y - cy) - 1, np.abs(c.x - (cx + dx * 22)) - 22)
        arm_v = np.maximum(np.abs(c.x - cx) - 1, np.abs(c.y - (cy + dy * 22)) - 22)
        theta = np.arctan2(c.y - cy, c.x - cx)
        c.paint(BRASS, .9 * c.cov(np.minimum(arm_h, arm_v)))
        c.paint(BLACK, .6 * c.cov(diamond(c, cx, cy, 8)))
        c.paint(metal(c, theta), c.cov(diamond(c, cx, cy, 6)))

    def hrule(y, x0, x1, alpha, ornament):
        u = np.abs(c.x - (x0 + x1) / 2) / ((x1 - x0) / 2)
        fade = 1 - smooth(.6, 1, u)
        if ornament:
            fade = fade * smooth(0, 1, (np.abs(c.x - (x0 + x1) / 2) - 14) / 3)
        c.paint(BRASS_D, alpha * fade * c.line(c.y - y, 1.1))
        if ornament:
            cx = (x0 + x1) / 2
            theta = np.arctan2(c.y - y, c.x - cx)
            c.paint(metal(c, theta), c.cov(diamond(c, cx, y, 7)))
            c.paint(IRON0, c.cov(diamond(c, cx, y, 2.5)))

    # Separators; positions are relative to the panel's top-left corner (ui.lua).
    hrule(m + 138, m + 40, m + PANEL_W - 40, .95, True)
    hrule(m + 782, m + 40, m + PANEL_W - 40, .7, False)
    vx = m + 913
    v = np.abs(c.y - (m + 457)) / 305
    c.paint(BRASS_D, .7 * (1 - smooth(.7, 1, v)) * c.line(c.x - vx, 1.1))
    c.save('panel')


def plate(name, w, h, top, bottom, border, border_w=1.2, alpha=.94, accent=None, well=None, sep=None):
    c = Canvas(w, h)
    d = rrect(c, .5, .5, w - 1, h - 1, 4)
    inside = c.cov(d)
    c.paint(lerp(top, bottom, smooth(0, h, c.y)), alpha * inside)
    c.grain(inside, .015)
    c.paint(WHITE, .05 * c.line(c.y - 1.8, .8) * c.cov(d + 2))
    if well is not None:
        wx, wy, ws, wborder = well
        wd = rrect(c, wx, wy, ws, ws, 3)
        c.paint(hexc('#070807'), .9 * c.cov(wd))
        c.paint(BLACK, .5 * c.cov(wd) * (1 - smooth(0, 8, c.y - wy)))
        c.paint(wborder, .8 * c.line(wd + .5, 1))
    if sep is not None:
        c.paint(sep[1], .6 * c.line(c.x - sep[0], 1) * c.cov(np.abs(c.y - h / 2) - (h / 2 - 9)))
    if accent is not None:
        c.paint(accent, c.cov(np.maximum(c.x - 4.5, d)) * c.cov(np.abs(c.y - h / 2) - (h / 2 - 7)))
    c.paint(border, c.line(d + border_w / 2, border_w))
    return c


CARD_W, CARD_H = 272, 78      # ui.lua
ROW_W, ROW_H = 454, 50        # ui.lua


def cards():
    well = lambda b: (8, 7, 64, b)
    plate('card', CARD_W, CARD_H, hexc('#1e1f1b'), hexc('#151613'), hexc('#3c3a33'), well=well(hexc('#2e2c26'))).save('card')
    plate('card-hover', CARD_W, CARD_H, hexc('#2c2b25'), hexc('#1d1d19'), BRASS_D, well=well(BRASS_D)).save('card-hover')
    plate('card-chosen', CARD_W, CARD_H, hexc('#33291a'), hexc('#211b12'), BRASS, 1.4,
          well=well(BRASS_D), accent=BRASS_L).save('card-chosen')
    plate('card-chosen-hover', CARD_W, CARD_H, hexc('#4a3b22'), hexc('#2e2516'), BRASS_L, 1.6,
          well=well(BRASS), accent=BRASS_L).save('card-chosen-hover')

    c = Canvas(30, 30)
    dd = diamond(c, 15, 15, 13)
    theta = np.arctan2(c.y - 15, c.x - 15)
    c.paint(BLACK, .6 * c.cov(diamond(c, 15, 16, 14)))
    c.paint(hexc('#16130d'), c.cov(dd))
    c.paint(metal(c, theta), c.line(dd + .7, 1.4))
    c.save('badge')

    sep = (44, BRASS_D)
    plate('row', ROW_W, ROW_H, hexc('#1c1d1a'), hexc('#141512'), hexc('#36352f'), sep=sep).save('row')
    plate('row-hover', ROW_W, ROW_H, hexc('#2a2924'), hexc('#1c1c18'), BRASS_D, sep=sep).save('row-hover')
    plate('row-selected', ROW_W, ROW_H, hexc('#3a2f1c'), hexc('#251e13'), BRASS, 1.4, sep=(44, BRASS), accent=BRASS_L).save('row-selected')
    plate('row-selected-hover', ROW_W, ROW_H, hexc('#4c3d23'), hexc('#2f2617'), BRASS_L, 1.6, sep=(44, BRASS), accent=BRASS_L).save('row-selected-hover')


BUTTONS = [(150, 46, True), (170, 42, False), (144, 42, False)]   # ui.lua
ARROW = (44, 42)


def button_states(w, h, primary):
    if primary:
        return {
            '': (hexc('#6a5330'), hexc('#46361e'), BRASS, 1.4),
            '-hover': (hexc('#8e7040'), hexc('#5e4826'), BRASS_L, 1.6),
            '-disabled': (hexc('#1a1a17'), hexc('#121210'), hexc('#3a3832'), 1.0),
        }
    return {
        '': (hexc('#2a2a25'), hexc('#1a1a17'), BRASS_D, 1.3),
        '-hover': (hexc('#4a3c22'), hexc('#2e2516'), BRASS_L, 1.5),
        '-disabled': (hexc('#171815'), hexc('#111210'), hexc('#2e2d28'), 1.0),
    }


def buttons():
    for w, h, primary in BUTTONS:
        for suffix, (top, bottom, border, bw) in button_states(w, h, primary).items():
            name = f'btn-{w}x{h}{"-primary" if primary else ""}{suffix}'
            plate(name, w, h, top, bottom, border, bw, alpha=.96 if suffix != '-disabled' else .8).save(name)
    w, h = ARROW
    for direction in ('left', 'right'):
        for suffix, (top, bottom, border, bw) in button_states(w, h, False).items():
            c = plate('', w, h, top, bottom, border, bw, alpha=.96 if suffix != '-disabled' else .8)
            sx = -1 if direction == 'left' else 1
            cx, cy = w / 2 + sx * 2, h / 2
            # Chevron: outer tip, two arms, inner notch.
            pts = [(cx + sx * 5, cy), (cx - sx * 3, cy - 8), (cx - sx * 7, cy - 8),
                   (cx + sx * 1, cy), (cx - sx * 7, cy + 8), (cx - sx * 3, cy + 8)]
            color = {'': BRASS, '-hover': BRASS_L, '-disabled': hexc('#4a4740')}[suffix]
            c.paint(BLACK, .5 * poly_mask(c, [(px, py + 1) for px, py in pts]))
            c.paint(color, poly_mask(c, pts))
            c.save(f'arrow-{direction}{suffix}')


def main():
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.endswith('.png'):
            os.remove(os.path.join(OUT, f))
    vignette()
    backplate()
    hub()
    for n in range(1, 13):
        for state in ('base', 'hover', 'current'):
            sector(n, state)
    divider('divider', 520, 28)
    pips()
    keycap(48)
    keycap(72)
    cursor()
    panel()
    cards()
    buttons()
    print('Wrote', len([f for f in os.listdir(OUT) if f.endswith('.png')]), 'textures to', os.path.abspath(OUT))


if __name__ == '__main__':
    main()

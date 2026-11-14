#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""MacNix 2.0 — Calamares slayt görsellerini üretir.

Kurulum sırasında ilerleme ekranında görünen görseller. Hepsi logo paletinde
(turkuaz gradyan #7DF0FF → #17B8CE, koyu #0B0C10 zemin) ve ŞEFFAF PNG'dir;
böylece slayt kartındaki koyu zemine dikişsiz oturur.

Kullanım: python3 tools/assets/gen-slide-art.py --out calamares/branding/macnix
"""
import argparse
import math
import os

from PIL import Image, ImageDraw

S = 512  # çalışma çözünürlüğü (merkezden kırpılıp 384'e indirilir)
TOP = (125, 240, 255)      # #7DF0FF
BOT = (23, 184, 206)       # #17B8CE
DARK = (11, 12, 16)        # #0B0C10


def gradient(size=(S, S)):
    img = Image.new("RGB", size)
    px = img.load()
    w, h = size
    for y in range(h):
        t = y / max(1, h - 1)
        r = int(TOP[0] + (BOT[0] - TOP[0]) * t)
        g = int(TOP[1] + (BOT[1] - TOP[1]) * t)
        b = int(TOP[2] + (BOT[2] - TOP[2]) * t)
        for x in range(w):
            px[x, y] = (r, g, b)
    return img


GRAD = gradient()


def new_mask():
    return Image.new("L", (S, S), 0)


def fill(mask, alpha=255):
    """Maskeyi gradyanla doldur → RGBA katman."""
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    layer.paste(GRAD, (0, 0), mask.point(lambda v: v * alpha // 255))
    return layer


def dark_mask(mask, alpha=255):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    layer.paste(Image.new("RGB", (S, S), DARK), (0, 0), mask.point(lambda v: v * alpha // 255))
    return layer


def ring(draw, box, width):
    draw.ellipse(box, outline=255, width=width)


def rr(draw, box, r, width=None, fillv=None):
    if fillv is not None:
        draw.rounded_rectangle(box, radius=r, fill=fillv)
    else:
        draw.rounded_rectangle(box, radius=r, outline=255, width=width)


# ── 1. Donanım profili: çip + devre izleri ─────────────────────────────────
def art_hardware():
    m = new_mask()
    d = ImageDraw.Draw(m)
    # gövde
    rr(d, (150, 150, 362, 362), 46, width=16)
    # iç çekirdek
    rr(d, (216, 216, 296, 296), 22, width=14)
    # pinler
    for i in range(5):
        p = 172 + i * 42
        d.rounded_rectangle((p, 108, p + 22, 152), radius=10, fill=255)     # üst
        d.rounded_rectangle((p, 360, p + 22, 404), radius=10, fill=255)     # alt
        d.rounded_rectangle((108, p, 152, p + 22), radius=10, fill=255)     # sol
        d.rounded_rectangle((360, p, 404, p + 22), radius=10, fill=255)     # sağ
    # devre izleri
    for (x1, y1, x2, y2) in [(60, 200, 108, 200), (60, 256, 108, 256), (60, 312, 108, 312),
                             (404, 200, 452, 200), (404, 256, 452, 256), (404, 312, 452, 312),
                             (200, 60, 200, 108), (256, 60, 256, 108), (312, 60, 312, 108),
                             (200, 404, 200, 452), (256, 404, 256, 452), (312, 404, 312, 452)]:
        d.line((x1, y1, x2, y2), fill=255, width=12)
    for (cx, cy) in [(60, 200), (60, 256), (60, 312), (452, 200), (452, 256), (452, 312)]:
        d.ellipse((cx - 11, cy - 11, cx + 11, cy + 11), fill=255)
    img = fill(m)
    # çekirdek içini koyu yap (kontrast)
    inner = new_mask()
    ImageDraw.Draw(inner).rounded_rectangle((222, 222, 290, 290), radius=18, fill=255)
    img = Image.alpha_composite(img, dark_mask(inner))
    return img


# ── 2. macOS indirme: bulut + aşağı ok ─────────────────────────────────────
def art_download():
    m = new_mask()
    d = ImageDraw.Draw(m)
    # bulut
    d.ellipse((120, 150, 250, 280), fill=255)
    d.ellipse((210, 120, 350, 260), fill=255)
    d.ellipse((290, 165, 400, 275), fill=255)
    d.rectangle((150, 210, 380, 275), fill=255)
    # ok
    d.rounded_rectangle((238, 290, 274, 380), radius=16, fill=255)
    d.polygon([(200, 366), (312, 366), (256, 440)], fill=255)
    # taban çizgisi
    d.rounded_rectangle((140, 452, 372, 470), radius=9, fill=255)
    return fill(m)


# ── 3. Sanal makine: iki pencere (host + guest) ────────────────────────────
def art_vm():
    host = new_mask()
    dh = ImageDraw.Draw(host)
    rr(dh, (52, 96, 460, 400), 34, width=16)
    dh.line((52, 156, 460, 156), fill=255, width=14)
    for i, cx in enumerate((92, 124, 156)):
        dh.ellipse((cx - 9, 118, cx + 9, 136), fill=255)
    # ekran içi
    rr(dh, (96, 196, 416, 356), 20, width=12)

    guest = new_mask()
    dg = ImageDraw.Draw(guest)
    rr(dg, (140, 232, 420, 452), 26, width=0, fillv=255)
    # iç boşluk (koyu) → pencere görünümü
    hole = new_mask()
    dhole = ImageDraw.Draw(hole)
    rr(dhole, (168, 262, 392, 424), 16, fillv=255)
    dh2 = ImageDraw.Draw(hole)
    dh2.line((168, 300, 392, 300), fill=0, width=10)
    dh2.ellipse((182, 272, 198, 288), fill=0)
    dh2.ellipse((208, 272, 224, 288), fill=0)

    img = fill(host, 190)
    img = Image.alpha_composite(img, fill(guest))
    img = Image.alpha_composite(img, dark_mask(hole))
    return img


# ── 4. Performans: gösterge (speedometer) ──────────────────────────────────
def art_perf():
    m = new_mask()
    d = ImageDraw.Draw(m)
    box = (96, 116, 416, 436)
    d.arc(box, start=150, end=390, fill=255, width=26)
    # ibre
    ang = math.radians(300)
    cx, cy = 256, 276
    d.line((cx, cy, cx + 130 * math.cos(ang), cy + 130 * math.sin(ang)), fill=255, width=22)
    d.ellipse((cx - 34, cy - 34, cx + 34, cy + 34), fill=255)
    for a in range(150, 391, 30):
        r = math.radians(a)
        d.line((cx + 168 * math.cos(r), cy + 168 * math.sin(r),
                cx + 196 * math.cos(r), cy + 196 * math.sin(r)), fill=255, width=14)
    img = fill(m)
    hub = new_mask()
    ImageDraw.Draw(hub).ellipse((cx - 16, cy - 16, cx + 16, cy + 16), fill=255)
    return Image.alpha_composite(img, dark_mask(hub))


# ── 5. OpenCore: dişli çarklar ─────────────────────────────────────────────
def gear(d, cx, cy, r_out, r_in, teeth=10, depth=34, width=18):
    for i in range(teeth):
        a = 2 * math.pi * i / teeth
        x1 = cx + (r_out - depth) * math.cos(a)
        y1 = cy + (r_out - depth) * math.sin(a)
        x2 = cx + (r_out + depth) * math.cos(a)
        y2 = cy + (r_out + depth) * math.sin(a)
        d.line((x1, y1, x2, y2), fill=255, width=width * 2)
    d.ellipse((cx - r_out, cy - r_out, cx + r_out, cy + r_out), outline=255, width=width)
    d.ellipse((cx - r_in, cy - r_in, cx + r_in, cy + r_in), outline=255, width=width)


def art_opencore():
    m = new_mask()
    d = ImageDraw.Draw(m)
    gear(d, 224, 232, 104, 40, teeth=9, depth=30, width=20)
    g2 = new_mask()
    gear(ImageDraw.Draw(g2), 356, 344, 62, 24, teeth=8, depth=20, width=14)
    img = fill(m)
    return Image.alpha_composite(img, fill(g2, 220))


# ── 6. Güvenlik / gizlilik: kalkan + onay ──────────────────────────────────
def art_shield():
    m = new_mask()
    d = ImageDraw.Draw(m)
    d.polygon([(256, 92), (404, 148), (404, 268), (256, 428), (108, 268), (108, 148)], fill=255)
    img = fill(m)
    hole = new_mask()
    dh = ImageDraw.Draw(hole)
    dh.polygon([(256, 132), (368, 176), (368, 262), (256, 388), (144, 262), (144, 176)], fill=255)
    img = Image.alpha_composite(img, dark_mask(hole))
    check = new_mask()
    ImageDraw.Draw(check).line([(196, 258), (240, 304), (322, 210)], fill=255, width=26, joint="curve")
    return Image.alpha_composite(img, fill(check))


ARTS = {
    "slide-hardware.png": art_hardware,
    "slide-download.png": art_download,
    "slide-vm.png": art_vm,
    "slide-perf.png": art_perf,
    "slide-opencore.png": art_opencore,
    "slide-shield.png": art_shield,
}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--size", type=int, default=384)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    for name, fn in ARTS.items():
        img = fn()
        # 512 → hedef boyut (yumuşak ölçek)
        img = img.resize((a.size, a.size), Image.LANCZOS)
        path = os.path.join(a.out, name)
        img.save(path, optimize=True)
        print(f"  {name}  {img.size}  {os.path.getsize(path) // 1024} KB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

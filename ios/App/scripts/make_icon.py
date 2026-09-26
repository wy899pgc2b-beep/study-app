#!/usr/bin/env python3
"""ツクエログのアプリアイコンを作る(決定事項 D-22)。

シンプルで、綺麗で美しく整った見た目にする(アニメ映画のタイトルのような上品さ):
  - まっすぐ立てた明朝の文字 1 字(「ツクエログ」の「ツ」)を、真ん中に置く
  - 文字は白から淡い金へのグラデーションと、やわらかい光。斜めに細い光の帯(箔押しのような)
  - 文字を囲む細い金の輪(内側にもう 1 本の細い線)。輪の真上にキラッ 1 つ
  - 背景は夕方から夜へ移る空(紺から青、下に灯りのような温かい光)と、左右対称の小さな星
2 倍の大きさ(2048)で描いて 1024 に縮め、ふちをなめらかにする。透明な部分は作らない(App Store の決まり)。

文字は しっぽり明朝 B1 ExtraBold(SIL Open Font License)。初めて動かすときに google/fonts から取ってくる(リポジトリには入れない)。
使い方(pillow・numpy・scipy が要る):
  python3 make_icon.py                                  # Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png を作り直す
  python3 make_icon.py --glyph 机 --palette green --out x.png   # ほかの案(文字:ツ・机、色:twilight・green)
  python3 make_icon.py --preview preview.png            # 角の丸い形で切った、ホーム画面の大きさの見本
"""

import argparse
import math
import os
import urllib.request

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.dirname(HERE)
ICON = os.path.join(APP, "Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
FONT_DIR = os.path.join(APP, ".icon-fonts")
FONT = "ShipporiMinchoB1-ExtraBold.ttf"
FONT_URL = "https://raw.githubusercontent.com/google/fonts/main/ofl/shipporiminchob1/ShipporiMinchoB1-ExtraBold.ttf"

S = 2048  # 描く大きさ(書き出しは 1024)
Y, X = np.mgrid[0:S, 0:S].astype(np.float32)
CX, CY = S / 2, S / 2

# 金(輪と、緑の案の文字)と、淡い金(夕空の案の文字)
GOLD = [(0.0, 0xFFF3CF), (0.42, 0xF3D183), (0.58, 0xE2AE55), (1.0, 0xC4892E)]
PALE = [(0.0, 0xFFFFFF), (0.6, 0xFFF4DA), (1.0, 0xF5D9A2)]
# 文字ごとの大きさと、見た目の中心に合わせる上下のずれ
GLYPHS = {"ツ": (1060, 0.01), "机": (920, 0.015)}


def font_path():
    path = os.path.join(FONT_DIR, FONT)
    if not os.path.exists(path):
        os.makedirs(FONT_DIR, exist_ok=True)
        urllib.request.urlretrieve(FONT_URL, path)
    return path


def rgb(h):
    return np.array([(h >> 16) & 255, (h >> 8) & 255, h & 255], dtype=np.float32) / 255


def over(base, color, alpha):
    a = alpha[..., None]
    return base * (1 - a) + color * a


def stops(t, pairs):
    """t(0〜1)の配列に、色の段階 [(位置, 色), ...] をなめらかにつける"""
    out = np.zeros(t.shape + (3,), dtype=np.float32)
    for (p0, c0), (p1, c1) in zip(pairs, pairs[1:]):
        m = (t >= p0) & (t <= p1)
        u = ((t - p0) / max(1e-6, p1 - p0))[..., None]
        out[m] = (rgb(c0) * (1 - u) + rgb(c1) * u)[m]
    out[t < pairs[0][0]] = rgb(pairs[0][1])
    out[t > pairs[-1][0]] = rgb(pairs[-1][1])
    return out


def glyph(text, size, dy):
    """文字の形(0〜1)。字面の中心を、真ん中から dy だけ下に置く"""
    f = ImageFont.truetype(font_path(), size)
    layer = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(layer)
    l, t, r, b = d.textbbox((0, 0), text, font=f)
    d.text((CX - (l + r) / 2, CY + S * dy - (t + b) / 2), text, font=f, fill=255)
    return np.asarray(layer, dtype=np.float32) / 255


def ring(radius, width, gap_center, gap_r):
    """細い輪。キラッの後ろは切っておく"""
    a = np.clip(width / 2 + 0.5 - np.abs(np.hypot(X - CX, Y - CY) - radius), 0, 1)
    return a * np.clip((np.hypot(X - gap_center[0], Y - gap_center[1]) - gap_r) / 6, 0, 1)


def sparkle(img, cx, cy, r, inner):
    """キラッ(4 つの角の細い星)と、まわりの光"""
    pts = []
    for k in range(8):
        ang = k * math.pi / 4 - math.pi / 2
        rr = r if k % 2 == 0 else r * inner
        pts.append((cx + rr * math.cos(ang), cy + rr * math.sin(ang)))
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).polygon(pts, fill=255)
    m = np.asarray(m, dtype=np.float32) / 255
    img = over(img, rgb(0xFFF1C8), np.clip(ndimage.gaussian_filter(m, r * 0.5) * 1.4, 0, 1) * 0.5)
    return over(img, rgb(0xFFFFFF), m)


def foil(img, alpha, pairs, top, bottom, sheen):
    """箔押しのような色:上から下へのグラデーションと、斜めの細い光の帯"""
    t = np.clip((Y - top) / max(1, bottom - top), 0, 1)
    col = stops(t, pairs)
    band = np.exp(-(((X - CX) * 0.55 + (Y - CY) * 0.85 + S * 0.05) / (S * 0.06)) ** 2) * sheen
    col = col * (1 - band[..., None]) + band[..., None]
    return img * (1 - alpha[..., None]) + col * alpha[..., None]


def background(palette):
    t = np.clip(Y / S, 0, 1)
    if palette == "twilight":
        # 夕方から夜へ移る空。下には、机の灯りのような温かい光
        img = stops(t, [(0.0, 0x0E1830), (0.5, 0x1F3560), (0.85, 0x44558A), (1.0, 0x7A6C9C)])
        glow = np.clip(1 - np.hypot(X - CX, Y - S * 1.02) / (S * 0.7), 0, 1) ** 2
        img = over(img, rgb(0xF6C98E), glow * 0.55)
    else:
        # 日誌の表紙のような深い緑(アプリの基本の色)
        img = stops(t, [(0.0, 0x2F6B5A), (1.0, 0x173E34)])
        light = np.clip(1 - np.hypot(X - S * 0.35, Y - S * 0.25) / (S * 0.8), 0, 1) ** 2
        img = over(img, rgb(0x4E8F79), light * 0.35)
    # 外側を少し暗くして、真ん中に目が行くようにする
    vig = np.clip((np.hypot(X - CX, Y - CY) - S * 0.45) / (S * 0.35), 0, 1)
    return over(img, np.zeros(3, dtype=np.float32), vig * 0.25)


def render(text="ツ", palette="twilight"):
    size, dy = GLYPHS[text]
    img = background(palette)
    a = glyph(text, size, dy)
    rows = np.nonzero(a.max(axis=1) > 0.5)[0]
    radius = S * 0.385
    spark = (CX, CY - radius)
    outer = ring(radius, S * 0.012, spark, S * 0.05)
    inner = ring(radius - S * 0.028, S * 0.0045, spark, S * 0.07)
    # 文字と輪の、やわらかい影と、文字のまわりの光
    shadow = ndimage.gaussian_filter(np.maximum(a, outer), 14)
    img = over(img, np.zeros(3, dtype=np.float32), ndimage.shift(shadow, (18, 0), order=1) * 0.35)
    img = over(img, rgb(0xFFE7B0), np.clip(ndimage.gaussian_filter(a, 40) * 1.2, 0, 1) * 0.28)
    img = foil(img, outer, GOLD, CY - radius, CY + radius, sheen=0.2)
    img = foil(img, inner * 0.8, GOLD, CY - radius, CY + radius, sheen=0.0)
    img = foil(img, a, PALE if palette == "twilight" else GOLD, rows.min(), rows.max(), sheen=0.28)
    img = sparkle(img, spark[0], spark[1], S * 0.07, 0.13)
    if palette == "twilight":
        # 左右対称の小さな星(輪にかからない所)
        for x, y, r in ((0.17, 0.15, 0.017), (0.83, 0.15, 0.017), (0.09, 0.3, 0.009), (0.91, 0.3, 0.009)):
            img = sparkle(img, S * x, S * y, S * r, 0.18)
    out = Image.fromarray(np.clip(img * 255 + 0.5, 0, 255).astype(np.uint8), "RGB")
    return out.resize((1024, 1024), Image.LANCZOS)


def squircle(im, n):
    """iOS のアイコンに近い、角の丸い形で切る(見本用)"""
    m = n * 4
    y, x = np.mgrid[0:m, 0:m].astype(np.float32)
    u, v = np.abs((x + 0.5) / m * 2 - 1), np.abs((y + 0.5) / m * 2 - 1)
    mask = Image.fromarray(((u**5 + v**5) <= 1).astype(np.uint8) * 255, "L").resize((n, n), Image.LANCZOS)
    out = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    out.paste(im.resize((n, n), Image.LANCZOS), (0, 0), mask)
    return out


def preview(icon, path):
    """大きい表示と、ホーム画面(60pt@3x=180px)・設定(29pt@3x=87px)の大きさを、明るい壁紙と暗い壁紙の上に並べる"""
    sheet = Image.new("RGB", (900, 560), (245, 242, 235))
    d = ImageDraw.Draw(sheet)
    d.rectangle([460, 0, 900, 280], fill=(206, 222, 236))
    d.rectangle([460, 280, 900, 560], fill=(28, 30, 36))
    big = squircle(icon, 420)
    sheet.paste(big, (20, 70), big)
    for y in (50, 330):
        a, b = squircle(icon, 180), squircle(icon, 87)
        sheet.paste(a, (500, y), a)
        sheet.paste(b, (730, y + 46), b)
    sheet.save(path)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--glyph", default="ツ", choices=sorted(GLYPHS))
    p.add_argument("--palette", default="twilight", choices=["twilight", "green"])
    p.add_argument("--out", default=ICON)
    p.add_argument("--preview")
    a = p.parse_args()
    icon = render(a.glyph, a.palette)
    icon.save(a.out, optimize=True)
    if a.preview:
        preview(icon, a.preview)
    print(f"{a.out} を作りました")


if __name__ == "__main__":
    main()

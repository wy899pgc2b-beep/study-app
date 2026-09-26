#!/usr/bin/env python3
"""ツクエログのアプリアイコンを作る(決定事項 D-22)。

シンプルさを追いつつ、アニメのタイトルロゴのように印象に残る見た目にする:
  - 太い文字 1 字(「ツクエログ」の「ツ」)を少し傾ける
  - 重ね方:ぼかした影 → 濃いふち → 立体の側面 → 白いふち → ランプの灯りの色のグラデーション → つや
  - 背景は夜の机の紺色に、漫画の集中線(「集中」を表す)と、中心のやわらかい灯り
  - キラッ(4 つの角の星)を 1 つ
2 倍の大きさ(2048)で描いて 1024 に縮め、ふちをなめらかにする。透明な部分は作らない(App Store の決まり)。

文字は Dela Gothic One(SIL Open Font License)。初めて動かすときに google/fonts から取ってくる(リポジトリには入れない)。
使い方(pillow・numpy・scipy が要る):
  python3 make_icon.py                      # Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png を作り直す
  python3 make_icon.py --variant b --out x.png   # ほかの案(a2:丸い「ツ」、b:「机」、c:「ツクエ」)
  python3 make_icon.py --preview preview.png     # 角の丸い形で切った、ホーム画面の大きさの見本
"""

import argparse
import math
import os
import random
import urllib.request

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.dirname(HERE)
ICON = os.path.join(APP, "Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
FONT_DIR = os.path.join(APP, ".icon-fonts")
FONT_URLS = {
    "DelaGothicOne-Regular.ttf": "https://raw.githubusercontent.com/google/fonts/main/ofl/delagothicone/DelaGothicOne-Regular.ttf",
    "ZenMaruGothic-Black.ttf": "https://raw.githubusercontent.com/google/fonts/main/ofl/zenmarugothic/ZenMaruGothic-Black.ttf",
}

S = 2048  # 描く大きさ(書き出しは 1024)

# 色(設計書 5.5 の「机と日誌」の色:夜の机の紺、ランプの灯り。赤は使わない)
NAVY_TOP, NAVY_BOTTOM, NAVY_RAY, LAMP = 0x2A3E53, 0x121B27, 0x40607F, 0xE9B868
AMBER_TOP, AMBER_BOTTOM, AMBER_SIDE = 0xFFE36E, 0xF28A12, 0x9A5410
CREAM, INK = 0xFFF8E6, 0x0C1420


def font_path(name):
    path = os.path.join(FONT_DIR, name)
    if not os.path.exists(path):
        os.makedirs(FONT_DIR, exist_ok=True)
        urllib.request.urlretrieve(FONT_URLS[name], path)
    return path


def rgb(h):
    return np.array([(h >> 16) & 255, (h >> 8) & 255, h & 255], dtype=np.float32) / 255


def over(base, color, alpha):
    a = alpha[..., None]
    return base * (1 - a) + color * a


def glyph_layer(text, font, size, center, skew=0.0, angle=0.0):
    """文字の形。字面の中心を center に合わせ、斜体(skew)と回転(angle。反時計回り)をかける"""
    f = ImageFont.truetype(font_path(font), size)
    layer = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(layer)
    l, t, r, b = d.textbbox((0, 0), text, font=f)
    cx, cy = center
    d.text((cx - (l + r) / 2, cy - (t + b) / 2), text, font=f, fill=255)
    if skew:
        layer = layer.transform((S, S), Image.AFFINE, (1, skew, -skew * cy, 0, 1, 0), resample=Image.BICUBIC)
    if angle:
        layer = layer.rotate(angle, resample=Image.BICUBIC, center=(cx, cy))
    return layer


def dilate(alpha, r):
    """形を半径 r だけ太らせる(なめらかなふち)"""
    dist = ndimage.distance_transform_edt(alpha < 0.5)
    return np.clip(r + 0.5 - dist, 0, 1)


def shift(a, dx, dy):
    return ndimage.shift(a, (dy, dx), order=1, mode="constant", cval=0)


def background(seed):
    """紺のグラデーション、中心の灯り、集中線(外から中心へ細くなる線。中心の近くは空ける)"""
    y, x = np.mgrid[0:S, 0:S].astype(np.float32)
    cx, cy = S / 2, S * 0.48
    dist = np.hypot(x - cx, y - cy)
    t = np.clip(dist / (S * 0.75), 0, 1)[..., None]
    img = rgb(NAVY_TOP) * (1 - t) + rgb(NAVY_BOTTOM) * t
    img = over(img, rgb(LAMP), np.clip(1 - dist / (S * 0.42), 0, 1) ** 2 * 0.35)
    rays = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(rays)
    rnd = random.Random(seed)
    n = 72
    for i in range(n):
        a = (i + rnd.uniform(-0.35, 0.35)) / n * 2 * math.pi
        w = rnd.uniform(0.010, 0.030)
        inner = S * rnd.uniform(0.36, 0.46)
        outer = S * 1.1
        d.polygon(
            [
                (cx + inner * math.cos(a), cy + inner * math.sin(a)),
                (cx + outer * math.cos(a - w), cy + outer * math.sin(a - w)),
                (cx + outer * math.cos(a + w), cy + outer * math.sin(a + w)),
            ],
            fill=255,
        )
    fade = np.clip((dist - S * 0.34) / (S * 0.25), 0, 1)
    return over(img, rgb(NAVY_RAY), np.asarray(rays, dtype=np.float32) / 255 * fade * 0.55)


def title(img, glyph, inner_r=24, outer_w=30, depth=(16, 34), steps=16):
    """アニメのタイトルロゴの重ね方"""
    a = np.asarray(glyph, dtype=np.float32) / 255
    a_inner = dilate(a, inner_r)
    side = np.zeros_like(a)
    for k in range(1, steps + 1):
        side = np.maximum(side, shift(a_inner, depth[0] * k / steps, depth[1] * k / steps))
    a_outer = dilate(np.maximum(a_inner, side), outer_w)
    drop = ndimage.gaussian_filter(shift(a_outer, 10, 26), 22)
    img = over(img, np.zeros(3, dtype=np.float32), drop * 0.55)
    img = over(img, rgb(INK), a_outer)
    img = over(img, rgb(AMBER_SIDE), side)
    img = over(img, rgb(CREAM), a_inner)
    rows = np.nonzero(a.max(axis=1) > 0.5)[0]
    top, bottom = rows.min(), rows.max()
    t = np.clip((np.arange(S, dtype=np.float32) - top) / max(1, bottom - top), 0, 1)[:, None, None]
    img = img * (1 - a[..., None]) + (rgb(AMBER_TOP) * (1 - t) + rgb(AMBER_BOTTOM) * t) * a[..., None]
    return over(img, rgb(0xFFFFFF), a * np.clip(1 - t[..., 0] / 0.45, 0, 1) * 0.3)


def sparkle(img, cx, cy, r):
    """キラッ(4 つの角の星)と、まわりの光"""
    pts = []
    for k in range(8):
        ang = k * math.pi / 4 - math.pi / 2
        rr = r if k % 2 == 0 else r * 0.2
        pts.append((cx + rr * math.cos(ang), cy + rr * math.sin(ang)))
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).polygon(pts, fill=255)
    halo = np.asarray(m.filter(ImageFilter.GaussianBlur(r * 0.35)), dtype=np.float32) / 255
    img = over(img, rgb(0xFFE9A8), np.clip(halo * 1.6, 0, 1) * 0.6)
    return over(img, rgb(0xFFFFFF), np.asarray(m, dtype=np.float32) / 255)


def render(variant):
    if variant in ("a", "a2"):
        img = background(7)
        font, size = ("DelaGothicOne-Regular.ttf", 1240) if variant == "a" else ("ZenMaruGothic-Black.ttf", 1240)
        img = title(img, glyph_layer("ツ", font, size, (S * 0.48, S * 0.51), skew=0.1, angle=5))
        return sparkle(img, S * 0.78, S * 0.23, 150)
    if variant == "b":
        img = background(11)
        img = title(img, glyph_layer("机", "DelaGothicOne-Regular.ttf", 1040, (S * 0.49, S * 0.49), skew=0.1, angle=4))
        return sparkle(img, S * 0.8, S * 0.21, 140)
    if variant == "c":
        img = background(3)
        g = Image.new("L", (S, S), 0)
        for text, size, c, ang in (("ツ", 660, (0.26, 0.47), 8), ("ク", 540, (0.52, 0.43), -4), ("エ", 540, (0.76, 0.53), 6)):
            g = ImageChops.lighter(g, glyph_layer(text, "DelaGothicOne-Regular.ttf", size, (S * c[0], S * c[1]), skew=0.12, angle=ang))
        img = title(img, g, inner_r=18, outer_w=24, depth=(12, 26))
        return sparkle(img, S * 0.82, S * 0.2, 110)
    raise SystemExit(f"案がありません: {variant}")


def to_image(img):
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
    p.add_argument("--variant", default="a", choices=["a", "a2", "b", "c"])
    p.add_argument("--out", default=ICON)
    p.add_argument("--preview")
    a = p.parse_args()
    icon = to_image(render(a.variant))
    icon.save(a.out, optimize=True)
    if a.preview:
        preview(icon, a.preview)
    print(f"{a.out} を作りました")


if __name__ == "__main__":
    main()

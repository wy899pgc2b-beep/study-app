#!/usr/bin/env python3
"""ツクエログのアプリアイコンを作る(決定事項 D-22。利用者の考えたデザインを、細部を整えて仕上げたもの)。

利用者の考えた形:
  - ベースは真っ白。上 7 割にエメラルドグリーンの横長の板と、平仮名の「つくえ」(白)。下 3 割に黒い「Log」
  - 文字は、アプリの画面と同じ丸い Zen Maru Gothic。「つくえ」は太く、できる限り大きく
仕上げで整えたところ:
  - 余白:板の上と左右の余白を同じにし、「Log」は板の下の空きの真ん中に置く(板と「Log」がひとまとまりに見える)
  - 板:角を少しだけ丸くする(丸い文字と、アイコン自体の角の丸みにそろえる)。緑は上から下へわずかに深くし、
    白い文字を読みやすくする。板の下にごく薄い影
  - 字間:「く」のまわりは空いて見えるので、字の形の左右の空きの量で測って、見た目の字間をそろえる
  - 「Log」:小さな画面でも読めるように少し大きくし、字間をわずかに広げる。黒は緑になじむ深い黒
  - iOS 18 からのダークモードと、色合い付き(Tinted)のアイコンも作る
文字は Zen Maru Gothic(SIL Open Font License。初めて動かすときに google/fonts から取ってくる。リポジトリには入れない)。
2 倍の大きさ(2048)で描いて 1024 に縮め、ふちをなめらかにする。ふつうのアイコンには透明な部分を作らない(App Store の決まり)。

使い方(pillow・numpy・scipy が要る):
  python3 make_icon.py                     # Resources/Assets.xcassets/AppIcon.appiconset に、ふつう・ダーク・色合い付きの 3 枚を書く
  python3 make_icon.py --preview p.png     # 角の丸い形で切った、ホーム画面の大きさの見本
"""

import argparse
import json
import os
import urllib.request

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.dirname(HERE)
ICONSET = os.path.join(APP, "Resources/Assets.xcassets/AppIcon.appiconset")
FONT_DIR = os.path.join(APP, ".icon-fonts")
FONT_URL = "https://raw.githubusercontent.com/google/fonts/main/ofl/zenmarugothic/"
TITLE_FONT = "ZenMaruGothic-Black.ttf"  # 「つくえ」
LOG_FONT = "ZenMaruGothic-Bold.ttf"  # 「Log」

S = 2048  # 描く大きさ(書き出しは 1024)
U = S / 1024  # 1024 の大きさでの 1 ピクセル

# 形(1024 の大きさで)。板は上 7 割の中、「Log」は下 3 割の中
MARGIN = 100  # 板の上と左右の余白
PLATE_BOTTOM = 600
PLATE_RADIUS = 56  # 板の角の丸み
TEXT_PAD = 62  # 「つくえ」の左右の余白(板の中)
LOG_CAP = 124  # 「Log」の大文字の高さ
LOG_CENTER = 800  # 「Log」の大文字の真ん中(板の下の空きの真ん中より、少し上)

# 色。ふつう・ダーク・色合い付き
THEMES = {
    "light": dict(base=0xFFFFFF, plate=(0x07AC71, 0x00925F), text=0xFFFFFF, log=0x16211D, shadow=0.16),
    "dark": dict(base=0x0F1513, plate=(0x16BD84, 0x04A36B), text=0xFFFFFF, log=0xEEF3F1, shadow=0.0),
    "tinted": dict(base=0x000000, plate=(0x9A9A9A, 0x808080), text=0xFFFFFF, log=0xE2E2E2, shadow=0.0),
}


def font(name, size):
    path = os.path.join(FONT_DIR, name)
    if not os.path.exists(path):
        os.makedirs(FONT_DIR, exist_ok=True)
        urllib.request.urlretrieve(FONT_URL + name, path)
    return ImageFont.truetype(path, round(size))


def rgb(h):
    return np.array([(h >> 16) & 255, (h >> 8) & 255, h & 255], dtype=np.float32) / 255


def over(base, color, alpha):
    a = alpha[..., None]
    return base * (1 - a) + color * a


def glyph_mask(ch, f):
    """1 字の形(0〜1)と、書くときの原点からのずれ。実際に描いた字の形の外枠で切り出す
    (getbbox は、字によっては字の形ではなく字の枠全体を返すため)"""
    l, t, r, b = f.getbbox(ch)
    pad = 8
    im = Image.new("L", (r - l + 2 * pad, b - t + 2 * pad), 0)
    ImageDraw.Draw(im).text((pad - l, pad - t), ch, font=f, fill=255)
    a = np.asarray(im, dtype=np.float32) / 255
    rows = np.nonzero(a.max(axis=1) > 0.02)[0]
    cols = np.nonzero(a.max(axis=0) > 0.02)[0]
    a = a[rows.min() : rows.max() + 1, cols.min() : cols.max() + 1]
    return a, (l - pad + cols.min(), t - pad + rows.min())


def optical_gaps(masks, tops, size):
    """見た目の字間をそろえる。隣り合う 2 字の、両方に字の形がある行ごとの左右の空きの平均が同じになるように、
    字の外枠のあいだを決める。空きが大きすぎる行(「く」の口の中など)は、上限で打ち切って数える"""
    target, cap, clear = size * 0.16, size * 0.3, size * 0.06
    gaps = []
    for (a, ta), (b, tb) in zip(zip(masks, tops), zip(masks[1:], tops[1:])):
        top = min(ta, tb)
        bottom = max(ta + a.shape[0], tb + b.shape[0])
        d = []
        for y in range(top, bottom):
            ra = a[y - ta] if ta <= y < ta + a.shape[0] else None
            rb = b[y - tb] if tb <= y < tb + b.shape[0] else None
            ia = np.nonzero(ra > 0.5)[0] if ra is not None else []
            ib = np.nonzero(rb > 0.5)[0] if rb is not None else []
            if len(ia) and len(ib):
                d.append((a.shape[1] - 1 - ia.max()) + ib.min())
            else:
                d.append(np.inf)
        d = np.array(d, dtype=np.float64)
        d = d[np.isfinite(d)]
        lo, hi = -size, size
        for _ in range(40):
            g = (lo + hi) / 2
            if np.minimum(d + g, cap).mean() < target:
                lo = g
            else:
                hi = g
        g = (lo + hi) / 2
        g = max(g, clear - d.min())  # 字どうしが近づきすぎない
        gaps.append(g)
    return gaps


def title_layer(text, width, center):
    """「つくえ」を、見た目の字間をそろえて、幅 width に収まる大きさで並べる"""
    size = S * 0.25
    for _ in range(4):
        f = font(TITLE_FONT, size)
        glyphs = [glyph_mask(ch, f) for ch in text]
        masks = [m for m, _ in glyphs]
        tops = [off[1] for _, off in glyphs]
        gaps = optical_gaps(masks, tops, size)
        total = sum(m.shape[1] for m in masks) + sum(gaps)
        size *= width / total
    top = min(tops)
    height = max(t + m.shape[0] for m, t in zip(masks, tops)) - top
    layer = np.zeros((S, S), dtype=np.float32)
    x = center[0] - total / 2
    y0 = center[1] - height / 2
    for i, (m, t) in enumerate(zip(masks, tops)):
        ys, xs = int(round(y0 + t - top)), int(round(x))
        region = layer[ys : ys + m.shape[0], xs : xs + m.shape[1]]
        layer[ys : ys + m.shape[0], xs : xs + m.shape[1]] = np.maximum(region, m)
        x += m.shape[1] + (gaps[i] if i < len(gaps) else 0)
    return layer


def log_layer(center_y, cap_height, tracking=0.03):
    """「Log」。大文字の高さ(L の上から字の線まで)を cap_height にし、その真ん中を center_y に合わせる。字間をわずかに広げる"""
    size = cap_height * 1.4
    for _ in range(3):
        f = font(LOG_FONT, size)
        l_box = f.getbbox("L")
        size *= cap_height / (l_box[3] - l_box[1])
    f = font(LOG_FONT, size)
    l_box = f.getbbox("L")
    advances = [f.getlength(ch) for ch in "Log"]
    width = sum(advances) + size * tracking * 2
    im = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(im)
    x = S / 2 - width / 2
    y = center_y - (l_box[3] + l_box[1]) / 2
    for ch, adv in zip("Log", advances):
        d.text((x, y), ch, font=f, fill=255)
        x += adv + size * tracking
    layer = np.asarray(im, dtype=np.float32) / 255
    # 字の形で測って、左右の真ん中に置き直す
    cols = np.nonzero(layer.max(axis=0) > 0.5)[0]
    return ndimage.shift(layer, (0, S / 2 - (cols.min() + cols.max()) / 2), order=1)


def plate_mask():
    im = Image.new("L", (S, S), 0)
    ImageDraw.Draw(im).rounded_rectangle(
        (MARGIN * U, MARGIN * U, S - MARGIN * U, PLATE_BOTTOM * U), radius=PLATE_RADIUS * U, fill=255)
    return np.asarray(im, dtype=np.float32) / 255


def render(theme="light"):
    c = THEMES[theme]
    y = np.arange(S, dtype=np.float32)[:, None, None]
    img = np.ones((S, S, 3), dtype=np.float32) * rgb(c["base"])
    plate = plate_mask()
    if c["shadow"]:
        shadow = ndimage.gaussian_filter(ndimage.shift(plate, (10 * U, 0), order=1), 18 * U)
        img = over(img, rgb(0x0A3A28), shadow * c["shadow"])
    t = np.clip((y - MARGIN * U) / ((PLATE_BOTTOM - MARGIN) * U), 0, 1)
    grad = rgb(c["plate"][0]) * (1 - t) + rgb(c["plate"][1]) * t
    img = img * (1 - plate[..., None]) + grad * plate[..., None]
    center = (S / 2, (MARGIN + PLATE_BOTTOM) / 2 * U - 4 * U)  # 見た目の真ん中(わずかに上)
    title = title_layer("つくえ", S - 2 * (MARGIN + TEXT_PAD) * U, center)
    img = over(img, rgb(c["text"]), title)
    img = over(img, rgb(c["log"]), log_layer(LOG_CENTER * U, LOG_CAP * U))
    out = Image.fromarray(np.clip(img * 255 + 0.5, 0, 255).astype(np.uint8), "RGB")
    return out.resize((1024, 1024), Image.LANCZOS)


def write_iconset():
    names = {"light": "icon-1024.png", "dark": "icon-1024-dark.png", "tinted": "icon-1024-tinted.png"}
    images = []
    for theme, name in names.items():
        im = render(theme)
        if theme == "tinted":
            im = im.convert("L").convert("RGB")
        im.save(os.path.join(ICONSET, name), optimize=True)
        entry = {"filename": name, "idiom": "universal", "platform": "ios", "size": "1024x1024"}
        if theme != "light":
            entry = {"appearances": [{"appearance": "luminosity", "value": theme}], **entry}
        images.append(entry)
    with open(os.path.join(ICONSET, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=2, ensure_ascii=False)
        f.write("\n")


def squircle(im, n):
    """iOS のアイコンに近い、角の丸い形で切る(見本用)"""
    m = n * 4
    yy, xx = np.mgrid[0:m, 0:m].astype(np.float32)
    u, v = np.abs((xx + 0.5) / m * 2 - 1), np.abs((yy + 0.5) / m * 2 - 1)
    mask = Image.fromarray(((u**5 + v**5) <= 1).astype(np.uint8) * 255, "L").resize((n, n), Image.LANCZOS)
    out = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    out.paste(im.resize((n, n), Image.LANCZOS), (0, 0), mask)
    return out


def preview(path):
    """大きい表示と、ホーム画面(60pt@3x=180px)・設定(29pt@3x=87px)の大きさ。下の段は、ダークと色合い付き"""
    light, dark, tinted = render("light"), render("dark"), render("tinted").convert("L").convert("RGB")
    sheet = Image.new("RGB", (900, 560), (236, 233, 226))
    d = ImageDraw.Draw(sheet)
    d.rectangle([460, 0, 900, 280], fill=(206, 222, 236))
    d.rectangle([460, 280, 900, 560], fill=(28, 30, 36))
    big = squircle(light, 420)
    sheet.paste(big, (20, 70), big)
    for im, x, y, n in ((light, 500, 50, 180), (light, 730, 96, 87), (dark, 500, 330, 180), (tinted, 730, 376, 87)):
        s = squircle(im, n)
        sheet.paste(s, (x, y), s)
    sheet.save(path)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--preview")
    a = p.parse_args()
    if a.preview:
        preview(a.preview)
        print(f"{a.preview} を作りました")
        return
    write_iconset()
    print(f"{ICONSET} に 3 枚を書きました")


if __name__ == "__main__":
    main()

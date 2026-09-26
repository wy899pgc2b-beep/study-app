#!/usr/bin/env python3
"""ツクエログのアプリアイコンを作る(決定事項 D-22。利用者の考えたデザイン)。

  - 正方形を、上 7 割と下 3 割に分ける。ベースは真っ白
  - 上 7 割:エメラルドグリーンの横長の長方形に、平仮名で「つくえ」
    (文字の色は 白・黒・グレー・藍色 から選ぶ)
  - 下 3 割:黒い文字で「Log」
文字はアプリの画面と同じ Zen Maru Gothic(丸みがあって親しみやすい。SIL Open Font License。
初めて動かすときに google/fonts から取ってくる。リポジトリには入れない)。
「つくえ」はいちばん太い Black で、長方形の中にできる限り大きく入れる。「Log」は Bold。
字と字のあいだは字の形の幅で測ってそろえ、それぞれの場所の真ん中に置く。
2 倍の大きさ(2048)で描いて 1024 に縮め、ふちをなめらかにする。透明な部分は作らない(App Store の決まり)。

使い方(pillow・numpy が要る):
  python3 make_icon.py                                   # Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png を作り直す
  python3 make_icon.py --text-color indigo --band full --out x.png
      --text-color:white・black・gray・indigo(「つくえ」の色)
      --band:inset(上 7 割の中に、白いふちを残して長方形を置く)・full(上 7 割を全部、長方形にする)
  python3 make_icon.py --preview preview.png             # 角の丸い形で切った、ホーム画面の大きさの見本
"""

import argparse
import os
import urllib.request

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.dirname(HERE)
ICON = os.path.join(APP, "Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
FONT_DIR = os.path.join(APP, ".icon-fonts")
FONT_URL = "https://raw.githubusercontent.com/google/fonts/main/ofl/zenmarugothic/"
TITLE_FONT = "ZenMaruGothic-Black.ttf"  # 「つくえ」
LOG_FONT = "ZenMaruGothic-Bold.ttf"  # 「Log」

S = 2048  # 描く大きさ(書き出しは 1024)
SPLIT = 0.7  # 上 7 割と下 3 割の境

WHITE = (255, 255, 255)
EMERALD = (0, 169, 104)  # エメラルドグリーン(JIS の慣用色名 #00A968)
LOG = (17, 17, 17)  # 「Log」の黒
TEXT_COLORS = {
    "white": (255, 255, 255),
    "black": (17, 17, 17),
    "gray": (88, 88, 88),
    "indigo": (22, 94, 131),  # 藍色(JIS の慣用色名 #165E83)
}


def font(name, size):
    path = os.path.join(FONT_DIR, name)
    if not os.path.exists(path):
        os.makedirs(FONT_DIR, exist_ok=True)
        urllib.request.urlretrieve(FONT_URL + name, path)
    return ImageFont.truetype(path, round(size))


def band_box(band):
    """上 7 割の中の、エメラルドグリーンの長方形(左, 上, 右, 下)"""
    if band == "full":
        return (0, 0, S, S * SPLIT)
    # 白いふちを残した横長の長方形(上 7 割の真ん中。横:縦 = 約 1.7:1)
    w, h = S * 0.8, S * 0.47
    cy = S * SPLIT / 2
    return (S / 2 - w / 2, cy - h / 2, S / 2 + w / 2, cy + h / 2)


def draw_spaced(d, text, size, center, gap_ratio, color, fit_width=None, fit_height=None):
    """字の形の幅で測って、字と字のあいだを等しくして並べる。行の上下は、字の形のいちばん上と下で測る。
    fit_width・fit_height を渡すと、その中に収まるいちばん大きい大きさにする"""
    for _ in range(4):
        f = font(TITLE_FONT, size)
        boxes = [f.getbbox(ch) for ch in text]
        gap = size * gap_ratio
        width = sum(b[2] - b[0] for b in boxes) + gap * (len(text) - 1)
        top, bottom = min(b[1] for b in boxes), max(b[3] for b in boxes)
        scale = min(fit_width / width if fit_width else 1, fit_height / (bottom - top) if fit_height else 1)
        if abs(scale - 1) < 0.005:
            break
        size *= scale
    x = center[0] - width / 2
    y = center[1] - (bottom + top) / 2
    for ch, b in zip(text, boxes):
        d.text((x - b[0], y), ch, font=f, fill=color)
        x += b[2] - b[0] + gap


def draw_log(d, center_y, cap_height):
    """「Log」。大文字の高さ(L の上から字の線まで)を cap_height にし、その真ん中を center_y に合わせる(g の下は線の下に出る)"""
    size = cap_height * 1.5
    for _ in range(3):
        f = font(LOG_FONT, size)
        l_box = f.getbbox("L")
        size *= cap_height / (l_box[3] - l_box[1])
    f = font(LOG_FONT, size)
    l_box = f.getbbox("L")
    full = f.getbbox("Log")
    x = S / 2 - (full[2] + full[0]) / 2
    y = center_y - (l_box[3] + l_box[1]) / 2
    d.text((x, y), "Log", font=f, fill=LOG)


def render(text_color="white", band="inset"):
    img = Image.new("RGB", (S, S), WHITE)
    d = ImageDraw.Draw(img)
    box = band_box(band)
    d.rectangle(box, fill=EMERALD)
    bw, bh = box[2] - box[0], box[3] - box[1]
    # できる限り大きく:長方形の幅から、左右に少しだけ余白を残す
    draw_spaced(
        d, "つくえ", S * 0.2, ((box[0] + box[2]) / 2, (box[1] + box[3]) / 2), 0.04, TEXT_COLORS[text_color],
        fit_width=bw * (0.88 if band == "inset" else 0.8), fit_height=bh * (0.8 if band == "inset" else 0.6))
    draw_log(d, S * (SPLIT + (1 - SPLIT) / 2) - S * 0.012, S * 0.105)
    return img.resize((1024, 1024), Image.LANCZOS)


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
    sheet = Image.new("RGB", (900, 560), (236, 233, 226))
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
    p.add_argument("--text-color", default="white", choices=sorted(TEXT_COLORS))
    p.add_argument("--band", default="inset", choices=["inset", "full"])
    p.add_argument("--out", default=ICON)
    p.add_argument("--preview")
    a = p.parse_args()
    icon = render(a.text_color, a.band)
    icon.save(a.out, optimize=True)
    if a.preview:
        preview(icon, a.preview)
    print(f"{a.out} を作りました")


if __name__ == "__main__":
    main()

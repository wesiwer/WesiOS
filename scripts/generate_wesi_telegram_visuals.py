#!/usr/bin/env python3
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import math
import random

W, H = 1280, 720
OUT = Path("build/wesi_telegram_visuals")
OUT.mkdir(parents=True, exist_ok=True)

BG = (5, 7, 12)
FG = (242, 245, 250)
MUTED = (126, 136, 156)
GRID = (27, 33, 46)

CARDS = {
    "brief": ("EXECUTIVE BRIEF", "BUSINESS AT A GLANCE", (105, 92, 255), "orbit"),
    "cash": ("CASH", "LIVE FINANCIAL POSITION", (44, 232, 180), "flow"),
    "risk": ("RISK", "EARLY WARNING SYSTEM", (255, 77, 106), "pulse"),
    "today": ("TODAY", "FOCUS / EXECUTION", (65, 176, 255), "steps"),
    "overdue": ("OVERDUE", "ATTENTION REQUIRED", (255, 169, 64), "clock"),
    "push": ("SIGNAL", "WESIOS NOTIFICATION CHANNEL", (190, 91, 255), "signal"),
    "farewell": ("THANK YOU", "A CHAPTER ENDS. THE STORY CONTINUES.", (127, 143, 166), "horizon"),
}


def font(size, bold=False):
    candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation2/LiberationSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf",
    ]
    for p in candidates:
        if Path(p).exists():
            return ImageFont.truetype(p, size=size)
    return ImageFont.load_default()


def glow(layer, radius=28):
    return layer.filter(ImageFilter.GaussianBlur(radius))


def line(draw, pts, fill, width=2):
    draw.line(pts, fill=fill, width=width, joint="curve")


def draw_grid(draw):
    for x in range(0, W, 64):
        draw.line((x, 0, x, H), fill=GRID, width=1)
    for y in range(0, H, 64):
        draw.line((0, y, W, y), fill=GRID, width=1)


def visual(kind, title, subtitle, accent, motif):
    img = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(img)
    draw_grid(draw)

    # Soft depth bands.
    haze = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    hd = ImageDraw.Draw(haze)
    for r, alpha in [(360, 26), (260, 38), (170, 48)]:
        hd.ellipse((W-540-r//2, -80-r//2, W-540+r*2, -80+r*2), fill=(*accent, alpha))
    img = Image.alpha_composite(img.convert("RGBA"), glow(haze, 55))
    draw = ImageDraw.Draw(img)

    # Premium glass panel.
    panel = (52, 52, W-52, H-52)
    draw.rounded_rectangle(panel, radius=34, fill=(9, 12, 19, 218), outline=(51, 58, 76, 180), width=2)
    draw.rounded_rectangle((76, 76, 234, 112), radius=18, fill=(*accent, 34), outline=(*accent, 115), width=1)
    draw.text((96, 84), "WESIOS", font=font(20, True), fill=(*accent, 255))

    # Motifs live on the right and never fight with the text.
    md = ImageDraw.Draw(img)
    cx, cy = 965, 355
    if motif == "orbit":
        for r in (70, 125, 182):
            md.ellipse((cx-r, cy-r, cx+r, cy+r), outline=(*accent, 90), width=2)
        for a in (0.2, 2.2, 4.5):
            x = cx + math.cos(a)*182
            y = cy + math.sin(a)*182
            md.ellipse((x-8, y-8, x+8, y+8), fill=(*accent, 255))
        md.ellipse((cx-32, cy-32, cx+32, cy+32), fill=(*accent, 210))
    elif motif == "flow":
        pts = []
        for i in range(9):
            x = 760 + i*55
            y = 420 - (i*23 + math.sin(i*1.4)*55)
            pts.append((x, y))
        line(md, pts, (*accent, 230), 7)
        for x, y in pts:
            md.ellipse((x-7, y-7, x+7, y+7), fill=(*accent, 255))
        md.line((750, 490, 1210, 490), fill=(80, 89, 110, 180), width=2)
    elif motif == "pulse":
        pts = [(735, 360), (825, 360), (875, 260), (930, 465), (990, 315), (1040, 360), (1210, 360)]
        line(md, pts, (*accent, 255), 8)
        md.ellipse((905, 335, 955, 385), outline=(*accent, 120), width=3)
    elif motif == "steps":
        for i, y in enumerate((485, 405, 325, 245)):
            x = 770 + i*105
            md.rounded_rectangle((x, y, x+82, 540), radius=15, fill=(*accent, 28+i*28), outline=(*accent, 110+i*25), width=2)
            md.ellipse((x+30, y-10, x+50, y+10), fill=(*accent, 255))
    elif motif == "clock":
        r = 165
        md.ellipse((cx-r, cy-r, cx+r, cy+r), outline=(*accent, 190), width=5)
        md.line((cx, cy, cx, cy-94), fill=(*accent, 255), width=8)
        md.line((cx, cy, cx+76, cy+44), fill=(*accent, 255), width=8)
        md.ellipse((cx-10, cy-10, cx+10, cy+10), fill=(*accent, 255))
    elif motif == "signal":
        for r, alpha in ((55, 230), (105, 160), (160, 95), (215, 50)):
            md.arc((cx-r, cy-r, cx+r, cy+r), 215, 325, fill=(*accent, alpha), width=9)
        md.ellipse((cx-17, cy+75, cx+17, cy+109), fill=(*accent, 255))
    elif motif == "horizon":
        md.line((730, 410, 1210, 410), fill=(*accent, 170), width=2)
        for i in range(8):
            x = 730 + i*68
            top = 410 - (35 + i*15)
            md.line((x, 410, x, top), fill=(*accent, 80+i*12), width=2)
        md.arc((825, 240, 1105, 520), 200, 340, fill=(*accent, 170), width=4)

    # Typography.
    draw.text((94, 220), title, font=font(67, True), fill=FG)
    draw.text((98, 303), subtitle, font=font(23, False), fill=MUTED)
    draw.rounded_rectangle((96, 372, 470, 378), radius=3, fill=(*accent, 230))
    draw.text((96, 425), "BUSINESS OPERATING SYSTEM", font=font(18, True), fill=(186, 194, 210))
    draw.text((96, 468), "secure • contextual • real-time", font=font(17), fill=(98, 109, 130))

    # Footer signature.
    draw.text((96, 620), "WESI / TELEGRAM", font=font(14, True), fill=(86, 96, 117))
    draw.text((1085, 620), "LIVE", font=font(14, True), fill=(*accent, 210))
    draw.ellipse((1058, 625, 1067, 634), fill=(*accent, 255))

    # Subtle grain for less sterile look.
    px = img.load()
    rnd = random.Random(20260818 + len(kind))
    for _ in range(16000):
        x = rnd.randrange(W)
        y = rnd.randrange(H)
        r, g, b, a = px[x, y]
        n = rnd.choice((-4, -3, -2, 2, 3, 4))
        px[x, y] = (max(0, min(255, r+n)), max(0, min(255, g+n)), max(0, min(255, b+n)), a)

    out = OUT / f"{kind}.jpg"
    img.convert("RGB").save(out, "JPEG", quality=91, optimize=True, progressive=True)
    print(out)


for key, values in CARDS.items():
    visual(key, *values)

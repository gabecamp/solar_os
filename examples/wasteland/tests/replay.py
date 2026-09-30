import sys
from PIL import Image, ImageDraw, ImageFont

W, H, SCALE = 300, 400, 2
GRAY = {"WHITE": 255, "LIGHT": 190, "DARK": 105, "BLACK": 0}

def replay(ops_path, out_path):
    img = Image.new("L", (W, H), 255)
    d = ImageDraw.Draw(img)
    try:
        mono = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 11)
        bold = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf", 13)
    except Exception:
        mono = bold = ImageFont.load_default()
    for line in open(ops_path).read().splitlines():
        p = line.split("\t")
        op = p[0]
        if op == "clear":
            d.rectangle([0, 0, W, H], fill=GRAY[p[1]])
        elif op == "fillrect":
            x, y, w, h = map(int, p[1:5]); d.rectangle([x, y, x + w - 1, y + h - 1], fill=GRAY[p[5]])
        elif op == "rect":
            x, y, w, h = map(int, p[1:5]); d.rectangle([x, y, x + w - 1, y + h - 1], outline=GRAY[p[5]])
        elif op == "line":
            x0, y0, x1, y1 = map(int, p[1:5]); d.line([x0, y0, x1, y1], fill=GRAY[p[5]])
        elif op == "circle":
            x, y, r = map(int, p[1:4]); d.ellipse([x - r, y - r, x + r, y + r], outline=GRAY[p[4]])
        elif op == "fillcircle":
            x, y, r = map(int, p[1:4]); d.ellipse([x - r, y - r, x + r, y + r], fill=GRAY[p[4]])
        elif op == "pixel":
            d.point((int(p[1]), int(p[2])), fill=GRAY[p[3]])
        elif op == "sprite":
            x, y, w, h = map(int, p[1:5]); col = GRAY[p[5]]; data = bytes.fromhex(p[6])
            bpr = (w + 7) // 8
            for row in range(h):
                for col_x in range(w):
                    if (data[row * bpr + col_x // 8] >> (col_x % 8)) & 1:
                        d.point((x + col_x, y + row), fill=col)
        elif op == "text":
            x, y = int(p[1]), int(p[2]); col = GRAY[p[3]]; font = bold if p[4] == "BOLD14" else mono
            # y is a baseline; PIL anchors "ls" = left/baseline
            d.text((x, y), p[5], fill=col, font=font, anchor="ls")
    img = img.resize((W * SCALE, H * SCALE), Image.NEAREST)
    # frame so the screen edge is visible
    framed = Image.new("L", (W * SCALE + 8, H * SCALE + 8), 90)
    framed.paste(img, (4, 4))
    framed.save(out_path)

for name in ("inventory", "inventory_barefoot", "inventory_full", "inventory_dressed", "inventory_hands", "creator", "map", "map_explored", "map_scavenge", "map_full"):
    replay(f"ops_{name}.txt", f"preview_{name}.png")
print("ok")

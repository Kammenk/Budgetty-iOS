from PIL import Image, ImageDraw

S = 4                      # supersample factor
N = 1024
W = N * S

TOP = (0x7A, 0x63, 0xCB)
BOT = (0x4C, 0x38, 0x91)
MARK = (0x4F, 0x37, 0x8B)
WHITE = (255, 255, 255)


def s(v):
    return int(round(v * S))


# vertical gradient background
img = Image.new("RGB", (W, W))
d = ImageDraw.Draw(img)
for y in range(W):
    t = y / (W - 1)
    d.line(
        [(0, y), (W, y)],
        fill=tuple(round(TOP[i] + (BOT[i] - TOP[i]) * t) for i in range(3)),
    )

# receipt body: rounded top corners only, square bottom (zigzag drawn separately)
d.rounded_rectangle(
    [s(338), s(238), s(686), s(734)],
    radius=s(52),
    fill=WHITE,
    corners=(True, True, False, False),
)

# torn bottom edge: 4 downward teeth
valleys = [338, 425, 512, 599, 686]
apexes = [381.5, 468.5, 555.5, 642.5]
pts = [(s(338), s(733))]
for i, ax in enumerate(apexes):
    pts.append((s(ax), s(782)))
    pts.append((s(valleys[i + 1]), s(733)))
d.polygon(pts, fill=WHITE)

# two text bars
d.rounded_rectangle([s(384), s(350), s(638), s(386)], radius=s(18), fill=MARK)
d.rounded_rectangle([s(384), s(422), s(572), s(458)], radius=s(18), fill=MARK)

# checkmark: thick polyline with round caps + round join
check = [(412, 571), (484, 642), (632, 500)]
r = 20
for a, b in zip(check, check[1:]):
    d.line([(s(a[0]), s(a[1])), (s(b[0]), s(b[1]))], fill=MARK, width=s(r * 2))
for cx, cy in check:
    d.ellipse([s(cx - r), s(cy - r), s(cx + r), s(cy + r)], fill=MARK)

out = img.resize((N, N), Image.LANCZOS).convert("RGB")  # RGB => no alpha channel
out.save("icon_1024.png", "PNG")
print("wrote icon_1024.png", out.size, out.mode)

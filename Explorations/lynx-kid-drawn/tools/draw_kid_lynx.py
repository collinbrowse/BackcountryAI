# Draws the lynx as if a 3rd grader made it: wobbly marker lines gone over twice,
# crayon scribble fills that miss the edges, lined notebook paper.
import math, random, sys
random.seed(7)
W = H = 800
out = []

def wob(pts, closed=True, amt=4, step=18):
    """Subdivide a polyline and jitter it, returning a smooth SVG path."""
    seq = pts + ([pts[0]] if closed else [])
    dense = []
    for (x1, y1), (x2, y2) in zip(seq, seq[1:]):
        n = max(1, int(math.hypot(x2 - x1, y2 - y1) / step))
        for i in range(n):
            t = i / n
            dense.append((x1 + (x2 - x1) * t + random.uniform(-amt, amt),
                          y1 + (y2 - y1) * t + random.uniform(-amt, amt)))
    if not closed:
        dense.append((seq[-1][0] + random.uniform(-amt, amt), seq[-1][1] + random.uniform(-amt, amt)))
    else:
        dense.append(dense[0])
    d = f"M{dense[0][0]:.1f},{dense[0][1]:.1f}"
    for a, b in zip(dense[1:], dense[2:]):
        d += f" Q{a[0]:.1f},{a[1]:.1f} {(a[0]+b[0])/2:.1f},{(a[1]+b[1])/2:.1f}"
    d += f" L{dense[-1][0]:.1f},{dense[-1][1]:.1f}"
    return d

def ellipse(cx, cy, rx, ry, n=28, rot=0):
    r = math.radians(rot)
    return [(cx + rx * math.cos(a) * math.cos(r) - ry * math.sin(a) * math.sin(r),
             cy + rx * math.cos(a) * math.sin(r) + ry * math.sin(a) * math.cos(r))
            for a in [2 * math.pi * i / n for i in range(n)]]

clip_id = 0
def under(pts):
    out.append(f'<path d="{wob(pts, amt=2)}" fill="#FCFBF6"/>')

def scribble(pts, color, width=9, gap=11, angle=None, opacity=0.85, miss=7):
    """Crayon zigzag inside a shape (clipped to a slightly shrunken, shifted copy, so it misses the edges)."""
    global clip_id
    clip_id += 1
    cx = sum(p[0] for p in pts) / len(pts); cy = sum(p[1] for p in pts) / len(pts)
    dx, dy = random.uniform(-miss, miss), random.uniform(-miss, miss)
    shrunk = [(cx + (x - cx) * 0.93 + dx, cy + (y - cy) * 0.93 + dy) for x, y in pts]
    out.append(f'<clipPath id="c{clip_id}"><path d="{wob(shrunk, amt=3)}"/></clipPath>')
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
    x0, x1, y0, y1 = min(xs) - 20, max(xs) + 20, min(ys) - 20, max(ys) + 20
    ang = math.radians(angle if angle is not None else random.uniform(20, 70))
    # zigzag strokes along the angle
    zz = []
    diag = math.hypot(x1 - x0, y1 - y0)
    ux, uy = math.cos(ang), math.sin(ang)        # stroke direction
    vx, vy = -uy, ux                              # step direction
    mx, my = (x0 + x1) / 2, (y0 + y1) / 2
    k = -diag / 2
    flip = 1
    while k < diag / 2:
        px, py = mx + vx * k, my + vy * k
        zz.append((px + ux * diag / 2 * flip + random.uniform(-6, 6), py + uy * diag / 2 * flip + random.uniform(-6, 6)))
        flip *= -1
        k += gap + random.uniform(-3, 3)
    d = "M" + " L".join(f"{x:.1f},{y:.1f}" for x, y in zz)
    out.append(f'<path d="{d}" clip-path="url(#c{clip_id})" fill="none" stroke="{color}" stroke-width="{width}" '
               f'stroke-linejoin="round" stroke-linecap="round" opacity="{opacity}"/>')

def marker(pts, closed=True, color="#262422", width=5, twice=True, amt=4):
    for i in range(2 if twice else 1):
        out.append(f'<path d="{wob(pts, closed, amt=amt)}" fill="none" stroke="{color}" stroke-width="{width - i * 1.5}" '
                   f'stroke-linecap="round" stroke-linejoin="round" opacity="{0.95 if i == 0 else 0.7}"/>')

def blob(cx, cy, r, color, amt=2):
    out.append(f'<path d="{wob(ellipse(cx, cy, r, r * random.uniform(0.8, 1.1), n=10), amt=amt, step=6)}" fill="{color}"/>')

# Paper.
out.append('<rect width="800" height="800" fill="#FCFBF6"/>')
for y in range(110, 800, 42):
    out.append(f'<line x1="0" y1="{y}" x2="800" y2="{y}" stroke="#A9C6E8" stroke-width="2" opacity="0.7"/>')
out.append('<line x1="70" y1="0" x2="70" y2="800" stroke="#E79A9A" stroke-width="2.5"/>')

# Sun in the corner, with a face.
sun = ellipse(720, 80, 75, 75)
scribble(sun, "#FFD23F", width=12, gap=10, angle=10)
marker(sun, color="#E8A20C", width=4)
for a in range(100, 260, 26):
    r = math.radians(a)
    marker([(720 + 92 * math.cos(r), 80 - 92 * math.sin(r) * -1), (720 + 135 * math.cos(r), 80 + 135 * math.sin(r))],
           closed=False, color="#E8A20C", width=4, twice=False, amt=3)
blob(700, 72, 5, "#262422"); blob(735, 70, 5, "#262422")
marker([(694, 96), (715, 108), (738, 94)], closed=False, width=3.5, twice=False, amt=1.5)

# Mountains, lopsided.
for pts, snow in [([(60, 560), (230, 250), (390, 560)], [(185, 330), (230, 250), (270, 320), (248, 310), (230, 330), (210, 312)]),
                  ([(430, 560), (600, 300), (790, 560)], [(560, 365), (600, 300), (640, 360), (618, 352), (600, 372), (580, 352)])]:
    scribble(pts, "#8E8BC4", width=11, gap=12, angle=75)
    scribble(snow, "#FFFFFF", width=10, gap=8, angle=20, opacity=1, miss=2)
    marker(pts, color="#4F4A7A", width=4)
    marker(snow[3:] + [snow[0]], closed=False, color="#4F4A7A", width=3, twice=False, amt=2)

# Grass.
grass = [(0, 600), (800, 590), (800, 800), (0, 800)]
scribble(grass, "#7CC46A", width=14, gap=12, angle=80, opacity=0.9, miss=2)
for x in range(20, 800, 34):
    marker([(x, 610), (x + 6, 585), (x + 12, 608)], closed=False, color="#3E8C3A", width=3.5, twice=False, amt=2)

TAN, TAN_DARK, INK = "#E8A85A", "#B9772F", "#262422"

# Tail: a sausage sticking up on the right, black tip.
tail = [(520, 590), (585, 560), (640, 480), (660, 410), (690, 405), (685, 470), (640, 560), (560, 625)]
under(tail)
scribble(tail, TAN, width=11, gap=10, angle=60)
tip = [(648, 455), (660, 405), (692, 402), (690, 460), (668, 478)]
scribble(tip, "#2A2522", width=10, gap=6, angle=30, opacity=0.95, miss=2)
marker(tail)

# Body: a big lumpy potato.
body = ellipse(400, 560, 150, 120, n=14)
under(body)
scribble(body, TAN, width=12, gap=10, angle=35)
marker(body)

# Legs: four stubby sticks with toe lines.
for x in (300, 360, 440, 500):
    leg = [(x - 22, 630), (x + 22, 632), (x + 24, 700), (x - 24, 702)]
    scribble(leg, TAN, width=10, gap=9, angle=90)
    marker(leg)
    for t in (-8, 8):
        marker([(x + t, 690), (x + t, 701)], closed=False, width=3, twice=False, amt=1)

# Spots: dots, all different sizes.
for cx, cy, r in [(330, 520, 11), (380, 490, 8), (450, 510, 12), (500, 560, 9), (340, 590, 10), (420, 600, 13),
                  (480, 620, 7), (290, 560, 7), (600, 540, 8), (640, 500, 7)]:
    blob(cx, cy, r, "#6B3E1E")

# Head: way too big, a little squashed.
head = ellipse(400, 330, 150, 128, n=16, rot=-4)
ears = [[(282, 260), (290, 120), (370, 215)], [(430, 210), (515, 115), (520, 258)]]
for ear in ears:
    under(ear)
    scribble(ear, TAN, width=10, gap=9, angle=70)
    inner = [(ear[0][0] * 0.7 + ear[1][0] * 0.3 + 8, ear[0][1] * 0.6 + ear[1][1] * 0.4),
             (ear[1][0], ear[1][1] + 40), (ear[2][0] * 0.7 + ear[1][0] * 0.3 - 8, ear[2][1] * 0.75 + ear[1][1] * 0.25)]
    scribble(inner, "#F4A3B5", width=8, gap=7, angle=50, miss=3)
    marker(ear)
    # Tufts: three black lines straight up.
    tx, ty = ear[1]
    for dx, dy in [(-14, -42), (0, -50), (14, -40)]:
        marker([(tx, ty + 4), (tx + dx, ty + dy)], closed=False, width=5, twice=False, amt=2)
under(head)
scribble(head, TAN, width=12, gap=10, angle=25)
marker(head)

# Scarf: a blue band and a flap, colored hard.
scarf = [(290, 440), (510, 430), (515, 478), (288, 488)]
flap = [(440, 470), (510, 470), (470, 560)]
scribble(flap, "#2E6FE0", width=11, gap=7, angle=80, opacity=0.95, miss=3)
scribble(scarf, "#2E6FE0", width=12, gap=7, angle=5, opacity=0.95, miss=3)
marker(flap); marker(scarf)

# Face. Eyes don't quite match.
for cx, cy, r in [(345, 315, 24), (455, 310, 20)]:
    out.append(f'<path d="{wob(ellipse(cx, cy, r, r * 1.15, n=12), amt=1.5, step=6)}" fill="#FFFFFF"/>')
    marker(ellipse(cx, cy, r, r * 1.15, n=12), width=4, amt=1.5)
    blob(cx + 6, cy + 6, r * 0.5, INK, amt=1)
    blob(cx + 1, cy - 1, r * 0.17, "#FFFFFF", amt=0.5)
for cx, cy in [(310, 375), (495, 368)]:
    scribble(ellipse(cx, cy, 26, 18), "#F48FA6", width=7, gap=6, angle=10, miss=2)
nose = [(385, 352), (422, 350), (404, 375)]
out.append(f'<path d="{wob(nose, amt=1.5, step=6)}" fill="#F06C8C"/>')
marker(nose, width=4, amt=1.5)
# Big smile with a tongue.
marker([(404, 376), (404, 392)], closed=False, width=4, twice=False, amt=1)
smile = [(350, 385), (375, 420), (404, 392), (432, 420), (458, 383)]
marker(smile, closed=False, width=5, amt=2)
# Whiskers: three each side, all different lengths.
for (x0, y0, x1, y1) in [(330, 390, 200, 360), (330, 400, 190, 405), (332, 410, 215, 450),
                         (470, 385, 600, 350), (470, 395, 615, 398), (468, 405, 590, 445)]:
    marker([(x0, y0), (x1, y1)], closed=False, width=3, twice=False, amt=3)
# Forehead stripes.
for x in (375, 400, 425):
    marker([(x, 220), (x + 2, 250)], closed=False, color="#6B3E1E", width=6, twice=False, amt=2)

# Name, with one letter backwards.
out.append('<g font-family="Chalkboard SE, Comic Sans MS, Marker Felt" font-weight="bold" font-size="54" fill="#2E6FE0">'
           '<text x="110" y="93" transform="rotate(-4 110 93)">MY LYNX</text>'
           '<text transform="translate(146 160) rotate(-2) scale(-1 1)">S</text>'
           '<text x="148" y="160" transform="rotate(-2 148 160)">COUT</text></g>')

svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">' + "".join(out) + "</svg>"
open(sys.argv[1], "w").write(svg)
print("wrote", sys.argv[1])

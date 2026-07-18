"""Render captured RoomPlan geometry as top-down floor-plan PNGs.

Each surface arrives as {x, z, dx, dz, len_m} (world center, local-X direction
in the floor plane, length). Walls draw as dark lines, doors green/red by
walker clearance, windows blue, furniture as labeled gray boxes.
"""

import io
import math

from PIL import Image, ImageDraw, ImageFont

from config import WALKER_WIDTH_IN

SCALE = 70          # px per meter
PAD = 50
M_TO_IN = 39.3701


def _endpoints(s: dict) -> tuple[tuple[float, float], tuple[float, float]]:
    x, z = s["x"], s["z"]
    dx, dz = s.get("dx", 1.0), s.get("dz", 0.0)
    n = math.hypot(dx, dz) or 1.0
    hx, hz = dx / n * s["len_m"] / 2, dz / n * s["len_m"] / 2
    return (x - hx, z - hz), (x + hx, z + hz)


def _obj_corners(o: dict) -> list[tuple[float, float]]:
    x, z = o["x"], o["z"]
    dx, dz = o.get("dx", 1.0), o.get("dz", 0.0)
    n = math.hypot(dx, dz) or 1.0
    ux, uz = dx / n, dz / n           # local X in plane
    px, pz = -uz, ux                  # perpendicular
    hl, hd = o["len_m"] / 2, o.get("depth_m", 0.5) / 2
    return [(x + sx * ux * hl + sz * px * hd, z + sx * uz * hl + sz * pz * hd)
            for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))]


def render_room(fp: dict) -> Image.Image:
    pts: list[tuple[float, float]] = []
    for kind in ("walls", "doors", "openings", "windows"):
        for s in fp.get(kind) or []:
            pts.extend(_endpoints(s))
    for o in fp.get("objects") or []:
        pts.extend(_obj_corners(o))
    if not pts:
        img = Image.new("RGB", (420, 120), "white")
        ImageDraw.Draw(img).text((20, 50), f"{fp.get('room', 'room')}: no geometry",
                                 fill="#666")
        return img

    xs, zs = [p[0] for p in pts], [p[1] for p in pts]
    w = int((max(xs) - min(xs)) * SCALE) + 2 * PAD
    h = int((max(zs) - min(zs)) * SCALE) + 2 * PAD
    img = Image.new("RGB", (max(w, 320), max(h, 240)), "white")
    d = ImageDraw.Draw(img)

    def P(p: tuple[float, float]) -> tuple[float, float]:
        return (PAD + (p[0] - min(xs)) * SCALE, PAD + (p[1] - min(zs)) * SCALE)

    try:
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 15)
        small = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 12)
    except OSError:
        font = small = ImageFont.load_default()

    for o in fp.get("objects") or []:
        corners = [P(c) for c in _obj_corners(o)]
        d.polygon(corners, fill="#eef1f3", outline="#aab7b8")
        cx = sum(c[0] for c in corners) / 4
        cz = sum(c[1] for c in corners) / 4
        d.text((cx, cz), o.get("category", ""), fill="#7f8c8d",
               anchor="mm", font=small)

    for s in fp.get("walls") or []:
        a, b = _endpoints(s)
        d.line([P(a), P(b)], fill="#2c3e50", width=6)

    for s in fp.get("windows") or []:
        a, b = _endpoints(s)
        d.line([P(a), P(b)], fill="#5dade2", width=6)

    for kind, dashed in (("doors", False), ("openings", True)):
        for s in fp.get(kind) or []:
            w_in = round(s["width_m"] * M_TO_IN, 1)
            if w_in > 60:      # wall span mislabeled as door — draw as opening
                color = "#bdc3c7"
            else:
                clears = w_in >= WALKER_WIDTH_IN + 1
                color = "#1e8449" if clears else "#c0392b"
            a, b = _endpoints(s)
            d.line([P(a), P(b)], fill=color, width=8)
            if w_in <= 60:
                mid = ((P(a)[0] + P(b)[0]) / 2, (P(a)[1] + P(b)[1]) / 2 - 14)
                d.text(mid, f'{w_in}"', fill=color, anchor="mm", font=font)

    d.text((12, 8), fp.get("room", "room"), fill="#17202a", font=font)
    return img


def render_run(floorplans: list[dict]) -> bytes:
    imgs = [render_room(fp) for fp in floorplans] or [render_room({})]
    gap = 16
    w = max(i.width for i in imgs)
    h = sum(i.height for i in imgs) + gap * (len(imgs) - 1)
    canvas = Image.new("RGB", (w, h), "white")
    y = 0
    for i in imgs:
        canvas.paste(i, (0, y))
        y += i.height + gap
    buf = io.BytesIO()
    canvas.save(buf, "PNG")
    return buf.getvalue()

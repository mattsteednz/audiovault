"""
Generate AudioVault launcher icons from the VaultIcon SVG spec.

SVG source (VaultIcon.tsx viewBox 0 0 48 48):
  <rect width="48" height="48" rx="12" fill="#6B4C9A"/>
  <circle cx="24" cy="24" r="13" stroke="#ccb5ff" strokeWidth="2.5"/>
  <circle cx="24" cy="24" r="5" fill="#ccb5ff"/>
  <path d="M24 11v4M24 33v4M11 24h4M33 24h4" stroke="#ccb5ff" strokeWidth="2.5" strokeLinecap="round"/>
  <circle cx="24" cy="24" r="9" stroke="#8a5ef7" strokeWidth="1" strokeDasharray="2 3"/>
  <path d="M28 24a4 4 0 1 1-8 0 4 4 0 0 1 8 0z" fill="#6B4C9A"/>  <- punches hole in r=5 fill
  <circle cx="24" cy="24" r="2" fill="#f3eeff"/>
"""

import math
import os
from pathlib import Path
from PIL import Image, ImageDraw

# ── Colours (from VaultIcon) ─────────────────────────────────────────────────
BG        = (107, 76, 154, 255)   # #6B4C9A
LIGHT     = (204, 181, 255, 255)  # #ccb5ff
DASH_RING = (138, 94, 247, 255)   # #8a5ef7
WHITE_DOT = (243, 238, 255, 255)  # #f3eeff

# ── Draw at this size, then downsample ───────────────────────────────────────
SRC = 1024

def s(v):
    """Scale a coordinate from the 48-unit viewBox to SRC pixels."""
    return v / 48 * SRC

def draw_icon(size: int) -> Image.Image:
    img = Image.new("RGBA", (SRC, SRC), (0, 0, 0, 0))
    img_ctx = img
    d = ImageDraw.Draw(img)

    cx, cy = SRC / 2, SRC / 2

    # 1. Rounded-rect background (rx=12 → 25 % of width)
    rx = s(12)
    d.rounded_rectangle([0, 0, SRC - 1, SRC - 1], radius=rx, fill=BG)

    # 2. Outer ring  r=13, stroke=#ccb5ff, width=2.5
    def ring(r_outer_svg, r_inner_svg, colour):
        r_o = s(r_outer_svg)
        r_i = s(r_inner_svg)
        d.ellipse([cx - r_o, cy - r_o, cx + r_o, cy + r_o], fill=colour)
        d.ellipse([cx - r_i, cy - r_i, cx + r_i, cy + r_i], fill=BG)

    stroke = 2.5
    ring(13 + stroke / 2, 13 - stroke / 2, LIGHT)

    # 3. Cardinal tick marks  stroke=#ccb5ff, width=2.5, linecap=round
    hw = s(stroke / 2)   # half stroke-width in pixels
    ticks = [
        (s(24), s(11), s(24), s(15)),   # top
        (s(24), s(33), s(24), s(37)),   # bottom
        (s(11), s(24), s(15), s(24)),   # left
        (s(33), s(24), s(37), s(24)),   # right
    ]
    for x1, y1, x2, y2 in ticks:
        # Draw as a filled rounded rectangle for round linecaps
        if x1 == x2:  # vertical
            d.rounded_rectangle([x1 - hw, y1, x2 + hw, y2], radius=hw, fill=LIGHT)
        else:          # horizontal
            d.rounded_rectangle([x1, y1 - hw, x2, y2 + hw], radius=hw, fill=LIGHT)

    # 4. Dashed inner ring  r=9, stroke=#8a5ef7, width=1, dasharray="2 3"
    r_dash = s(9)
    dash_on  = s(2)   # arc length of dash
    dash_off = s(3)   # arc length of gap
    circumference = 2 * math.pi * r_dash
    step = dash_on + dash_off
    dash_width = s(1)
    angle = 0.0
    while angle < 360:
        # Convert arc-lengths to degrees
        on_deg  = math.degrees(dash_on  / r_dash)
        off_deg = math.degrees(dash_off / r_dash)
        end_angle = min(angle + on_deg, 360)
        # Draw arc segment as a thin ring slice via two ellipses
        r_o = r_dash + dash_width / 2
        r_i = r_dash - dash_width / 2
        # Use a tiny polygon approximation for each dash
        pts = []
        steps = max(4, int(on_deg / 2))
        for i in range(steps + 1):
            a = math.radians(angle + (end_angle - angle) * i / steps)
            pts.append((cx + r_o * math.cos(a), cy + r_o * math.sin(a)))
        for i in range(steps + 1):
            a = math.radians(end_angle - (end_angle - angle) * i / steps)
            pts.append((cx + r_i * math.cos(a), cy + r_i * math.sin(a)))
        if len(pts) >= 3:
            d.polygon(pts, fill=DASH_RING)
        angle += on_deg + off_deg

    # 5. Filled inner disc  r=5, fill=#ccb5ff (the "hub")
    r5 = s(5)
    d.ellipse([cx - r5, cy - r5, cx + r5, cy + r5], fill=LIGHT)

    # 6. Punch hole  r=4, fill=bg  (creates a ring from the r=5 fill)
    r4 = s(4)
    d.ellipse([cx - r4, cy - r4, cx + r4, cy + r4], fill=BG)

    # 7. Centre dot  r=2, fill=#f3eeff
    r2 = s(2)
    d.ellipse([cx - r2, cy - r2, cx + r2, cy + r2], fill=WHITE_DOT)

    # Downsample to target size with high-quality Lanczos
    result = img.resize((size, size), Image.LANCZOS)
    img.close()
    return result


def save(img: Image.Image, path: str):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, "PNG")
    print(f"  wrote {path}  ({img.size[0]}×{img.size[1]})")


def main():
    root = Path(__file__).parent.parent

    # ── Android mipmap launcher icons (legacy / pre-adaptive) ───────────────
    android_sizes = {
        "mipmap-mdpi":    48,
        "mipmap-hdpi":    72,
        "mipmap-xhdpi":   96,
        "mipmap-xxhdpi":  144,
        "mipmap-xxxhdpi": 192,
    }
    print("Android legacy icons:")
    for folder, size in android_sizes.items():
        img = draw_icon(size)
        save(img, str(root / "android/app/src/main/res" / folder / "ic_launcher.png"))
        save(img, str(root / "android/app/src/main/res" / folder / "ic_launcher_round.png"))

    # ── Android adaptive icon foreground (108 dp, content in centre 72 dp) ──
    # Foreground is 108×108 dp; icon content should live in the inner 72×72 dp.
    # We draw at 432 px (= 108 dp × 4) with the icon scaled to 288 px (72 dp × 4)
    # and centred, on a transparent background.
    print("\nAndroid adaptive icon foreground:")
    adaptive_sizes = {
        "mipmap-mdpi":    108,
        "mipmap-hdpi":    162,
        "mipmap-xhdpi":   216,
        "mipmap-xxhdpi":  324,
        "mipmap-xxxhdpi": 432,
    }
    for folder, canvas_px in adaptive_sizes.items():
        inner_px = int(canvas_px * (72 / 108))
        icon = draw_icon(inner_px)
        canvas = Image.new("RGBA", (canvas_px, canvas_px), (0, 0, 0, 0))
        try:
            offset = (canvas_px - inner_px) // 2
            canvas.paste(icon, (offset, offset))
            save(canvas, str(root / "android/app/src/main/res" / folder / "ic_launcher_foreground.png"))
        finally:
            canvas.close()

    # ── iOS AppIcon ──────────────────────────────────────────────────────────
    # iOS icons must NOT have rounded corners or transparency — the OS clips them.
    ios_sizes = [20, 29, 40, 58, 60, 76, 80, 87, 120, 152, 167, 180, 1024]
    print("\niOS icons:")
    ios_dir = root / "ios/Runner/Assets.xcassets/AppIcon.appiconset"

    def draw_icon_flat(size: int) -> Image.Image:
        """Same icon but with square corners and opaque background (iOS requirement)."""
        img = Image.new("RGBA", (SRC, SRC), BG)   # solid bg, no rounding
        d = ImageDraw.Draw(img)

        cx, cy = SRC / 2, SRC / 2
        stroke = 2.5
        def ring(r_outer_svg, r_inner_svg, colour):
            r_o, r_i = s(r_outer_svg), s(r_inner_svg)
            d.ellipse([cx-r_o, cy-r_o, cx+r_o, cy+r_o], fill=colour)
            d.ellipse([cx-r_i, cy-r_i, cx+r_i, cy+r_i], fill=BG)
        ring(13 + stroke/2, 13 - stroke/2, LIGHT)
        hw = s(stroke / 2)
        ticks = [(s(24),s(11),s(24),s(15)),(s(24),s(33),s(24),s(37)),
                 (s(11),s(24),s(15),s(24)),(s(33),s(24),s(37),s(24))]
        for x1,y1,x2,y2 in ticks:
            if x1 == x2:
                d.rounded_rectangle([x1-hw,y1,x2+hw,y2], radius=hw, fill=LIGHT)
            else:
                d.rounded_rectangle([x1,y1-hw,x2,y2+hw], radius=hw, fill=LIGHT)
        # Dashed ring
        r_dash = s(9); dash_width = s(1)
        angle = 0.0
        while angle < 360:
            on_deg  = math.degrees(s(2)  / r_dash)
            off_deg = math.degrees(s(3) / r_dash)
            end_angle = min(angle + on_deg, 360)
            r_o = r_dash + dash_width / 2; r_i = r_dash - dash_width / 2
            pts = []
            steps = max(4, int(on_deg / 2))
            for i in range(steps + 1):
                a = math.radians(angle + (end_angle - angle) * i / steps)
                pts.append((cx + r_o * math.cos(a), cy + r_o * math.sin(a)))
            for i in range(steps + 1):
                a = math.radians(end_angle - (end_angle - angle) * i / steps)
                pts.append((cx + r_i * math.cos(a), cy + r_i * math.sin(a)))
            if len(pts) >= 3: d.polygon(pts, fill=DASH_RING)
            angle += on_deg + off_deg
        r5 = s(5); d.ellipse([cx-r5,cy-r5,cx+r5,cy+r5], fill=LIGHT)
        r4 = s(4); d.ellipse([cx-r4,cy-r4,cx+r4,cy+r4], fill=BG)
        r2 = s(2); d.ellipse([cx-r2,cy-r2,cx+r2,cy+r2], fill=WHITE_DOT)
        result = img.resize((size, size), Image.LANCZOS)
        img.close()
        return result

    for size in ios_sizes:
        img = draw_icon_flat(size)
        save(img, str(ios_dir / f"Icon-{size}.png"))

    # Update Contents.json
    contents = _ios_contents_json(ios_sizes)
    (ios_dir / "Contents.json").write_text(contents)
    print(f"  wrote {ios_dir}/Contents.json")

    # ── Play Store hi-res icon ───────────────────────────────────────────────
    print("\nPlay Store icon:")
    img = draw_icon(512)
    save(img, str(root / "store/icon-512.png"))

    # ── Amazon Appstore icons ────────────────────────────────────────────────
    # 512×512  — store listing (hi-res icon)
    # 114×114  — device icon shown on Fire devices
    # Both accept transparency; draw_icon() already renders on a transparent
    # canvas with the rounded-rect background, so no extra work needed.
    print("\nAmazon Appstore icons:")
    for size in (512, 114):
        img = draw_icon(size)
        save(img, str(root / f"store/amazon/icon-{size}.png"))

    print("\nDone.")


def _ios_contents_json(sizes):
    import json
    images = []
    # Standard idiom/scale combos required by Xcode
    combos = [
        ("iphone", "2x",  40), ("iphone", "3x",  60),
        ("iphone", "2x",  58), ("iphone", "3x",  87),
        ("iphone", "2x",  80), ("iphone", "3x", 120),
        ("iphone", "2x", 120), ("iphone", "3x", 180),
        ("ipad",   "1x",  20), ("ipad",   "2x",  40),
        ("ipad",   "1x",  29), ("ipad",   "2x",  58),
        ("ipad",   "1x",  40), ("ipad",   "2x",  80),
        ("ipad",   "1x",  76), ("ipad",   "2x", 152),
        ("ipad",   "2x", 167),
        ("ios-marketing", "1x", 1024),
    ]
    seen = set()
    for idiom, scale, px in combos:
        key = (idiom, scale, px)
        if key in seen:
            continue
        seen.add(key)
        size_pt = px // int(scale[0])
        images.append({
            "filename": f"Icon-{px}.png",
            "idiom": idiom,
            "scale": scale,
            "size": f"{size_pt}x{size_pt}",
        })
    return json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2)


if __name__ == "__main__":
    main()

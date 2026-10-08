"""Freewire app icon: the white Ethernet glyph <···> on a green squircle, in every macOS size.

Run from the repository root: python3 tools/make_icon.py  (needs Pillow; dev-only).
"""

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "Freewire/Assets.xcassets/AppIcon.appiconset"
S = 1024
SS = 4  # supersampling


def master() -> Image.Image:
    big = S * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    # macOS icon grid: 824 px body centered in 1024, corner radius ~185
    inset, size, radius = 100 * SS, 824 * SS, 185 * SS
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle([inset, inset, inset + size, inset + size], radius=radius, fill=255)
    grad = Image.new("RGBA", (big, big))
    top, bottom = (52, 211, 120), (10, 130, 90)
    d = ImageDraw.Draw(grad)
    for y in range(big):
        t = y / (big - 1)
        d.line([(0, y), (big, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)) + (255,))
    img.paste(grad, (0, 0), mask)

    # <···> in white: two chevrons and three dots, with a soft shadow
    def p(x, y):
        return (x * SS, y * SS)
    w = 64 * SS
    layer = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    for outer, inner in ((250, 400), (774, 624)):
        ld.line([p(inner, 330), p(outer, 512), p(inner, 694)], fill=(255, 255, 255, 255), width=w, joint="curve")
        for x, y in ((inner, 330), (outer, 512), (inner, 694)):
            ld.ellipse([x * SS - w / 2, y * SS - w / 2, x * SS + w / 2, y * SS + w / 2], fill=(255, 255, 255, 255))
    for x in (432, 512, 592):
        r = 38 * SS
        ld.ellipse([x * SS - r, 512 * SS - r, x * SS + r, 512 * SS + r], fill=(255, 255, 255, 255))
    shadow = Image.new("RGBA", (big, big), (0, 30, 20, 0))
    shadow.putalpha(layer.getchannel("A").point(lambda a: a * 100 // 255))
    shifted = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    shifted.paste(shadow, (10 * SS, 18 * SS))
    img.alpha_composite(shifted.filter(ImageFilter.GaussianBlur(12 * SS)))
    img.alpha_composite(layer)
    return img.resize((S, S), Image.LANCZOS)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    base = master()
    images = []
    for points in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = points * scale
            name = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
            base.resize((px, px), Image.LANCZOS).save(OUT / name, optimize=True)
            images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{points}x{points}"})
    (OUT / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    (OUT.parent / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    print("icons written to", OUT)


if __name__ == "__main__":
    main()

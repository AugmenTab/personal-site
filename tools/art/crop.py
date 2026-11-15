"""Crop (and optionally zoom) a region of an image for inspection.

    python3 tools/art/crop.py SRC OUT x y w h [scale] [--grid STEP]

--grid draws a labelled coordinate grid (in source pixels) every STEP px,
which makes it practical to read off positions for masks. Development aid.
"""

import sys

from PIL import Image, ImageDraw


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    grid = None
    if "--grid" in sys.argv:
        grid = int(sys.argv[sys.argv.index("--grid") + 1])
        args = [a for a in args if a != str(grid)]
    src, out, x, y, w, h = args[0], args[1], *map(int, args[2:6])
    scale = float(args[6]) if len(args) > 6 else 1.0
    img = Image.open(src).convert("RGB").crop((x, y, x + w, y + h))
    if scale != 1.0:
        img = img.resize((round(w * scale), round(h * scale)), Image.LANCZOS)
    if grid:
        d = ImageDraw.Draw(img)
        for gx in range((x // grid + 1) * grid, x + w, grid):
            px = (gx - x) * scale
            d.line([(px, 0), (px, img.height)], fill=(0, 255, 255), width=1)
            d.text((px + 2, 2), str(gx), fill=(0, 255, 255))
        for gy in range((y // grid + 1) * grid, y + h, grid):
            py = (gy - y) * scale
            d.line([(0, py), (img.width, py)], fill=(255, 0, 255), width=1)
            d.text((2, py + 2), str(gy), fill=(255, 0, 255))
    img.save(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())

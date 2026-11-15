"""Overlay a monogram SVG on the gold adaptation for tracing feedback.

    docker compose --profile tools run --rm art \
        python3 tools/art/overlay.py SVG OUT.png

The SVG must use the coordinate space of
design/references/monogram-first-gold-adaptation.jpg scaled to 1254 px (the
original kit PNG size); the reference is resampled to that size.

Output colours: gold = both agree, magenta = reference only (vector too
thin), cyan = vector only (vector too fat). Development aid only.
"""

import sys

import numpy as np
from PIL import Image
from playwright.sync_api import sync_playwright

REF = "design/references/monogram-first-gold-adaptation.jpg"
SIZE = 1254
# Region containing the letterforms (x0, y0, x1, y1).
BOX = (200, 270, 1040, 820)


def render_svg(path: str) -> np.ndarray:
    svg = open(path, encoding="utf-8").read()
    html = (
        "<html><body style='margin:0;background:#000'>"
        f"<div style='width:{SIZE}px;height:{SIZE}px'>{svg}</div></body></html>"
    )
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(viewport={"width": SIZE, "height": SIZE})
        page.set_content(html)
        page.evaluate(
            f"() => {{ const s = document.querySelector('svg');"
            f" s.setAttribute('width', {SIZE}); s.setAttribute('height', {SIZE});"
            f" s.setAttribute('viewBox', '0 0 {SIZE} {SIZE}'); }}"
        )
        page.screenshot(path="/tmp/overlay-render.png")
        browser.close()
    img = np.asarray(Image.open("/tmp/overlay-render.png").convert("L"), dtype=np.float32)
    return img > 60


def main() -> int:
    svg_path, out = sys.argv[1], sys.argv[2]
    ref = Image.open(REF).convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
    ref_arr = np.asarray(ref, dtype=np.float32)
    ref_mask = ref_arr.mean(axis=2) > 38
    vec = render_svg(svg_path)

    base = (ref_arr * 0.35).astype(np.uint8)
    outimg = base.copy()
    both = ref_mask & vec
    ref_only = ref_mask & ~vec
    vec_only = vec & ~ref_mask
    outimg[both] = (190, 160, 100)
    outimg[ref_only] = (220, 40, 200)
    outimg[vec_only] = (40, 200, 230)
    x0, y0, x1, y1 = BOX
    crop = Image.fromarray(outimg).crop(BOX)
    crop.save(out)
    print(f"agree={both.sum()} ref_only={ref_only[y0:y1, x0:x1].sum()} vec_only={vec_only[y0:y1, x0:x1].sum()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

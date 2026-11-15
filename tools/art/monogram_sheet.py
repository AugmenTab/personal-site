"""Render the monogram comparison sheet to design/proof/monogram-comparison.png.

    docker compose --profile tools run --rm art python3 tools/art/monogram_sheet.py

Row 1: original handwritten mark, first gold adaptation, revised master
(flat), revised ornate treatment. Rows 2-3: the gold adaptation and the
revised simple mark at 256, 64, 32 and 24 px wide, rendered at 1x device
pixels (no supersampling), on the site's void background. Row 4: the same
sizes at 2x device pixels, as a high-density screen shows them.
Development aid only.
"""

import os
import sys

from PIL import Image
from playwright.sync_api import sync_playwright

from common import chown_like_work

OUT = "design/proof/monogram-comparison.png"
TMP = "/tmp/monogram-sheet"
GOLD = "design/references/monogram-first-gold-adaptation.jpg"
ORIGINAL = "design/references/monogram-original-handwritten.png"
SIZES = [256, 64, 32, 24]


def crops() -> None:
    os.makedirs(TMP, exist_ok=True)
    gold = Image.open(GOLD).convert("RGB").resize((1254, 1254), Image.LANCZOS)
    # Same box as the revised mark's viewBox (218 284 806 514).
    gold.crop((218, 284, 1024, 798)).save(f"{TMP}/gold-mark.png")
    gold.crop((90, 90, 1164, 1164)).save(f"{TMP}/gold-full.png")
    original = Image.open(ORIGINAL).convert("RGB")
    original.crop((40, 130, 610, 490)).save(f"{TMP}/original-mark.png")


def html() -> str:
    work = "file:///work"
    cell = "display:flex;flex-direction:column;align-items:center;gap:10px"
    label = "font:13px/1.3 sans-serif;color:#cfc6b0;letter-spacing:.04em;text-align:center"
    big = 330

    def figure(src: str, caption: str, w: int, h: int | None = None) -> str:
        hh = f"height:{h}px;" if h else ""
        return (
            f"<div style='{cell}'><img src='{src}' style='width:{w}px;{hh}object-fit:contain'>"
            f"<div style='{label}'>{caption}</div></div>"
        )

    row1 = "".join([
        figure(f"file://{TMP}/original-mark.png", "Original handwritten<br>(topology authority)", big, 210),
        figure(f"file://{TMP}/gold-full.png", "First gold adaptation<br>(primary visual target)", big, big),
        f"<div style='{cell}'><div style='background:#0B0B0D;padding:20px'>"
        f"<img src='{work}/design/monogram.svg' style='width:{big - 40}px'></div>"
        f"<div style='{label}'>Revised master, flat<br>design/monogram.svg</div></div>",
        figure(f"{work}/assets/brand/monogram-ornate.svg", "Revised ornate<br>assets/brand/monogram-ornate.svg", big, big),
    ])

    def size_row(src: str, caption: str) -> str:
        items = "".join(
            f"<div style='{cell}'><div style='background:#0B0B0D;padding:8px;display:flex;align-items:center;"
            f"justify-content:center;min-width:{max(s, 40)}px;min-height:40px'>"
            f"<img src='{src}' style='width:{s}px'></div>"
            f"<div style='{label}'>{s} px</div></div>"
            for s in SIZES
        )
        return (
            f"<div style='display:flex;align-items:flex-end;gap:36px'>"
            f"<div style='{label};width:150px;text-align:right'>{caption}</div>{items}</div>"
        )

    row2 = size_row(f"file://{TMP}/gold-mark.png", "First gold adaptation")
    row3 = size_row(f"{work}/assets/brand/monogram-simple.svg", "Revised simple<br>(nav variant)")
    fav = "".join(
        f"<img src='{work}/assets/brand/favicon.svg' style='width:{s}px'>" for s in (64, 32, 16)
    )
    row4 = (
        f"<div style='display:flex;align-items:flex-end;gap:36px'>"
        f"<div style='{label};width:150px;text-align:right'>Favicon<br>64 / 32 / 16 px</div>"
        f"<div style='display:flex;gap:24px;align-items:flex-end'>{fav}</div></div>"
    )
    return (
        "<!doctype html><html><body style='margin:0;background:#1a1816;padding:32px;"
        "display:flex;flex-direction:column;gap:36px;width:1500px'>"
        f"<div style='display:flex;gap:32px;align-items:flex-end'>{row1}</div>"
        f"{row2}{row3}{row4}</body></html>"
    )


def main() -> int:
    crops()
    with open(f"{TMP}/sheet.html", "w", encoding="utf-8") as fh:
        fh.write(html())
    with sync_playwright() as p:
        browser = p.chromium.launch(args=["--allow-file-access-from-files"])
        page = browser.new_page(viewport={"width": 1564, "height": 900}, device_scale_factor=1)
        page.goto(f"file://{TMP}/sheet.html", wait_until="networkidle")
        page.screenshot(path=OUT, full_page=True)
        page2 = browser.new_page(viewport={"width": 1564, "height": 900}, device_scale_factor=2)
        page2.goto(f"file://{TMP}/sheet.html", wait_until="networkidle")
        page2.screenshot(path=OUT.replace(".png", "-2x.png"), full_page=True)
        browser.close()
    chown_like_work(OUT, OUT.replace(".png", "-2x.png"))
    print(f"wrote {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

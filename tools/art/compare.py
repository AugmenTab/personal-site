"""Registered comparisons between the approved render and the live proof.

    docker compose --profile tools run --rm art python3 tools/art/compare.py

Run after the screenshots service. Reference: the full-resolution render
from the git-ignored kit, resized to 1440 wide (1586x992 -> 1440x900).
Proof: design/proof/desktop-first-view.png (Chromium, 1440x900).

Writes to design/proof/compare/:
  01-reference-1440x900.png      approved render at the authoritative size
  02-proof-1440x900.png          revised browser screenshot
  03-overlay-50.png              registered 50% opacity overlay
  04-difference.png              |reference - proof|, amplified 3x
  05-arch-left.png               left architecture: reference | proof
  06-arch-right.png              right architecture: reference | proof
  07-clouds-left.png, 07-clouds-right.png
  08-eclipse.png                 eclipse and corona: reference | proof
  09-luminance.png               grayscale reference | proof
  metrics.md                     mean absolute luminance differences per
                                 region; artwork-only regions are listed
                                 separately from regions with intentional
                                 content differences
Development aid only. Numbers support, but never replace, visual judgment.
"""

import os
import sys

import numpy as np
from PIL import Image, ImageDraw

from common import chown_like_work

RENDER = ".local/kit/01_approved_visuals/homepage-render-02.png"
PROOF = "design/proof/desktop-first-view.png"
OUT = "design/proof/compare"

# Regions (x0, y0, x1, y1) in 1440x900 page pixels.
ART_REGIONS = {  # artwork only: no text, controls or intentional differences
    "left architecture (beside text)": (0, 60, 300, 330),
    "left architecture (beside panel)": (0, 330, 140, 720),
    "right architecture (beside text)": (1150, 60, 1440, 330),
    "right architecture (beside panel)": (1300, 330, 1440, 720),
    "left cloud bank": (150, 165, 420, 290),
    "right cloud bank": (1060, 200, 1300, 300),
    "eclipse corona (above name)": (520, 50, 920, 100),
}
CONTENT_REGIONS = {  # contain intentional differences (text, CTAs, panel)
    "full frame": (0, 0, 1440, 900),
    "hero text band": (300, 100, 1140, 330),
    "CTA band + teaser": (140, 330, 1300, 900),
}
CROPS = {
    "05-arch-left": (0, 50, 330, 760),
    "06-arch-right": (1110, 50, 1440, 760),
    "07-clouds-left": (130, 150, 480, 320),
    "07-clouds-right": (1000, 180, 1330, 360),
    "08-eclipse": (480, 30, 960, 280),
}


def label(img, text):
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, 7 * len(text) + 12, 18], fill=(0, 0, 0))
    d.text((6, 3), text, fill=(235, 225, 205))
    return img


def pair(a, b, name, scale):
    a = a.resize((round(a.width * scale), round(a.height * scale)), Image.LANCZOS)
    b = b.resize((round(b.width * scale), round(b.height * scale)), Image.LANCZOS)
    out = Image.new("RGB", (a.width * 2 + 10, a.height), (60, 50, 40))
    out.paste(label(a, f"reference: {name}"), (0, 0))
    out.paste(label(b, f"proof: {name}"), (a.width + 10, 0))
    return out


def lum(img):
    return np.asarray(img.convert("RGB"), np.float32) @ np.array([0.2126, 0.7152, 0.0722], np.float32)


def mad(a, b, box):
    x0, y0, x1, y1 = box
    return float(np.abs(a[y0:y1, x0:x1] - b[y0:y1, x0:x1]).mean())


def main() -> int:
    os.makedirs(OUT, exist_ok=True)
    ref = Image.open(RENDER).convert("RGB").resize((1440, 901), Image.LANCZOS).crop((0, 0, 1440, 900))
    proof = Image.open(PROOF).convert("RGB")
    assert proof.size == (1440, 900), proof.size
    written = []

    def save(img, name):
        path = f"{OUT}/{name}"
        img.save(path, optimize=True)
        written.append(path)

    save(ref, "01-reference-1440x900.png")
    save(proof, "02-proof-1440x900.png")
    save(Image.blend(ref, proof, 0.5), "03-overlay-50.png")
    diff = np.abs(np.asarray(ref, np.float32) - np.asarray(proof, np.float32))
    save(Image.fromarray(np.clip(diff * 3, 0, 255).astype(np.uint8)), "04-difference.png")
    for name, box in CROPS.items():
        scale = 1.5 if (box[2] - box[0]) < 400 else 1.25
        save(pair(ref.crop(box), proof.crop(box), name[3:], scale), f"{name}.png")
    lr, lp = lum(ref), lum(proof)
    g = Image.new("RGB", (1440 * 2 + 10, 900), (60, 50, 40))
    g.paste(label(Image.fromarray(lr.astype(np.uint8)).convert("RGB"), "reference luminance"), (0, 0))
    g.paste(label(Image.fromarray(lp.astype(np.uint8)).convert("RGB"), "proof luminance"), (1450, 0))
    save(g, "09-luminance.png")

    lines = [
        "# Registered comparison metrics",
        "",
        "Mean absolute luminance difference (0-255) between the approved render",
        "at 1440x900 and the proof screenshot. Lower is closer. These numbers",
        "support visual judgment; they do not replace it.",
        "",
        "## Artwork-only regions",
        "",
        "| Region | Box (x0,y0,x1,y1) | MAD |",
        "| --- | --- | --- |",
    ]
    for name, box in ART_REGIONS.items():
        lines.append(f"| {name} | {box} | {mad(lr, lp, box):.1f} |")
    lines += [
        "",
        "## Regions with intentional content differences",
        "",
        "(Different nav items, the role line, added CTAs, a static teaser instead",
        "of the fake compiler. Not a fidelity score for the artwork.)",
        "",
        "| Region | Box | MAD |",
        "| --- | --- | --- |",
    ]
    for name, box in CONTENT_REGIONS.items():
        lines.append(f"| {name} | {box} | {mad(lr, lp, box):.1f} |")
    with open(f"{OUT}/metrics.md", "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    written.append(f"{OUT}/metrics.md")
    chown_like_work(OUT, *written)
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())

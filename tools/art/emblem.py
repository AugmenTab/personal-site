"""Prepare the tree-and-eclipse emblem for the About section.

    docker compose --profile tools run --rm art python3 tools/art/emblem.py

Source: the Eclipsing Eden branding board in the git-ignored kit
(.local/kit/03_eclipsing_eden_branding/source_boards/f42612e0-….png),
approved by the owner for personal identity use (Baum = tree). Only the
standalone emblem is taken: the ring, eclipse, tree, skyline, gate and base
rule. The ECLIPSING EDEN wordmark and the board's border are excluded.

Writes assets/images/about-tree.webp (alpha-feathered edge so the board's
background melts into the page). Not reproducible from the repository
alone; the output is a committed source asset.
"""

import sys

import numpy as np
from PIL import Image

from common import chown_like_work

SRC = ".local/kit/03_eclipsing_eden_branding/source_boards/f42612e0-4729-46d3-ad0c-c5eace5dba47.png"
BOX = (100, 48, 1022, 992)   # emblem only; wordmark starts below y ~1010
OUT = "assets/images/about-tree.webp"
SIZE = 680                     # output width (shown at <= 340 CSS px; 2x density)


def main() -> int:
    img = Image.open(SRC).convert("RGB").crop(BOX)
    h = round(img.height * SIZE / img.width)
    img = img.resize((SIZE, h), Image.LANCZOS)
    arr = np.asarray(img, np.float32)
    yy, xx = np.mgrid[0:h, 0:SIZE].astype(np.float32)
    # elliptical feather: fully opaque over the emblem, fading at the margins
    d = np.hypot((xx - SIZE / 2) / (SIZE / 2), (yy - h / 2) / (h / 2))
    alpha = np.clip((1.04 - d) / 0.12, 0, 1)
    # the board's near-black ground becomes transparent, so it never shows
    # as a lighter or darker rectangle on the page
    lum = arr @ np.array([0.3, 0.55, 0.15], np.float32)
    alpha *= np.clip((lum - 14) / 26, 0, 1) * 0.85 + 0.15 * np.clip((lum - 10) / 10, 0, 1)
    rgba = np.dstack([arr.astype(np.uint8), (alpha * 255 + 0.5).astype(np.uint8)])
    Image.fromarray(rgba, "RGBA").save(OUT, "WEBP", quality=78, method=6)
    chown_like_work(OUT)
    print("wrote", OUT, rgba.shape)
    return 0


if __name__ == "__main__":
    sys.exit(main())

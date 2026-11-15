"""Compare the latest desktop capture with the approved regression reference.

    docker compose up -d preview
    docker compose --profile tools run --rm screenshots
    docker compose --profile tools run --rm art python3 tools/art/regression.py
    docker compose --profile tools run --rm art python3 tools/art/regression.py --hero-band

Reference: design/regression/desktop-1440x900.png (approved at the Phase 00
gate). Candidate: design/proof/desktop-first-view.png. Writes
design/proof/regression-diff.png (|difference| x4) and exits 1 if the mean
absolute luminance difference exceeds the threshold, or if any 32x32 tile
differs by more than the tile threshold (catches local breakage that a
whole-frame mean would hide). Thresholds allow for font antialiasing noise.

--hero-band compares only the rows above the Black teaser's frame (y < 421
at 1440x900, the frame's top in both the reference and Phase 03): the
navigation, artwork, name, divider, thesis, disciplines and calls to
action. That band is the Phase 03 hard non-regression gate; the teaser's
content below it changed by design (verified program, truthful copy).
Development aid only; a failure means "look at the diff", not "broken".
"""

import sys

import numpy as np
from PIL import Image

REFERENCE = "design/regression/desktop-1440x900.png"
CANDIDATE = "design/proof/desktop-first-view.png"
DIFF = "design/proof/regression-diff.png"
HERO_BAND_ROWS = 416  # a whole number of 32px tiles above the teaser frame (y=421)
MEAN_LIMIT = 1.5      # 0-255 luminance, whole frame
TILE_LIMIT = 12.0     # 0-255 luminance, worst 32x32 tile
TILE = 32


def lum(img):
    return np.asarray(img, np.float32) @ np.array([0.2126, 0.7152, 0.0722], np.float32)


def main() -> int:
    hero_only = "--hero-band" in sys.argv[1:]
    ref_img = Image.open(REFERENCE).convert("RGB")
    cand_img = Image.open(CANDIDATE).convert("RGB")
    if ref_img.size != cand_img.size:
        print(f"size mismatch: reference {ref_img.size}, candidate {cand_img.size}")
        return 1
    if hero_only:
        box = (0, 0, ref_img.size[0], HERO_BAND_ROWS)
        ref_img, cand_img = ref_img.crop(box), cand_img.crop(box)
        print(f"region: hero band, rows 0-{HERO_BAND_ROWS - 1}")
    else:
        print("region: full first view")
    ref, cand = lum(ref_img), lum(cand_img)
    d = np.abs(ref - cand)
    h, w = d.shape
    tiles = d[: h - h % TILE, : w - w % TILE].reshape(h // TILE, TILE, w // TILE, TILE).mean(axis=(1, 3))
    worst = np.unravel_index(np.argmax(tiles), tiles.shape)
    rgb = np.abs(np.asarray(ref_img, np.float32) - np.asarray(cand_img, np.float32))
    diff = DIFF.replace(".png", "-hero-band.png") if hero_only else DIFF
    Image.fromarray(np.clip(rgb * 4, 0, 255).astype(np.uint8)).save(diff)
    print(f"mean |dL| = {d.mean():.2f} (limit {MEAN_LIMIT})")
    print(f"worst tile = {tiles.max():.2f} at x={worst[1] * TILE}, y={worst[0] * TILE} (limit {TILE_LIMIT})")
    print(f"diff image: {diff}")
    ok = d.mean() <= MEAN_LIMIT and tiles.max() <= TILE_LIMIT
    print("PASS" if ok else "FAIL: inspect the diff against the approved reference")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

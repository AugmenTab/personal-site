"""Compare the latest desktop capture with the approved regression reference.

    docker compose up -d preview
    docker compose --profile tools run --rm screenshots
    docker compose --profile tools run --rm art python3 tools/art/regression.py

Reference: design/regression/desktop-1440x900.png (approved at the Phase 00
gate). Candidate: design/proof/desktop-first-view.png. Writes
design/proof/regression-diff.png (|difference| x4) and exits 1 if the mean
absolute luminance difference exceeds the threshold, or if any 32x32 tile
differs by more than the tile threshold (catches local breakage that a
whole-frame mean would hide). Thresholds allow for font antialiasing noise.
Development aid only; a failure means "look at the diff", not "broken".
"""

import sys

import numpy as np
from PIL import Image

REFERENCE = "design/regression/desktop-1440x900.png"
CANDIDATE = "design/proof/desktop-first-view.png"
DIFF = "design/proof/regression-diff.png"
MEAN_LIMIT = 1.5      # 0-255 luminance, whole frame
TILE_LIMIT = 12.0     # 0-255 luminance, worst 32x32 tile
TILE = 32


def lum(path):
    img = Image.open(path).convert("RGB")
    return img, np.asarray(img, np.float32) @ np.array([0.2126, 0.7152, 0.0722], np.float32)


def main() -> int:
    ref_img, ref = lum(REFERENCE)
    cand_img, cand = lum(CANDIDATE)
    if ref.shape != cand.shape:
        print(f"size mismatch: reference {ref_img.size}, candidate {cand_img.size}")
        return 1
    d = np.abs(ref - cand)
    h, w = d.shape
    tiles = d[: h - h % TILE, : w - w % TILE].reshape(h // TILE, TILE, w // TILE, TILE).mean(axis=(1, 3))
    worst = np.unravel_index(np.argmax(tiles), tiles.shape)
    rgb = np.abs(np.asarray(ref_img, np.float32) - np.asarray(cand_img, np.float32))
    Image.fromarray(np.clip(rgb * 4, 0, 255).astype(np.uint8)).save(DIFF)
    print(f"mean |dL| = {d.mean():.2f} (limit {MEAN_LIMIT})")
    print(f"worst tile = {tiles.max():.2f} at x={worst[1] * TILE}, y={worst[0] * TILE} (limit {TILE_LIMIT})")
    print(f"diff image: {DIFF}")
    ok = d.mean() <= MEAN_LIMIT and tiles.max() <= TILE_LIMIT
    print("PASS" if ok else "FAIL: inspect the diff against the approved reference")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

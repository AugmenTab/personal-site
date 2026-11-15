"""Reconstruct the hero artwork from the owner's approved render.

    docker compose --profile tools run --rm art python3 tools/art/reconstruct.py

Source: the full-resolution approved render in the git-ignored reference kit
(.local/kit/01_approved_visuals/homepage-render-02.png, 1586x992). The
owner permitted use of their own reference pixels for decorative artwork
(phase-00_update2). This pipeline is NOT expected to be reproducible from the
repository alone: its outputs are committed as stable source assets, and the
site build only copies them.

Steps
  1. Remove every piece of text and UI the page draws itself in real
     HTML/CSS: nav labels and underline, the nav rule and its diamonds, the
     medallion, the name, the divider, the thesis, the disciplines, the Black
     panel and the Selected Work rule. Thin text is found by local contrast
     inside known boxes, dilated, and filled by Telea inpainting; the original
     grain is then transferred back so fills are not smeared.
  2. Synthesise the region the render's Black panel hid: each column fades
     from its last visible colour into the dark ground, with vertical
     weathering, feathered into the real architecture beside it.
  3. Cut the cleaned 1586x800 plate into three overlapping, feathered pieces
     (left, centre, right). Placed side by side they reproduce the cleaned
     render exactly; on narrow screens they slide together.

Writes assets/images/hero-plate-{left,centre,right}.webp and, for review,
design/proof/hero-cleaned.png (the full cleaned plate) and
design/proof/hero-mask.png (what was removed).
"""

import sys

import cv2
import numpy as np
from PIL import Image
from scipy import ndimage

from common import chown_like_work

SRC = ".local/kit/01_approved_visuals/homepage-render-02.png"
PLATE_H = 800
W = 1586

# Boxes (x0, y0, x1, y1) in render pixels.
TEXT_BOXES = [  # (box, |contrast| threshold, dilation radius)
    ((322, 6, 1296, 39), 22, 4),     # nav labels
    ((495, 168, 1092, 262), 18, 6),  # TYLER BAUM (letters + dark shadow)
]
SOLID_BOXES = [
    (595, 234, 995, 280),   # divider rule + glyph (over plain dark disc/sky)
    (452, 274, 1136, 326),  # thesis
    (338, 336, 1250, 367),  # disciplines
    (326, 37, 404, 47),     # HOME underline
    (40, 42, 1548, 50),     # nav rule
    (198, 36, 218, 56),     # rule diamond, left
    (1370, 36, 1390, 56),   # rule diamond, right
    (0, 764, 150, 788),     # Selected Work rule, left stub
    (1436, 764, 1586, 788), # Selected Work rule, right stub
]
MEDALLION = (793, 33, 41)   # centre x, centre y, radius
ECLIPSE = (793, 228)        # disc centre (rays radiate from here)
PANEL = (118, 372, 1468, PLATE_H)  # region the render's Black panel hid (frame at y>=391)

# Plate pieces: (name, x0, x1, fade_in, fade_out) in render pixels.
PIECES = [
    ("left", 0, 640, None, (570, 640)),
    ("centre", 470, 1116, (470, 545), (1041, 1116)),
    ("right", 946, W, (946, 1016), None),
]


def text_mask(lum, box, thresh, dilate):
    x0, y0, x1, y1 = box
    region = lum[y0:y1, x0:x1]
    bg = cv2.medianBlur(region.astype(np.uint8), 31).astype(np.float32)
    m = np.abs(region - bg) > thresh
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * dilate + 1, 2 * dilate + 1))
    m = cv2.dilate(m.astype(np.uint8), k)
    out = np.zeros(lum.shape, np.uint8)
    out[y0:y1, x0:x1] = m
    return out


def main() -> int:
    src = np.asarray(Image.open(SRC).convert("RGB"))
    assert src.shape[1] == W, src.shape
    img = src[:PLATE_H].copy()
    lum = img.astype(np.float32) @ np.array([0.3, 0.55, 0.15], np.float32)

    mask = np.zeros(lum.shape, np.uint8)
    for box, thresh, dil in TEXT_BOXES:
        mask |= text_mask(lum, box, thresh, dil)
    for x0, y0, x1, y1 in SOLID_BOXES:
        mask[y0:y1, x0:x1] = 1
    yy, xx = np.mgrid[0:PLATE_H, 0:W]
    cx, cy, r = MEDALLION
    med = (xx - cx) ** 2 + (yy - cy) ** 2 <= r * r
    px0, py0, px1, py1 = PANEL
    mask_panel = np.zeros_like(mask)
    mask_panel[py0:py1, px0:px1] = 1

    # 1a. the medallion sits on the corona, whose rays are radial from the
    # eclipse centre: fill it by interpolating around that centre, from the
    # first unmasked angle on each side at the same radius.
    f = img.astype(np.float32)
    ex, ey = ECLIPSE
    for y, x in zip(*np.nonzero(med)):
        rr = np.hypot(x - ex, y - ey)
        th = np.arctan2(x - ex, ey - y)
        samples = []
        for sgn in (-1, 1):
            a = th
            while True:
                a += sgn * 0.002
                sx, sy = ex + rr * np.sin(a), ey - rr * np.cos(a)
                ix, iy = int(round(sx)), int(round(sy))
                if not (0 <= iy < PLATE_H and 0 <= ix < W):
                    break
                if not med[iy, ix] and not mask[iy, ix]:
                    samples.append((abs(a - th), f[iy, ix]))
                    break
        if len(samples) == 2:
            (d1, c1), (d2, c2) = samples
            f[y, x] = (c1 * d2 + c2 * d1) / (d1 + d2)
        elif samples:
            f[y, x] = samples[0][1]
    img = f.astype(np.uint8)

    # 1b. inpaint the remaining text/UI (not the panel: synthesised below)
    bgr = cv2.cvtColor(img, cv2.COLOR_RGB2BGR)
    filled = cv2.inpaint(bgr, mask * 255, 6, cv2.INPAINT_TELEA)
    filled = cv2.cvtColor(filled, cv2.COLOR_BGR2RGB).astype(np.float32)

    # grain: inpainting is smooth, the render is not. Add synthetic grain
    # matched to a clean patch of sky (never copied from shifted pixels,
    # which re-introduces neighbouring text).
    clean = f[120:170, 380:460]
    hp = clean - np.stack([ndimage.gaussian_filter(clean[..., c], 1.6) for c in range(3)], -1)
    sd = hp.reshape(-1, 3).std(axis=0)
    rng0 = np.random.default_rng(11)
    noise = rng0.standard_normal((PLATE_H, W, 1)).astype(np.float32)
    noise = ndimage.gaussian_filter(noise, (0.6, 0.6, 0))
    noise /= noise.std()
    m3 = ndimage.gaussian_filter(mask.astype(np.float32), 1.0)[..., None]
    filled = filled + noise * sd[None, None, :] * m3
    detail = f - np.stack([ndimage.gaussian_filter(f[..., c], 1.6) for c in range(3)], -1)

    # 2. synthesise the panel region
    band = filled[py0 - 16:py0 - 2, :, :].mean(axis=0)      # per-column colour
    band = np.stack([ndimage.uniform_filter1d(band[:, c], 9) for c in range(3)], -1)
    t = (np.arange(py0, py1) - py0).astype(np.float32)[:, None, None]
    ground = np.array([11, 10, 12], np.float32)
    rng = np.random.default_rng(7)
    streak = ndimage.gaussian_filter(rng.standard_normal((py1 - py0, W)).astype(np.float32), (14, 1.2))
    streak = streak / (streak.std() + 1e-6)
    fade = np.exp(-t / 38.0)
    synth = ground + (band[None, :, :] - ground) * fade
    synth = synth * (1 + 0.035 * streak[..., None] * np.exp(-t / 260.0))
    # fine grain everywhere in the synthetic area, borrowed from real ground
    tile = detail[700:760, 0:120]
    reps = ((py1 - py0) // tile.shape[0] + 1, W // tile.shape[1] + 1, 1)
    synth += np.tile(tile, reps)[: py1 - py0, :W] * 0.8
    region = filled[py0:py1].copy()
    xw = np.arange(W, dtype=np.float32)
    wx = np.clip(np.minimum(xw - px0, px1 - xw) / 18.0, 0, 1)   # feather sides
    wx = np.where((xw < px0) | (xw >= px1), 0, wx)
    wy = np.clip((np.arange(py0, py1) - py0) / 16.0, 0, 1)[:, None]  # feather top
    wgt = (wx[None, :] * wy)[..., None]
    filled[py0:py1] = region * (1 - wgt) + synth * wgt

    cleaned = np.clip(filled, 0, 255).astype(np.uint8)
    Image.fromarray(cleaned).save("design/proof/hero-cleaned.png", optimize=True)
    vis = (src[:PLATE_H].astype(np.float32) * 0.35).astype(np.uint8)
    vis[mask.astype(bool)] = (230, 40, 200)
    vis[mask_panel.astype(bool) & ~mask.astype(bool)] = (40, 160, 230)
    Image.fromarray(vis).save("design/proof/hero-mask.png", optimize=True)

    # 3. cut the pieces
    written = ["design/proof/hero-cleaned.png", "design/proof/hero-mask.png"]
    ys = np.arange(PLATE_H, dtype=np.float32)
    bottom = np.clip((PLATE_H - 1 - ys) / 110.0, 0, 1)[:, None]
    for name, x0, x1, fin, fout in PIECES:
        piece = cleaned[:, x0:x1]
        xs = np.arange(x0, x1, dtype=np.float32)
        a = np.ones_like(xs)
        if fin:
            a = np.minimum(a, np.clip((xs - fin[0]) / (fin[1] - fin[0]), 0, 1))
        if fout:
            a = np.minimum(a, np.clip((fout[1] - xs) / (fout[1] - fout[0]), 0, 1))
        alpha = (a[None, :] * bottom * 255 + 0.5).astype(np.uint8)
        rgba = np.dstack([piece, alpha])
        path = f"assets/images/hero-plate-{name}.webp"
        Image.fromarray(rgba, "RGBA").save(path, "WEBP", quality=90, method=6)
        written.append(path)
    chown_like_work(*written)
    for p in written:
        print("wrote", p)
    return 0


if __name__ == "__main__":
    sys.exit(main())

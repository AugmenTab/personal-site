"""Print the reference monogram's filled runs along columns or rows.

    python3 tools/art/profile.py col 260 1020 20     # x from 260 to 1020
    python3 tools/art/profile.py row 300 800 20      # y from 300 to 800

Coordinates are in the 1254 px gold-adaptation space. Development aid only.
"""

import sys

import numpy as np
from PIL import Image
from scipy import ndimage

REF = "design/references/monogram-first-gold-adaptation.jpg"
SIZE = 1254
BOX = (200, 270, 1040, 820)


def runs(line: np.ndarray, offset: int) -> list[tuple[int, int]]:
    out, start = [], None
    for i, v in enumerate(line):
        if v and start is None:
            start = i
        if not v and start is not None:
            out.append((start + offset, i - 1 + offset))
            start = None
    if start is not None:
        out.append((start + offset, len(line) - 1 + offset))
    return [r for r in out if r[1] - r[0] >= 4]


def main() -> int:
    axis, lo, hi, step = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
    ref = Image.open(REF).convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
    mask = np.asarray(ref, dtype=np.float32).mean(axis=2) > 38
    mask = ndimage.binary_opening(mask, iterations=1)
    x0, y0, x1, y1 = BOX
    for v in range(lo, hi + 1, step):
        if axis == "col":
            print(f"x={v}: {runs(mask[y0:y1, v], y0)}")
        else:
            print(f"y={v}: {runs(mask[v, x0:x1], x0)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

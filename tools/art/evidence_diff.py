"""Compare curated evidence in design/proof/ with a fresh capture run.

    docker compose --profile tools run --rm art python3 tools/art/evidence_diff.py

For every committed screenshot that the capture suite also writes (same
relative path under design/proof/latest/), report whether the pixels are
identical. Exit 1 if any differ. Use it after a change that should not alter
the site's appearance, and before deliberately refreshing curated evidence.
Files the suite does not produce (references, sheets, frozen historical
captures) are listed as "not regenerated" and skipped.
"""

import os
import sys

from PIL import Image, ImageChops

PROOF = "design/proof"
LATEST = f"{PROOF}/latest"


def main():
    same, differ, skipped = [], [], []
    for root, dirs, files in os.walk(PROOF):
        if root.startswith(LATEST):
            continue
        for name in sorted(files):
            if not name.endswith(".png") or name.endswith(".scratch.png"):
                continue
            path = os.path.join(root, name)
            rel = os.path.relpath(path, PROOF)
            fresh = os.path.join(LATEST, rel)
            if not os.path.exists(fresh):
                skipped.append(rel)
                continue
            a = Image.open(path).convert("RGB")
            b = Image.open(fresh).convert("RGB")
            if a.size != b.size:
                differ.append(f"{rel}: size {a.size} -> {b.size}")
            elif ImageChops.difference(a, b).getbbox() is None:
                same.append(rel)
            else:
                box = ImageChops.difference(a, b).getbbox()
                differ.append(f"{rel}: pixels differ in {box}")
    for rel in same:
        print(f"identical        {rel}")
    for line in differ:
        print(f"DIFFERS          {line}")
    for rel in skipped:
        print(f"not regenerated  {rel}")
    print(f"\n{len(same)} identical, {len(differ)} differ, {len(skipped)} not regenerated")
    return 1 if differ else 0


if __name__ == "__main__":
    sys.exit(main())

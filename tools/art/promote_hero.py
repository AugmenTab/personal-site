"""Promote an approved project hero from the design staging area into content.

    docker compose --profile tools run --rm art \
        python3 tools/art/promote_hero.py SLUG [--src PATH] [--out PATH] [--width N]

Reads .local/heroes/{SLUG}-hero.png (the owner's externally prepared art;
.local/ is never committed), and writes content/projects/{SLUG}/hero.webp:

  - the composition is kept whole: no crop, no repainting, no generated
    content (the banner crops with CSS object-fit, steered by "focus");
  - it is scaled down (never up) to at most --width pixels wide (2400);
  - colour is kept as sRGB, metadata is dropped;
  - WebP quality starts at 86 and steps down until the file fits the
    build's hero limit (1 MiB, Site.Content.Load.heroByteLimit) with margin.

The site build never runs this; its output is a committed source asset.
After promoting, add "hero" to the project's project.json (README "Hero
artwork") and review the result at every viewport.
"""

import argparse
import io
import os
import sys

from PIL import Image

from common import chown_like_work

LIMIT = 1024 * 1024          # Site.Content.Load.heroByteLimit
TARGET = int(LIMIT * 0.85)   # leave room under the limit
QUALITIES = [86, 82, 78, 74, 70, 66, 62]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("slug")
    parser.add_argument("--src")
    parser.add_argument("--out")
    parser.add_argument("--width", type=int, default=2400)
    args = parser.parse_args()

    src = args.src or f".local/heroes/{args.slug}-hero.png"
    out = args.out or f"content/projects/{args.slug}/hero.webp"
    if not os.path.isfile(src):
        print(f"no staged hero at {src}", file=sys.stderr)
        return 1
    if not os.path.isdir(os.path.dirname(out) or "."):
        print(f"no project directory for {out}", file=sys.stderr)
        return 1

    img = Image.open(src)
    img.load()
    original = img.size
    img = img.convert("RGB")
    if img.width > args.width:
        height = round(img.height * args.width / img.width)
        img = img.resize((args.width, height), Image.LANCZOS)

    data = None
    for quality in QUALITIES:
        buf = io.BytesIO()
        img.save(buf, "WEBP", quality=quality, method=6)
        data = buf.getvalue()
        if len(data) <= TARGET:
            break
    if data is None or len(data) > LIMIT:
        print(f"cannot fit {src} under {LIMIT} bytes; try a smaller --width", file=sys.stderr)
        return 1

    with open(out, "wb") as f:
        f.write(data)
    chown_like_work(out)
    print(f"{src} {original[0]}x{original[1]} -> {out} {img.width}x{img.height}, "
          f"quality {quality}, {len(data)} bytes (limit {LIMIT})")
    return 0


if __name__ == "__main__":
    sys.exit(main())

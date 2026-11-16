"""Promote an approved project hero from the design staging area into content.

    docker compose --profile tools run --rm art \
        python3 tools/art/promote_hero.py SLUG [--src PATH] [--out PATH] [--width N]

Reads .local/heroes/{SLUG}-hero.png (the owner's externally prepared art;
.local/ is never committed), and writes content/projects/{SLUG}/hero.webp:

  - the composition is kept whole: no crop, no repainting, no generated
    content (the hero crops with CSS object-fit, steered by "focus");
  - it is scaled down (never up) to at most --width pixels wide (2400),
    and never further just to meet the size budget;
  - colour is kept as sRGB, metadata is dropped;
  - WebP quality starts at 90 and steps down, no lower than 80, until the
    file fits the 1 MiB budget. Painterly art that still does not fit is
    kept at quality 80 rather than degraded further: the build accepts it
    with a warning up to the 8 MiB ceiling (Site.Content.Load,
    defaultHeroSizePolicy), and this tool refuses only what exceeds that.

Always promote from the lossless source PNG. Re-encoding an already
compressed hero (WebP or JPEG) compounds its artefacts, so lossy sources are
refused unless --allow-lossy-source is given.

The site build never runs this; its output is a committed source asset.
After promoting, add "hero" to the project's project.json (README "Hero
artwork") and review the result at every viewport (tools/art/hero_preview.py
previews it first without touching content/).
"""

import argparse
import io
import os
import sys

from PIL import Image

from common import chown_like_work

BUDGET = 1024 * 1024           # Site.Content.Load.defaultHeroSizePolicy: budget
CEILING = 8 * 1024 * 1024      # ... and ceiling
TARGET = int(BUDGET * 0.95)    # a little room under the budget
QUALITIES = [90, 88, 86, 84, 82, 80]   # 80 is the floor: no lower for size alone
LOSSY = {".webp", ".jpg", ".jpeg"}


def encode(img: Image.Image, width: int):
    """Encode as WebP: the highest quality in QUALITIES that fits the budget,
    or the floor quality if none does. Returns (bytes, quality, (w, h))."""
    img = img.convert("RGB")
    if img.width > width:
        height = round(img.height * width / img.width)
        img = img.resize((width, height), Image.LANCZOS)
    data, quality = b"", QUALITIES[-1]
    for quality in QUALITIES:
        buf = io.BytesIO()
        img.save(buf, "WEBP", quality=quality, method=6)
        data = buf.getvalue()
        if len(data) <= TARGET:
            break
    return data, quality, img.size


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("slug")
    parser.add_argument("--src")
    parser.add_argument("--out")
    parser.add_argument("--width", type=int, default=2400)
    parser.add_argument("--allow-lossy-source", action="store_true")
    args = parser.parse_args()

    src = args.src or f".local/heroes/{args.slug}-hero.png"
    out = args.out or f"content/projects/{args.slug}/hero.webp"
    if not os.path.isfile(src):
        print(f"no staged hero at {src}", file=sys.stderr)
        return 1
    if os.path.splitext(src)[1].lower() in LOSSY and not args.allow_lossy_source:
        print(f"{src} is already lossy; promote from the original PNG (or pass --allow-lossy-source)", file=sys.stderr)
        return 1
    if not os.path.isdir(os.path.dirname(out) or "."):
        print(f"no project directory for {out}", file=sys.stderr)
        return 1

    img = Image.open(src)
    img.load()
    original = img.size
    data, quality, size = encode(img, args.width)
    if len(data) > CEILING:
        print(f"{src} is {len(data)} bytes even at quality {quality}, over the {CEILING}-byte ceiling; "
              "try a smaller --width", file=sys.stderr)
        return 1

    with open(out, "wb") as f:
        f.write(data)
    chown_like_work(out)
    print(f"{src} {original[0]}x{original[1]} -> {out} {size[0]}x{size[1]}, "
          f"quality {quality}, {len(data)} bytes (budget {BUDGET}, ceiling {CEILING})")
    if len(data) > BUDGET:
        print(f"note: over the {BUDGET}-byte budget at the quality floor; the build will accept it "
              "with a warning. Review the art at every viewport before committing.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

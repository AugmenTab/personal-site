"""Preview a project hero without publishing it (development only).

    docker compose --profile tools run --rm art \
        python3 tools/art/hero_preview.py SLUG (--image PNG | --stand-in) \
            [--alt TEXT] [--focus X,Y] [--mobile-focus X,Y] \
            [--title TEXT] [--summary TEXT] [--grain] [--format webp|png]

Builds a throwaway source tree in .local/hero-preview/ (git-ignored): a copy
of content/ and assets/ in which SLUG's project.json gains a "hero". The
repository's content/ is never touched, so nothing previewed here can be
committed or published by accident. Then:

    docker compose run --rm site-build stack exec -- \
        site build --root .local/hero-preview --out .local/hero-preview/html
    docker compose --profile tools up -d hero-preview      # http://localhost:8081/
    docker compose --profile tools run --rm art python3 tools/screenshots/hero_check.py SLUG

Image sources:

  --image PNG   staged artwork (e.g. .local/heroes/black-hero.png), encoded
                exactly as tools/art/promote_hero.py would encode it;
  --stand-in    a generated layout test card: a focal target toward the
                upper right, distinct left and right halves, a 10% grid, and
                top and bottom reference bands. It is labelled as a
                development stand-in across the image and is never a
                candidate for production art.

--focus and --mobile-focus write the hero's "focus" (README "Hero
artwork"); omit both to preview the default (centre). --title and --summary
override the project's text, to test long titles and summaries.

--grain adds film grain, making the file large, to test the size policy:
as WebP it lands just over the 1 MiB budget and as PNG at about 6.4 MiB
(the build accepts both with a warning); with --format png --canvas
3200,1600 it exceeds the 8 MiB ceiling, so the build fails.
"""

import argparse
import json
import os
import shutil
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from common import chown_like_work
from promote_hero import encode

ROOT = ".local/hero-preview"
WIDTH, HEIGHT = 2400, 1200
FOCAL = (0.78, 0.35)   # the stand-in's target, as fractions of width and height


def font(size):
    try:
        return ImageFont.load_default(size=size)
    except TypeError:          # older Pillow: fixed-size bitmap font
        return ImageFont.load_default()


def stand_in(grain: bool) -> Image.Image:
    """A test card that makes the crop obvious at every viewport."""
    img = Image.new("RGB", (WIDTH, HEIGHT))
    px = np.zeros((HEIGHT, WIDTH, 3), dtype=np.float32)
    # left half cold slate, right half warm umber, blended across the middle
    t = np.clip((np.arange(WIDTH) / WIDTH - 0.4) / 0.2, 0, 1)[None, :, None]
    left, right = np.array([28, 36, 48]), np.array([70, 44, 22])
    px[:] = left * (1 - t) + right * t
    if grain:
        rng = np.random.default_rng(4)
        px += rng.normal(0, 38, px.shape)
    img = Image.fromarray(np.clip(px, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(img)

    # 10% grid with labels
    for i in range(1, 10):
        x, y = WIDTH * i // 10, HEIGHT * i // 10
        d.line([(x, 0), (x, HEIGHT)], fill=(110, 110, 110), width=2)
        d.line([(0, y), (WIDTH, y)], fill=(110, 110, 110), width=2)
        d.text((x + 8, HEIGHT // 2 + 8), f"{i * 10}", fill=(170, 170, 170), font=font(30))
        d.text((8, y + 6), f"{i * 10}", fill=(170, 170, 170), font=font(30))

    # top and bottom reference bands
    d.rectangle([(0, 0), (WIDTH, 60)], fill=(30, 110, 90))
    d.text((WIDTH // 2 - 60, 10), "TOP", fill=(240, 240, 240), font=font(40))
    d.rectangle([(0, HEIGHT - 60), (WIDTH, HEIGHT)], fill=(130, 40, 40))
    d.text((WIDTH // 2 - 110, HEIGHT - 52), "BOTTOM", fill=(240, 240, 240), font=font(40))

    # region labels
    d.text((90, HEIGHT // 2 - 160), "LEFT", fill=(150, 170, 200), font=font(120))
    d.text((WIDTH // 2 + 120, HEIGHT - 300), "RIGHT", fill=(220, 170, 110), font=font(120))

    # the focal target
    cx, cy = int(WIDTH * FOCAL[0]), int(HEIGHT * FOCAL[1])
    for r, colour in [(230, (212, 175, 90)), (160, (40, 30, 20)), (95, (212, 175, 90)), (30, (250, 240, 220))]:
        d.ellipse([(cx - r, cy - r), (cx + r, cy + r)], fill=colour)
    d.text((cx - 120, cy + 250), "FOCUS 78,35", fill=(250, 230, 190), font=font(44))

    # the stand-in label, repeated so every crop shows it
    label = "DEVELOPMENT STAND-IN - NOT PRODUCTION ART"
    for y in (140, HEIGHT - 170):
        d.text((90, y), label, fill=(240, 90, 90), font=font(44))
    return img


def point(text):
    try:
        x, y = (int(v) for v in text.split(","))
    except ValueError:
        raise argparse.ArgumentTypeError(f"expected X,Y (e.g. 65,35), got {text!r}")
    return {"x": x, "y": y}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("slug")
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--image")
    source.add_argument("--stand-in", action="store_true")
    parser.add_argument("--alt")
    parser.add_argument("--focus", type=point)
    parser.add_argument("--mobile-focus", type=point)
    parser.add_argument("--title")
    parser.add_argument("--summary")
    parser.add_argument("--grain", action="store_true")
    parser.add_argument("--format", choices=["webp", "png"], default="webp")
    parser.add_argument("--canvas", type=point, help="stand-in size as W,H (default 2400,1200)")
    args = parser.parse_args()
    if args.canvas:
        global WIDTH, HEIGHT
        WIDTH, HEIGHT = args.canvas["x"], args.canvas["y"]

    project_dir = f"content/projects/{args.slug}"
    if not os.path.isfile(f"{project_dir}/project.json"):
        print(f"no project {args.slug!r} in content/projects/", file=sys.stderr)
        return 1

    # A fresh copy of the sources. The built site (html/) is kept so a
    # running hero-preview server keeps serving the same directory.
    os.makedirs(ROOT, exist_ok=True)
    for name in ("content", "assets"):
        shutil.rmtree(f"{ROOT}/{name}", ignore_errors=True)
        shutil.copytree(name, f"{ROOT}/{name}", symlinks=False)

    if args.stand_in:
        img = stand_in(args.grain)
        what = "stand-in test card"
    else:
        if not os.path.isfile(args.image):
            print(f"no image at {args.image}", file=sys.stderr)
            return 1
        img = Image.open(args.image)
        img.load()
        what = args.image

    filename = f"hero.{args.format}"
    out = f"{ROOT}/{project_dir}/{filename}"
    if args.format == "png":
        img.convert("RGB").save(out, "PNG", optimize=False, compress_level=1)
        size = os.path.getsize(out)
    else:
        data, _quality, _size = encode(img, 2400)
        with open(out, "wb") as f:
            f.write(data)
        size = len(data)

    meta_path = f"{ROOT}/{project_dir}/project.json"
    with open(meta_path) as f:
        meta = json.load(f)
    hero = {"src": filename}
    if args.alt:
        hero["alt"] = args.alt
    else:
        hero["decorative"] = True
    focus = {}
    if args.focus:
        focus["desktop"] = args.focus
    if args.mobile_focus:
        focus["mobile"] = args.mobile_focus
    if focus:
        hero["focus"] = focus
    meta["hero"] = hero
    if args.title:
        meta["title"] = args.title
    if args.summary:
        meta["summary"] = args.summary
    with open(meta_path, "w") as f:
        json.dump(meta, f, indent=2, ensure_ascii=False)
        f.write("\n")

    for dirpath, dirnames, filenames in os.walk(ROOT):
        chown_like_work(dirpath, *(os.path.join(dirpath, n) for n in filenames))
    print(f"{what} -> {out} ({size} bytes); hero = {json.dumps(hero)}")
    print(f"preview tree: {ROOT}/ (content/ and assets/ copies; the repository is unchanged)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

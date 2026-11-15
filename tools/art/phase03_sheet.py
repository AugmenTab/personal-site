"""Phase 03 comparison sheets (development aid; outputs are evidence only).

    docker compose --profile tools run --rm art python3 tools/art/phase03_sheet.py

Reads the approved Phase 00 baseline, the pre-Phase 03 captures saved in
design/proof/phase-03/before/, and the latest captures, and writes:

- design/proof/phase-03/compare-hero.png: approved hero | current hero |
  |difference| x4, for the hero band (rows above the Black teaser frame);
- design/proof/phase-03/compare-home-desktop.png: the whole homepage at
  1440 wide, before and after Phase 03, side by side.
"""

from PIL import Image, ImageDraw, ImageChops

OUT = "design/proof/phase-03"
HERO_ROWS = 416
GAP = 24
INK = (194, 164, 106)
GROUND = (11, 11, 13)


def labelled(images, labels, gap=GAP):
    width = sum(i.width for i in images) + gap * (len(images) + 1)
    height = max(i.height for i in images) + 56
    sheet = Image.new("RGB", (width, height), GROUND)
    draw = ImageDraw.Draw(sheet)
    x = gap
    for img, label in zip(images, labels):
        draw.text((x, 18), label, fill=INK)
        sheet.paste(img, (x, 48))
        x += img.width + gap
    return sheet


def main():
    approved = Image.open("design/regression/desktop-1440x900.png").convert("RGB")
    current = Image.open("design/proof/desktop-first-view.png").convert("RGB")
    box = (0, 0, approved.width, HERO_ROWS)
    a, c = approved.crop(box), current.crop(box)
    diff = ImageChops.difference(a, c).point(lambda v: min(255, v * 4))
    half = lambda i: i.resize((i.width // 2, i.height // 2), Image.LANCZOS)
    sheet = labelled([half(a), half(c), half(diff)],
                     ["Phase 00 approved hero", "Phase 03 hero", "|difference| x4 (black = identical)"])
    sheet.save(f"{OUT}/compare-hero.png")

    before = Image.open(f"{OUT}/before/home-desktop-full.png").convert("RGB")
    after = Image.open(f"{OUT}/home-desktop-full.png").convert("RGB")
    scale = lambda i: i.resize((i.width * 2 // 5, i.height * 2 // 5), Image.LANCZOS)
    labelled([scale(before), scale(after)], ["Before Phase 03 (baseline af78a2e)", "Phase 03"]).save(
        f"{OUT}/compare-home-desktop.png")
    print("wrote compare-hero.png, compare-home-desktop.png")


if __name__ == "__main__":
    main()

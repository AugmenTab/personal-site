"""Phase 04 layout remediation comparison sheets (evidence only).

    docker compose --profile tools run --rm art python3 tools/art/remediation_sheet.py

Writes to design/proof/phase-04-remediation/:

- compare-desktop.png: the Phase 04 full-width hero (stand-in art) | the
  corrected sidebar-aligned hero (stand-in art) | the approved project
  render (structural reference only; its compiler panel is not built);
- compare-mobile.png: the same two implementations at 390 wide.

Both implementations show development stand-in art, never project art.
"""

from PIL import Image, ImageDraw, ImageFont

OUT = "design/proof/phase-04-remediation"
GAP = 32
INK = (194, 164, 106)
GROUND = (11, 11, 13)


def font(size):
    try:
        return ImageFont.load_default(size=size)
    except TypeError:
        return ImageFont.load_default()


def fit(path, height):
    img = Image.open(path).convert("RGB")
    return img.resize((round(img.width * height / img.height), height), Image.LANCZOS)


def sheet(panels, out, height):
    images = [fit(p, height) for p, _ in panels]
    width = sum(i.width for i in images) + GAP * (len(images) + 1)
    canvas = Image.new("RGB", (width, height + 80), GROUND)
    draw = ImageDraw.Draw(canvas)
    x = GAP
    for img, (_, label) in zip(images, panels):
        draw.text((x, 24), label, fill=INK, font=font(26))
        canvas.paste(img, (x, 72))
        x += img.width + GAP
    canvas.save(out, optimize=True)
    print(f"{out} {canvas.width}x{canvas.height}")


def main():
    sheet([
        ("design/proof/phase-04/stand-in-hero/black-desktop-first-view.png", "BEFORE: Phase 04 full-width hero, sidebar below"),
        ("design/proof/phase-04-remediation/right-focus/black-desktop-first-view.png", "AFTER: hero in the main column, sidebar beside it"),
        ("design/references/project-render-03.jpg", "APPROVED RENDER (structure only)"),
    ], f"{OUT}/compare-desktop.png", 900)
    sheet([
        ("design/proof/phase-04/stand-in-hero/black-mobile-first-view.png", "BEFORE (390 wide)"),
        ("design/proof/phase-04-remediation/right-focus/black-mobile-first-view.png", "AFTER (390 wide)"),
    ], f"{OUT}/compare-mobile.png", 844)


if __name__ == "__main__":
    main()

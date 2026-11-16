"""Quick development capture of one page (not part of the proof run).

    docker compose up -d preview
    docker compose --profile tools run --rm art \
        python3 tools/screenshots/peek.py /work/black/ 1440 900 [full] [selector]

Writes design/proof/peek-{width}.scratch.png (ignored by Git). With a CSS
selector, captures that element instead of the viewport. Prints any
horizontal overflow and console errors.
"""

import sys

from playwright.sync_api import sync_playwright

BASE = "http://preview"


def main() -> int:
    path, width, height = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    rest = sys.argv[4:]
    full = "full" in rest
    selector = next((a for a in rest if a != "full"), None)
    out = f"design/proof/peek-{width}.scratch.png"
    errors = []
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(viewport={"width": width, "height": height})
        page.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
        # a full URL (e.g. http://hero-preview/work/black/) overrides BASE
        page.goto(path if path.startswith("http") else BASE + path, wait_until="networkidle")
        page.evaluate("""async () => {
          document.documentElement.style.scrollBehavior = 'auto';
          for (const img of document.images) { img.loading = 'eager'; }
          await Promise.all([...document.images].map(i => i.complete ? null : new Promise(r => { i.onload = i.onerror = r; })));
          await document.fonts.ready;
        }""")
        if selector:
            page.locator(selector).first.screenshot(path=out)
        else:
            page.screenshot(path=out, full_page=full)
        overflow = page.evaluate("() => document.documentElement.scrollWidth - document.documentElement.clientWidth")
        print(f"{out} overflow={overflow} errors={errors}")
        browser.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())

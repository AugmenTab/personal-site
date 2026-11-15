"""Capture Phase 00 proof screenshots and run basic browser checks.

Development tool only; runs in the pinned Playwright container against the
static preview service:

    docker compose up -d preview
    docker compose --profile tools run --rm screenshots

Writes PNGs and checks.txt to design/proof/.
"""

import json
import os
import sys

from playwright.sync_api import sync_playwright

BASE = os.environ.get("PREVIEW_URL", "http://localhost:8080/")
OUT = "design/proof"

VIEWPORTS = {
    "desktop": {"width": 1440, "height": 900},
    "tablet": {"width": 768, "height": 1024},
    "mobile": {"width": 390, "height": 844},
}

CHECKS_JS = """
() => {
  const doc = document.documentElement;
  const headings = [...document.querySelectorAll('h1,h2,h3,h4,h5,h6')]
    .map(h => `${h.tagName.toLowerCase()}: ${h.textContent.trim().replace(/\\s+/g, ' ')}`);
  const imgs = [...document.images].map(i => ({
    src: i.getAttribute('src'), alt: i.getAttribute('alt'),
    loaded: i.complete && i.naturalWidth > 0,
  }));
  const anchors = [...document.querySelectorAll('a[href^="#"]')]
    .map(a => a.getAttribute('href'))
    .filter(h => h.length > 1 && !document.getElementById(h.slice(1)));
  const fonts = [...document.fonts].filter(f => f.status === 'loaded')
    .map(f => `${f.family} ${f.weight} ${f.style}`);
  return {
    scrollWidth: doc.scrollWidth, clientWidth: doc.clientWidth,
    horizontalOverflow: doc.scrollWidth > doc.clientWidth,
    headings, images: imgs, brokenFragmentLinks: anchors, fontsLoaded: fonts,
  };
}
"""


LOAD_ALL_JS = """
async () => {
  // Load lazy images now so full-page captures include them (capture only;
  // the page itself keeps loading="lazy").
  document.querySelectorAll('img[loading="lazy"]').forEach(i => { i.loading = 'eager'; });
  window.scrollTo(0, document.body.scrollHeight);
  await new Promise(r => setTimeout(r, 50));
  await Promise.all([...document.images].map(i => i.complete ? null :
    new Promise(r => { i.addEventListener('load', r); i.addEventListener('error', r); })));
  window.scrollTo(0, 0);
  await document.fonts.ready;
  await Promise.all([...document.fonts].filter(f => f.status !== 'unloaded').map(f => f.loaded));
}
"""


def ready(page):
    page.goto(BASE, wait_until="networkidle")
    page.evaluate("document.fonts.ready")
    page.evaluate(LOAD_ALL_JS)


def main() -> int:
    report = {}
    failures = []
    with sync_playwright() as p:
        browser = p.chromium.launch()

        for name, viewport in VIEWPORTS.items():
            page = browser.new_page(viewport=viewport, device_scale_factor=1)
            bad = []
            page.on("response", lambda r, bad=bad: bad.append(f"{r.status} {r.url}") if r.status >= 400 else None)
            page.on("console", lambda m, bad=bad: bad.append(f"console.{m.type}: {m.text}") if m.type in ("error", "warning") else None)
            ready(page)
            page.evaluate("document.fonts.ready")
            page.screenshot(path=f"{OUT}/{name}.png", full_page=True)
            page.screenshot(path=f"{OUT}/{name}-first-view.png", full_page=False)
            checks = page.evaluate(CHECKS_JS)
            checks["httpErrorsAndConsole"] = bad
            report[name] = checks
            if checks["horizontalOverflow"]:
                failures.append(f"{name}: horizontal overflow ({checks['scrollWidth']} > {checks['clientWidth']})")
            if checks["brokenFragmentLinks"]:
                failures.append(f"{name}: broken fragment links {checks['brokenFragmentLinks']}")
            if any(not i["loaded"] for i in checks["images"]):
                failures.append(f"{name}: image(s) failed to load")
            if bad:
                failures.append(f"{name}: http/console problems {bad}")
            page.close()

        # Branding close-ups at desktop: the About composition (tree emblem)
        # and the nav medallion + divider beneath the name.
        page = browser.new_page(viewport=VIEWPORTS["desktop"])
        ready(page)
        page.evaluate("document.fonts.ready")
        page.screenshot(path=f"{OUT}/branding-nav-divider.png",
                        clip={"x": 360, "y": 0, "width": 720, "height": 300})
        page.locator("#about").screenshot(path=f"{OUT}/about-section.png")
        report["monogramImages"] = page.evaluate(
            "() => [...document.images].filter(i => /monogram/.test(i.src)).map(i => i.closest('nav') ? 'nav' : 'elsewhere')")
        if report["monogramImages"] != ["nav"]:
            failures.append(f"monogram must appear once, in the nav: {report['monogramImages']}")
        page.close()
        page = browser.new_page(viewport=VIEWPORTS["mobile"])
        ready(page)
        page.evaluate("document.fonts.ready")
        page.locator("#about").screenshot(path=f"{OUT}/about-section-mobile.png")
        page.close()

        # Keyboard: tab from the top of the page and record the focus order.
        page = browser.new_page(viewport=VIEWPORTS["desktop"])
        page.goto(BASE, wait_until="networkidle")
        page.evaluate("document.fonts.ready")
        order = []
        for _ in range(12):
            page.keyboard.press("Tab")
            order.append(page.evaluate(
                "() => { const e = document.activeElement;"
                " return `${e.tagName.toLowerCase()} \"${(e.innerText || e.getAttribute('aria-label') || '').trim().replace(/\\s+/g,' ')}\" -> ${e.getAttribute('href')}`; }"))
        report["keyboardFocusOrder"] = order
        # Focus the primary call to action for the focus-state capture.
        page.goto(BASE, wait_until="networkidle")
        page.evaluate("document.fonts.ready")
        # skip link, Home, Work, monogram, About, Contact, primary CTA
        for _ in range(7):
            page.keyboard.press("Tab")
        page.screenshot(path=f"{OUT}/keyboard-focus.png", full_page=False)
        # Then (past the secondary CTA) the project card link.
        page.keyboard.press("Tab")
        page.keyboard.press("Tab")
        page.evaluate("document.activeElement.closest('article').scrollIntoView({block: 'center', behavior: 'instant'})")
        page.screenshot(path=f"{OUT}/keyboard-focus-card.png", full_page=False)
        page.close()

        # Reduced motion: confirm animations are disabled.
        context = browser.new_context(viewport=VIEWPORTS["desktop"], reduced_motion="reduce")
        page = context.new_page()
        page.goto(BASE, wait_until="networkidle")
        page.evaluate("document.fonts.ready")
        report["reducedMotion"] = page.evaluate(
            "() => ({ runningAnimations: document.getAnimations().length,"
            " scrollBehavior: getComputedStyle(document.documentElement).scrollBehavior })")
        if report["reducedMotion"]["runningAnimations"] != 0:
            failures.append("reduced motion: animations still running")
        if report["reducedMotion"]["scrollBehavior"] != "auto":
            failures.append("reduced motion: smooth scrolling still enabled")
        page.screenshot(path=f"{OUT}/reduced-motion.png", full_page=False)
        context.close()

        # No JavaScript: the page must be fully usable (it ships none, but check).
        context = browser.new_context(viewport=VIEWPORTS["desktop"], java_script_enabled=False)
        page = context.new_page()
        page.goto(BASE, wait_until="networkidle")
        page.screenshot(path=f"{OUT}/no-javascript.png", full_page=False)
        context.close()

        browser.close()

    report["failures"] = failures
    with open(f"{OUT}/checks.txt", "w") as fh:
        fh.write(json.dumps(report, indent=2))
        fh.write("\n")
    # The container runs as root; hand the evidence to whoever owns the
    # bind-mounted proof directory (matters on Linux hosts only).
    st = os.stat(OUT)
    for name in os.listdir(OUT):
        try:
            os.chown(os.path.join(OUT, name), st.st_uid, st.st_gid)
        except PermissionError:
            pass
    print(json.dumps(report, indent=2))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

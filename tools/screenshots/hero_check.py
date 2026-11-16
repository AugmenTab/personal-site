"""Browser checks and captures for a previewed hero (development only).

    docker compose --profile tools up -d hero-preview
    docker compose --profile tools run --rm art \
        python3 tools/screenshots/hero_check.py SLUG [NAME]

Runs the dossier checks of phase04.py (layout, hero, sections, keyboard)
against the hero preview server (README "Previewing a hero"), plus a
no-JavaScript walk of the sidebar links at every viewport. Captures go to
design/proof/phase-04-remediation/NAME/ (default "stand-in"), with the
results in checks.json. Exits 1 if any check fails.

The preview is built from .local/hero-preview/, never from content/, so
these captures show art that is not published.
"""

import json
import os
import sys
from urllib.parse import urljoin

from playwright.sync_api import sync_playwright

from capture import LOAD_ALL_JS, VIEWPORTS
from phase04 import phase04_captures

BASE = "http://hero-preview/"

NO_JS_CLICK_JS = """
(id) => { const t = document.getElementById(id); if (!t) return null;
  const r = t.getBoundingClientRect();
  return { hash: location.hash, inView: r.top >= 0 && r.top < innerHeight }; }
"""


def main() -> int:
    slug = sys.argv[1]
    name = sys.argv[2] if len(sys.argv) > 2 else "stand-in"
    out = f"design/proof/phase-04-remediation/{name}"
    path = f"/work/{slug}/"
    failures, errors = [], []

    with sync_playwright() as p:
        browser = p.chromium.launch()

        def ready(page, page_path="/"):
            page.on("console", lambda m: errors.append(f"console {m.type}: {m.text}") if m.type in ("error", "warning") else None)
            page.on("pageerror", lambda e: errors.append(f"page error: {e}"))
            page.on("response", lambda r: errors.append(f"HTTP {r.status} {r.url}") if r.status >= 400 else None)
            page.goto(urljoin(BASE, page_path), wait_until="networkidle")
            page.evaluate(LOAD_ALL_JS)

        report = phase04_captures(browser, BASE, {f"project-{slug}": path}, VIEWPORTS, ready, failures, out=out,
                                  layout_shots=False)   # the sections' own captures are phase-04/'s

        # The sidebar works without JavaScript at every width.
        no_js = {}
        for vp_name, viewport in VIEWPORTS.items():
            context = browser.new_context(viewport=viewport, java_script_enabled=False)
            page = context.new_page()
            page.goto(urljoin(BASE, path), wait_until="networkidle")
            page.evaluate("() => { document.documentElement.style.scrollBehavior = 'auto'; }")
            links = page.eval_on_selector_all(".project-nav__sections a", "els => els.map(a => a.getAttribute('href'))")
            results = {}
            for href in links:
                page.click(f".project-nav__sections a[href='{href}']")
                page.wait_for_timeout(100)
                state = page.evaluate(NO_JS_CLICK_JS, href[1:])
                results[href] = state
                if state is None or state["hash"] != href or not state["inView"]:
                    failures.append(f"{slug}/{vp_name}: no-JS sidebar link {href}: {state}")
            if not links:
                failures.append(f"{slug}/{vp_name}: no sidebar section links")
            no_js[vp_name] = results
            context.close()
        browser.close()

    failures.extend(errors)
    os.makedirs(out, exist_ok=True)
    with open(f"{out}/checks.json", "w") as f:
        json.dump({"base": BASE, "path": path, "failures": failures, "noJavaScript": no_js, "report": report}, f, indent=2)
        f.write("\n")
    print(f"{out}/checks.json: {len(failures)} failure(s)")
    for failure in failures:
        print(f"  - {failure}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

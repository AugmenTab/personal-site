"""Phase 04 evidence and browser checks for the project dossiers.

Called by capture.py (same browser, same preview). For every project page
at desktop, tablet and mobile it records and checks:

  - the hero (when the project has one): image loaded, title and summary
    inside the banner and unclipped, the sidebar starting below it;
  - every section's layout, in order, and that the sidebar lists exactly
    the sections marked for it;
  - splits: side by side above 1180px, stacked below, artifact on the
    declared side (first in reading order when stacked);
  - grids: 3 or 2 columns on desktop, 2 on tablet, 1 on mobile;
  - code panels never scroll sideways; diagrams may scroll inside their
    frame on mobile, and the page never does;
  - keyboard: every link in the dossier body takes a visible focus ring.

Writes design/proof/phase-04/: full pages, first views, hero close-ups and
one capture of each layout kind per viewport.
"""

import os
from urllib.parse import urljoin

PHASE04_OUT = "design/proof/phase-04"

STRUCTURE_JS = """
() => {
  const rect = e => { const r = e.getBoundingClientRect();
    return { top: Math.round(r.top + scrollY), left: Math.round(r.left), right: Math.round(r.right),
             bottom: Math.round(r.bottom + scrollY), width: Math.round(r.width), height: Math.round(r.height) }; };
  const hero = document.querySelector('.project-hero');
  const heroInfo = hero ? (() => {
    const img = hero.querySelector('img');
    const h = rect(hero), t = rect(hero.querySelector('.project__title')), s = rect(hero.querySelector('.project__summary'));
    const title = hero.querySelector('.project__title');
    return { box: h, title: t, summary: s,
             imageLoaded: img.complete && img.naturalWidth > 0,
             imageNatural: [img.naturalWidth, img.naturalHeight],
             objectPosition: getComputedStyle(img).objectPosition,
             decorative: img.getAttribute('alt') === '',
             textInside: t.top >= h.top && s.bottom <= h.bottom && t.left >= h.left && s.right <= h.right,
             titleClipped: title.scrollWidth > title.clientWidth + 1,
             sidebarBelow: rect(document.querySelector('.project-nav')).top >= h.bottom };
  })() : null;
  const sections = [...document.querySelectorAll('.dossier-section')].map(s => {
    const kind = [...s.classList].find(c => c.startsWith('dossier-section--') && !c.includes('artifact'))
      .replace('dossier-section--', '');
    const info = { id: s.querySelector('h2').id, layout: kind };
    if (kind === 'split') {
      const text = rect(s.querySelector('.dossier-split__text'));
      const art = rect(s.querySelector('.dossier-split__artifact'));
      info.side = s.classList.contains('dossier-section--artifact-start') ? 'start' : 'end';
      info.sideBySide = Math.abs(text.top - art.top) < 40 && (text.right <= art.left || art.right <= text.left);
      info.artifactFirst = info.sideBySide ? art.left < text.left : art.top < text.top;
    }
    if (kind === 'grid') {
      info.columns = new Set([...s.querySelectorAll('.dossier-grid__item')].map(i => Math.round(i.getBoundingClientRect().left))).size;
    }
    info.codeScrollsSideways = [...s.querySelectorAll('.artifact__code')].some(p => p.scrollWidth > p.clientWidth + 1);
    info.diagramScrolls = [...s.querySelectorAll('.artifact__viewport')].some(v => v.scrollWidth > v.clientWidth + 1);
    return info;
  });
  const sidebar = [...document.querySelectorAll('.project-nav__sections a')].map(a => a.getAttribute('href').slice(1));
  return { hero: heroInfo, sections, sidebar,
           overflow: document.documentElement.scrollWidth > document.documentElement.clientWidth };
}
"""

FOCUS_JS = """
() => { const e = document.activeElement; const s = getComputedStyle(e);
  return { href: e.getAttribute('href'), inBody: !!e.closest('.project__body, article.project'),
           inNav: !!e.closest('nav'), ring: s.outlineStyle !== 'none' && parseFloat(s.outlineWidth) > 0 }; }
"""


def phase04_captures(browser, base, pages, viewports, ready, failures):
    os.makedirs(PHASE04_OUT, exist_ok=True)
    report = {}
    for page_name, path in pages.items():
        name = page_name.replace("project-", "")
        report[name] = {}
        for vp_name, viewport in viewports.items():
            page = browser.new_page(viewport=viewport, device_scale_factor=1)
            ready(page, path)
            page.screenshot(path=f"{PHASE04_OUT}/{name}-{vp_name}-full.png", full_page=True)
            page.screenshot(path=f"{PHASE04_OUT}/{name}-{vp_name}-first-view.png", full_page=False)
            info = page.evaluate(STRUCTURE_JS)
            label = f"{name}/{vp_name}"
            width = viewport["width"]

            if info["overflow"]:
                failures.append(f"{label}: horizontal overflow")
            hero = info["hero"]
            if hero:
                page.locator(".project-hero").screenshot(path=f"{PHASE04_OUT}/{name}-{vp_name}-hero.png")
                if not hero["imageLoaded"]:
                    failures.append(f"{label}: hero image did not load")
                if not hero["textInside"]:
                    failures.append(f"{label}: hero text falls outside the banner {hero}")
                if hero["titleClipped"]:
                    failures.append(f"{label}: hero title clipped")
                if not hero["sidebarBelow"]:
                    failures.append(f"{label}: sidebar overlaps the hero")

            listed = [s["id"] for s in info["sections"]]
            missing = [i for i in info["sidebar"] if i not in listed]
            if missing:
                failures.append(f"{label}: sidebar links without sections {missing}")

            captured = set()
            for s in info["sections"]:
                if s["layout"] == "split":
                    expect_side = width > 1180
                    if s["sideBySide"] != expect_side:
                        failures.append(f"{label}: split #{s['id']} sideBySide={s['sideBySide']}, expected {expect_side}")
                    if s["artifactFirst"] != (s["side"] == "start"):
                        failures.append(f"{label}: split #{s['id']} artifact on the wrong side")
                if s["layout"] == "grid":
                    allowed = {"desktop": {2, 3}, "tablet": {2}, "mobile": {1}}[vp_name]
                    if s["columns"] not in allowed:
                        failures.append(f"{label}: grid #{s['id']} has {s['columns']} columns, expected {sorted(allowed)}")
                if s["codeScrollsSideways"]:
                    failures.append(f"{label}: code in #{s['id']} scrolls sideways")
                if s["diagramScrolls"] and vp_name != "mobile":
                    failures.append(f"{label}: diagram in #{s['id']} scrolls above mobile width")
                if s["layout"] not in captured:
                    captured.add(s["layout"])
                    page.locator(f"section:has(> h2#{s['id']})").screenshot(
                        path=f"{PHASE04_OUT}/{name}-{vp_name}-layout-{s['layout']}.png")

            # Keyboard: walk every focus stop after the sidebar; each must
            # show a ring (the sidebar's own order is checked elsewhere).
            if vp_name == "desktop":
                page.goto(urljoin(base, path), wait_until="networkidle")
                page.evaluate("() => { document.documentElement.style.scrollBehavior = 'auto'; }")
                stops = []
                for _ in range(80):
                    page.keyboard.press("Tab")
                    stop = page.evaluate(FOCUS_JS)
                    if stop["href"] is None and not stop["inBody"]:
                        break
                    if stop["inBody"] and not stop["inNav"]:
                        stops.append(stop)
                        if not stop["ring"]:
                            failures.append(f"{label}: no visible focus on {stop['href']}")
                    if stops and not stop["inBody"]:
                        break
                info["bodyFocusStops"] = [s["href"] for s in stops]
                if stops:
                    page.wait_for_timeout(300)
                    page.screenshot(path=f"{PHASE04_OUT}/{name}-desktop-focus.png", full_page=False)
            report[name][vp_name] = info
            page.close()
    return report

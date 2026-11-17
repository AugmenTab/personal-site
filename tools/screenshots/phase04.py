"""Phase 04 evidence and browser checks for the project dossiers.

Called by capture.py (same browser, same preview). For every project page
at desktop, tablet and mobile it records and checks:

  - the layout (Phase 04 remediation): on desktop the sidebar starts
    beside the opening (hero or header), in its own column; below 900px
    the opening, the sidebar and the dossier stack in that order;
  - the hero (when the project has one): inside the article, in the same
    column as the dossier (edge to edge on phones), image loaded, title and
    summary inside it and unclipped, the crop at the configured focus point
    for the viewport, and the first section starting within the first
    desktop screen;
  - every section's layout, in order, and that the sidebar lists exactly
    the sections marked for it;
  - splits: side by side above 1180px, stacked below, artifact on the
    declared side (first in reading order when stacked);
  - grids: 3 or 2 columns on desktop, 2 on tablet, 1 on mobile;
  - code panels never scroll sideways; diagrams may scroll inside their
    frame on mobile, and the page never does;
  - keyboard: every link in the dossier body takes a visible focus ring.

Writes design/proof/latest/phase-04/: full pages, first views, hero close-ups and
one capture of each layout kind per viewport.
"""

import os
from urllib.parse import urljoin

PHASE04_OUT = "design/proof/latest/phase-04"

STRUCTURE_JS = """
() => {
  const rect = e => { const r = e.getBoundingClientRect();
    return { top: Math.round(r.top + scrollY), left: Math.round(r.left), right: Math.round(r.right),
             bottom: Math.round(r.bottom + scrollY), width: Math.round(r.width), height: Math.round(r.height) }; };
  const article = document.querySelector('article.project');
  const hero = document.querySelector('.project-hero');
  const opening = hero || document.querySelector('article.project > .project__header');
  const navEl = document.querySelector('.project-nav');
  const bodyEl = document.querySelector('.project__body');
  const o = rect(opening), n = rect(navEl), b = rect(bodyEl);
  const firstSection = document.querySelector('.dossier-section h2');
  const layout = {
    opening: o, nav: n, body: b,
    allInArticle: [opening, navEl, bodyEl].every(e => e.parentElement === article),
    sourceOrder: [...article.children].map(e => e.classList[0]),
    navBeside: n.right <= o.left && n.right <= b.left && Math.abs(n.top - o.top) <= 40,
    navSticky: getComputedStyle(navEl).position === 'sticky',
    stacked: o.bottom <= n.top + 1 && n.bottom <= b.top + 1,
    firstSectionTop: firstSection ? rect(firstSection).top : null,
    viewport: [innerWidth, innerHeight],
  };
  const heroInfo = hero ? (() => {
    const img = hero.querySelector('img');
    const h = rect(hero), t = rect(hero.querySelector('.project__title')), s = rect(hero.querySelector('.project__summary'));
    const title = hero.querySelector('.project__title');
    const focus = {};
    for (const c of hero.classList) {
      const m = c.match(/^project-hero--(x|y|mx|my)-(\\d+)$/);
      if (m) focus[m[1]] = +m[2];
    }
    return { box: h, title: t, summary: s, focus,
             imageLoaded: img.complete && img.naturalWidth > 0,
             imageNatural: [img.naturalWidth, img.naturalHeight],
             objectPosition: getComputedStyle(img).objectPosition,
             decorative: img.getAttribute('alt') === '',
             focusable: hero.tabIndex >= 0 || img.tabIndex >= 0,
             textInside: t.top >= h.top && s.bottom <= h.bottom && t.left >= h.left && s.right <= h.right,
             titleClipped: title.scrollWidth > title.clientWidth + 1 || t.right > h.right + 1,
             sameColumnAsBody: Math.abs(h.left - b.left) <= 1 && Math.abs(h.right - b.right) <= 1,
             edgeToEdge: h.left <= 0 && h.right >= document.documentElement.clientWidth };
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
  return { layout, hero: heroInfo, sections, sidebar,
           overflow: document.documentElement.scrollWidth > document.documentElement.clientWidth };
}
"""

FOCUS_JS = """
() => { const e = document.activeElement; const s = getComputedStyle(e);
  return { href: e.getAttribute('href'), inBody: !!e.closest('.project__body, article.project'),
           inNav: !!e.closest('nav'), ring: s.outlineStyle !== 'none' && parseFloat(s.outlineWidth) > 0 }; }
"""


def check_layout(label, width, info, failures):
    """The shared dossier layout, with or without a hero."""
    lay = info["layout"]
    if not lay["allInArticle"]:
        failures.append(f"{label}: opening, sidebar and body are not all children of the article {lay['sourceOrder']}")
    if width > 900:
        if not lay["navBeside"]:
            failures.append(f"{label}: sidebar does not start beside the opening {lay}")
        if not lay["navSticky"]:
            failures.append(f"{label}: sidebar is not sticky on desktop")
    elif not lay["stacked"]:
        failures.append(f"{label}: below 900px expected opening, sidebar, body stacked {lay}")


def check_hero(label, width, info, failures):
    hero, lay = info["hero"], info["layout"]
    if not hero["imageLoaded"]:
        failures.append(f"{label}: hero image did not load")
    if not hero["textInside"]:
        failures.append(f"{label}: hero text falls outside the hero {hero}")
    if hero["titleClipped"]:
        failures.append(f"{label}: hero title clipped")
    if hero["focusable"]:
        failures.append(f"{label}: the hero is focusable")
    if width > 640 and not hero["sameColumnAsBody"]:
        failures.append(f"{label}: hero is not in the dossier's column {hero['box']} vs {lay['body']}")
    if width <= 640 and not hero["edgeToEdge"]:
        failures.append(f"{label}: phone hero should run edge to edge {hero['box']}")
    f = hero["focus"]
    expected = f"{f['mx']}% {f['my']}%" if width <= 640 else f"{f['x']}% {f['y']}%"
    if hero["objectPosition"] != expected:
        failures.append(f"{label}: hero crop at {hero['objectPosition']}, expected {expected}")
    if width > 900 and (lay["firstSectionTop"] is None or lay["firstSectionTop"] >= lay["viewport"][1]):
        failures.append(f"{label}: the first section starts below the first screen ({lay['firstSectionTop']})")


def phase04_captures(browser, base, pages, viewports, ready, failures, out=PHASE04_OUT, layout_shots=True):
    os.makedirs(out, exist_ok=True)
    report = {}
    for page_name, path in pages.items():
        name = page_name.replace("project-", "")
        report[name] = {}
        for vp_name, viewport in viewports.items():
            page = browser.new_page(viewport=viewport, device_scale_factor=1)
            ready(page, path)
            page.screenshot(path=f"{out}/{name}-{vp_name}-full.png", full_page=True)
            page.screenshot(path=f"{out}/{name}-{vp_name}-first-view.png", full_page=False)
            info = page.evaluate(STRUCTURE_JS)
            label = f"{name}/{vp_name}"
            width = viewport["width"]

            if info["overflow"]:
                failures.append(f"{label}: horizontal overflow")
            check_layout(label, width, info, failures)
            if info["hero"]:
                page.locator(".project-hero").screenshot(path=f"{out}/{name}-{vp_name}-hero.png")
                check_hero(label, width, info, failures)

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
                if layout_shots and s["layout"] not in captured:
                    captured.add(s["layout"])
                    page.locator(f"section:has(> h2#{s['id']})").screenshot(
                        path=f"{out}/{name}-{vp_name}-layout-{s['layout']}.png")

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
                    page.screenshot(path=f"{out}/{name}-desktop-focus.png", full_page=False)
            report[name][vp_name] = info
            page.close()
    return report

"""Phase 05 evidence and browser checks (called by capture.py).

Same browser, same preview. Writes design/proof/phase-05/ and returns a
report; every problem is appended to `failures`.

  - every page at the extra widths (1280 laptop, 1920 wide, 320 narrow):
    no horizontal overflow, images loaded, fragments resolve, no console or
    HTTP errors;
  - Work index: two columns from 1100px, one below; visible gaps; equal
    card heights per row; search (names, descriptions, topics, technologies,
    whitespace), category chips, combined filters, the empty state and its
    reset, keyboard operation, the focus guard, cumulative layout shift;
    without JavaScript every card shows and no control does;
  - project pages below 900px: the compact "On this page" index, collapsed
    and expanded, without JavaScript; desktop sidebar unchanged;
  - Contact: /#contact from a project page and on the homepage (no reload),
    in view and not under any fixed UI;
  - footer at every width; About; discovery files;
  - the fixture site (http://fixture-preview/, from tools/art/fixture_site.py)
    for Writing and the Résumé link, which the real site does not have yet.
"""

import json
import os
from urllib.parse import urljoin, urlparse

PHASE05_OUT = "design/proof/phase-05"
FIXTURE = os.environ.get("FIXTURE_URL", "http://fixture-preview/")

VIEWPORTS = {
    "wide": {"width": 1920, "height": 1080},
    "desktop": {"width": 1440, "height": 900},
    "laptop": {"width": 1280, "height": 800},
    "tablet": {"width": 768, "height": 1024},
    "mobile": {"width": 390, "height": 844},
    "narrow": {"width": 320, "height": 640},
}
EXTRA = ("wide", "laptop", "narrow")

INSTANT = "() => { document.documentElement.style.scrollBehavior = 'auto'; }"

GRID_JS = """
() => {
  const items = [...document.querySelectorAll('#work-list .work__item')].filter(li => !li.hidden);
  const rects = items.map(li => li.getBoundingClientRect());
  const lefts = [...new Set(rects.map(r => Math.round(r.left)))].sort((a, b) => a - b);
  const tops = [...new Set(rects.map(r => Math.round(r.top + scrollY)))].sort((a, b) => a - b);
  const rows = tops.map(t => rects.filter(r => Math.round(r.top + scrollY) === t));
  const colGap = lefts.length > 1 ? Math.round(Math.min(...rows.filter(r => r.length > 1).map(r => r[1].left - r[0].right))) : null;
  const rowGap = tops.length > 1 ? Math.round(Math.min(...tops.slice(1).map((t, i) => {
      const prev = rows[i]; return t - Math.max(...prev.map(r => r.bottom + scrollY)); }))) : null;
  const equalRows = rows.every(r => r.every(x => Math.abs(x.height - r[0].height) <= 1));
  const cardWidths = rects.map(r => Math.round(r.width));
  const summaries = [...document.querySelectorAll('#work-list .project-card__summary')].map(p => Math.round(p.getBoundingClientRect().width));
  return { columns: lefts.length, colGap, rowGap, equalRows, cardWidths, summaryWidths: summaries,
           overflow: document.documentElement.scrollWidth > document.documentElement.clientWidth,
           controlsVisible: !!document.querySelector('#work-filter') && document.querySelector('#work-filter').offsetParent !== null };
}
"""

VISIBLE_JS = """
() => ({
  titles: [...document.querySelectorAll('#work-list .work__item')].filter(li => !li.hidden)
            .map(li => li.querySelector('.project-card__title').textContent),
  status: document.getElementById('work-status').textContent,
  empty: !document.getElementById('work-empty').hidden,
  pressed: [...document.querySelectorAll('.work-filter__chip')].filter(c => c.getAttribute('aria-pressed') === 'true').map(c => c.textContent),
  active: document.activeElement ? (document.activeElement.id || document.activeElement.className || document.activeElement.tagName) : null,
})
"""

FOCUS_RING_JS = """
() => { const e = document.activeElement; const s = getComputedStyle(e);
  return { text: (e.textContent || '').trim(), ring: s.outlineStyle !== 'none' && parseFloat(s.outlineWidth) > 0 }; }
"""

CLS_JS = """
() => new Promise(resolve => {
  let total = 0;
  new PerformanceObserver(list => { for (const e of list.getEntries()) if (!e.hadRecentInput) total += e.value; })
    .observe({ type: 'layout-shift', buffered: true });
  setTimeout(() => resolve(total), 1200);
})
"""


def shot(page, name, **kwargs):
    os.makedirs(os.path.dirname(f"{PHASE05_OUT}/{name}") or PHASE05_OUT, exist_ok=True)
    page.screenshot(path=f"{PHASE05_OUT}/{name}", **kwargs)


def element_shot(page, selector, name):
    os.makedirs(os.path.dirname(f"{PHASE05_OUT}/{name}") or PHASE05_OUT, exist_ok=True)
    page.locator(selector).first.screenshot(path=f"{PHASE05_OUT}/{name}")


def page_checks(browser, base, pages, ready, watch, checks_js, failures):
    """Every page at the widths capture.py does not already cover."""
    report = {}
    for page_name, path in pages.items():
        for vp_name in EXTRA:
            page = browser.new_page(viewport=VIEWPORTS[vp_name], device_scale_factor=1)
            bad = watch(page, urljoin(base, path) if page_name == "404-deep" else None)
            ready(page, path)
            checks = page.evaluate(checks_js)
            label = f"{page_name}/{vp_name}"
            if checks["horizontalOverflow"]:
                failures.append(f"{label}: horizontal overflow ({checks['scrollWidth']} > {checks['clientWidth']})")
            if any(not i["loaded"] for i in checks["images"]):
                failures.append(f"{label}: image(s) failed to load")
            if checks["brokenFragmentLinks"]:
                failures.append(f"{label}: broken fragment links {checks['brokenFragmentLinks']}")
            if bad:
                failures.append(f"{label}: http/console problems {bad}")
            # Only the narrow width is new evidence (work/ covers the Work
            # index at every width; the other widths are checked, not kept).
            if vp_name == "narrow" and page_name in ("home", "work", "about", "project-black"):
                shot(page, f"pages/{page_name}-{vp_name}.png", full_page=True)
            report[label] = {"overflow": checks["horizontalOverflow"], "problems": bad}
            page.close()
    return report


def work_index_checks(browser, base, ready, failures):
    report = {"grid": {}}
    for vp_name, viewport in VIEWPORTS.items():
        page = browser.new_page(viewport=viewport, device_scale_factor=1)
        ready(page, "/work/")
        info = page.evaluate(GRID_JS)
        expected = 2 if viewport["width"] >= 1100 else 1
        label = f"work/{vp_name}"
        if info["columns"] != expected:
            failures.append(f"{label}: {info['columns']} columns, expected {expected}")
        if info["colGap"] is not None and info["colGap"] < 24:
            failures.append(f"{label}: column gap {info['colGap']}px")
        if info["rowGap"] is not None and info["rowGap"] < 24:
            failures.append(f"{label}: row gap {info['rowGap']}px")
        if not info["equalRows"]:
            failures.append(f"{label}: cards in a row differ in height")
        if info["overflow"]:
            failures.append(f"{label}: horizontal overflow")
        if not info["controlsVisible"]:
            failures.append(f"{label}: search controls not shown with JavaScript")
        shot(page, f"work/work-{vp_name}-full.png", full_page=True)
        report["grid"][vp_name] = info
        page.close()

    # Search and filters (JavaScript on, desktop).
    page = browser.new_page(viewport=VIEWPORTS["desktop"], device_scale_factor=1)
    ready(page, "/work/")
    page.evaluate(INSTANT)
    steps = {}

    def expect(label, titles, status=None, empty=False):
        state = page.evaluate(VISIBLE_JS)
        steps[label] = state
        if state["titles"] != titles:
            failures.append(f"work search {label}: showed {state['titles']}, expected {titles}")
        if status is not None and state["status"] != status:
            failures.append(f"work search {label}: status {state['status']!r}, expected {status!r}")
        if state["empty"] != empty:
            failures.append(f"work search {label}: empty message shown={state['empty']}, expected {empty}")
        return state

    expect("initial", ["Black", "Brigid", "Lockdown"], "3 projects")
    page.fill("#work-search", "haskell")
    expect("technology 'haskell'", ["Black", "Brigid"], "2 of 3 projects")
    page.locator("#work-search").scroll_into_view_if_needed()
    page.evaluate("() => window.scrollTo(0, document.getElementById('work-filter').getBoundingClientRect().top + scrollY - 40)")
    shot(page, "work/work-search-haskell.png", full_page=False)
    page.fill("#work-search", "  TYPE   systems  ")
    expect("topic with case and whitespace", ["Black", "Brigid"], "2 of 3 projects")
    page.fill("#work-search", "replayable")
    expect("description word", ["Lockdown"], "1 of 3 projects")
    page.fill("#work-search", "brigid")
    expect("name", ["Brigid"], "1 of 3 projects")
    page.fill("#work-search", "")
    page.click(".work-filter__chip[data-category='simulation-games']")
    state = expect("category chip", ["Lockdown"], "1 of 3 projects")
    if state["pressed"] != ["Simulation & Games"]:
        failures.append(f"work: pressed chips {state['pressed']}")
    shot(page, "work/work-filter-category.png", full_page=False)
    page.click(".work-filter__chip[data-category='libraries-tooling']")
    page.fill("#work-search", "haskell")
    expect("category + search", ["Brigid"], "1 of 3 projects")
    page.fill("#work-search", "rust")
    expect("no results", [], "0 of 3 projects", empty=True)
    shot(page, "work/work-no-results.png", full_page=False)
    page.click(".work-filter__reset")
    state = expect("reset", ["Black", "Brigid", "Lockdown"], "3 projects")
    if state["pressed"] != ["All"] or state["active"] != "work-search" or page.input_value("#work-search") != "":
        failures.append(f"work reset: {state}")
    page.click(".work-filter__chip[data-category='programming-languages']")
    page.click(".work-filter__chip[data-category='']")
    expect("back to All", ["Black", "Brigid", "Lockdown"], "3 projects")

    # Keyboard: Tab from the search field to the chips; Space selects.
    page.focus("#work-search")
    page.keyboard.press("Tab")
    page.keyboard.press("Tab")
    ring = page.evaluate(FOCUS_RING_JS)
    page.keyboard.press("Space")
    state = expect("keyboard chip", ["Black"], "1 of 3 projects")
    if ring["text"] != "Programming Languages" or not ring["ring"]:
        failures.append(f"work keyboard: focus on {ring}")
    page.wait_for_timeout(250)
    shot(page, "work/work-keyboard-chip.png", full_page=False)
    steps["keyboardFocus"] = ring
    page.keyboard.press("Shift+Tab")
    page.keyboard.press("Enter")   # All
    expect("keyboard All", ["Black", "Brigid", "Lockdown"], "3 projects")

    # Focus guard: a focused card that the filter hides hands focus back.
    page.focus(".project-card__link[href='/work/lockdown/']")
    page.evaluate("() => { const i = document.getElementById('work-search'); i.value = 'brigid'; i.dispatchEvent(new Event('input')); }")
    state = expect("focus guard", ["Brigid"], "1 of 3 projects")
    if state["active"] != "work-search":
        failures.append(f"work: focus left in a hidden card ({state['active']})")
    page.close()
    report["search"] = steps

    # Layout shift while the page loads and the script starts.
    page = browser.new_page(viewport=VIEWPORTS["desktop"])
    page.goto(urljoin(base, "/work/"), wait_until="networkidle")
    cls = page.evaluate(CLS_JS)
    report["cumulativeLayoutShift"] = cls
    if cls > 0.01:
        failures.append(f"work: cumulative layout shift {cls:.3f}")
    page.close()

    # No JavaScript: every card, no controls.
    context = browser.new_context(viewport=VIEWPORTS["desktop"], java_script_enabled=False)
    page = context.new_page()
    page.goto(urljoin(base, "/work/"), wait_until="networkidle")
    nojs = page.evaluate("""() => ({
        cards: [...document.querySelectorAll('#work-list .work__item')].filter(li => li.offsetParent !== null).length,
        controls: document.getElementById('work-filter').offsetParent !== null,
        empty: document.getElementById('work-empty').offsetParent !== null,
        links: [...document.querySelectorAll('.project-card__link')].map(a => a.getAttribute('href')) })""")
    report["noJavaScript"] = nojs
    if nojs["cards"] != 3 or nojs["controls"] or nojs["empty"]:
        failures.append(f"work without JavaScript: {nojs}")
    for href in nojs["links"]:
        if page.request.get(urljoin(base, href)).status != 200:
            failures.append(f"work without JavaScript: {href} does not resolve")
    shot(page, "work/work-no-javascript.png", full_page=True)
    context.close()
    return report


def project_nav_checks(browser, base, failures):
    report = {}
    for slug in ("black", "brigid", "lockdown"):
        path = f"/work/{slug}/"
        for vp_name in ("desktop", "tablet", "mobile", "narrow"):
            viewport = VIEWPORTS[vp_name]
            compact = viewport["width"] <= 900
            context = browser.new_context(viewport=viewport, java_script_enabled=False, device_scale_factor=1)
            page = context.new_page()
            page.goto(urljoin(base, path), wait_until="networkidle")
            info = page.evaluate("""() => {
              const vis = s => { const e = document.querySelector(s); return !!e && e.offsetParent !== null; };
              const d = document.querySelector('.project-nav__index');
              const n = document.querySelector('.project-nav').getBoundingClientRect();
              return { details: vis('.project-nav__index'), sections: vis('.project-nav__sections'),
                       tab: vis('.project-nav__current'), back: vis('.project-nav__back'),
                       open: d ? d.open : null, navHeight: Math.round(n.height),
                       position: getComputedStyle(document.querySelector('.project-nav')).position,
                       overflow: document.documentElement.scrollWidth > document.documentElement.clientWidth }; }""")
            label = f"{slug}/{vp_name}"
            if compact:
                if not (info["details"] and info["back"]) or info["sections"] or info["tab"]:
                    failures.append(f"{label}: compact index expected {info}")
                if info["open"]:
                    failures.append(f"{label}: index should start collapsed")
                if info["navHeight"] > 110:
                    failures.append(f"{label}: collapsed index is {info['navHeight']}px tall")
                if slug == "black" or vp_name == "mobile":
                    page.evaluate(INSTANT)
                    page.locator(".project-nav").scroll_into_view_if_needed()
                    element_shot(page, ".project-nav", f"project/{slug}-{vp_name}-nav-collapsed.png")
                    before = page.evaluate("() => scrollY")
                    page.click(".project-nav__summary")
                    after = page.evaluate("() => scrollY")
                    opened = page.evaluate("() => document.querySelector('.project-nav__index').open")
                    links = page.evaluate("() => [...document.querySelectorAll('.project-nav__index-list a')].map(a => { const r = a.getBoundingClientRect(); return { href: a.getAttribute('href'), visible: r.height > 0, right: Math.round(r.right) }; })")
                    if not opened or abs(after - before) > 2:
                        failures.append(f"{label}: opening the index (open={opened}, scroll {before}->{after})")
                    if any(not l["visible"] or l["right"] > viewport["width"] for l in links):
                        failures.append(f"{label}: index links not visible or overflowing {links}")
                    element_shot(page, ".project-nav", f"project/{slug}-{vp_name}-nav-expanded.png")
                    info["expanded"] = links
                if slug == "black" and vp_name == "mobile":
                    page.evaluate("() => { document.querySelector('.project-nav__index').open = false; window.scrollTo(0, 0); }")
                    shot(page, "project/black-mobile-first-view.png", full_page=False)
            else:
                if info["details"] or not info["sections"] or not info["tab"] or info["position"] != "sticky":
                    failures.append(f"{label}: desktop sidebar expected {info}")
                if slug in ("black", "brigid", "lockdown"):
                    shot(page, f"project/{slug}-desktop-first-view.png", full_page=False)
            if info["overflow"]:
                failures.append(f"{label}: horizontal overflow")
            report[label] = info
            context.close()
    return report


def contact_checks(browser, base, failures):
    report = {}
    # From a project page: the global Contact link lands on the homepage section.
    page = browser.new_page(viewport=VIEWPORTS["desktop"], device_scale_factor=1)
    page.goto(urljoin(base, "/work/lockdown/"), wait_until="networkidle")
    page.click(".site-nav a[href='/#contact']")
    page.wait_for_load_state("networkidle")
    page.wait_for_timeout(900)   # smooth scrolling settles
    state = page.evaluate("""() => { const r = document.getElementById('contact').getBoundingClientRect();
        const fixed = [...document.querySelectorAll('body *')].filter(e => ['fixed', 'sticky'].includes(getComputedStyle(e).position) && e.getBoundingClientRect().height > 0)
          .map(e => e.className);
        return { path: location.pathname, hash: location.hash, top: Math.round(r.top), inView: r.top >= 0 && r.top < innerHeight, fixedUi: fixed }; }""")
    report["fromProject"] = state
    if state["path"] != "/" or state["hash"] != "#contact" or not state["inView"] or state["fixedUi"]:
        failures.append(f"contact from a project page: {state}")
    shot(page, "contact/contact-from-project-desktop.png", full_page=False)
    # On the homepage: the same link scrolls without a reload.
    page.evaluate("() => { window.__phase05 = 'kept'; window.scrollTo(0, 0); }")
    page.click(".site-nav a[href='/#contact']")
    page.wait_for_timeout(900)
    same = page.evaluate("() => ({ kept: window.__phase05 === 'kept', hash: location.hash, inView: document.getElementById('contact').getBoundingClientRect().top < innerHeight })")
    report["onHomepage"] = same
    if not (same["kept"] and same["hash"] == "#contact" and same["inView"]):
        failures.append(f"contact on the homepage reloaded or missed: {same}")
    page.close()

    for vp_name in ("desktop", "mobile", "narrow"):
        page = browser.new_page(viewport=VIEWPORTS[vp_name], device_scale_factor=1)
        page.goto(urljoin(base, "/"), wait_until="networkidle")
        page.evaluate(INSTANT)
        controls = page.evaluate("() => [...document.querySelectorAll('#contact a')].map(a => a.getAttribute('href'))")
        report[f"controls/{vp_name}"] = controls
        if controls != ["https://github.com/AugmenTab"]:
            failures.append(f"contact/{vp_name}: controls {controls}")
        page.locator("#contact").scroll_into_view_if_needed()
        element_shot(page, "#contact", f"contact/home-contact-{vp_name}.png")
        page.close()
    return report


def footer_checks(browser, base, failures):
    report = {}
    for path, name in (("/about/", "about"), ("/", "home"), ("/work/brigid/", "brigid")):
        for vp_name in ("desktop", "tablet", "mobile", "narrow"):
            page = browser.new_page(viewport=VIEWPORTS[vp_name], device_scale_factor=1)
            page.goto(urljoin(base, path), wait_until="networkidle")
            page.evaluate(INSTANT)
            info = page.evaluate("""() => { const f = document.querySelector('.site-footer');
                const r = f.getBoundingClientRect();
                return { links: [...f.querySelectorAll('a')].map(a => a.getAttribute('href')),
                         images: f.querySelectorAll('img').length, overflow: f.scrollWidth > f.clientWidth + 1,
                         width: Math.round(r.width), minFont: Math.min(...[...f.querySelectorAll('p, a')].map(e => parseFloat(getComputedStyle(e).fontSize))) }; }""")
            label = f"footer/{name}/{vp_name}"
            if info["images"] or info["overflow"]:
                failures.append(f"{label}: {info}")
            if info["minFont"] < 11:
                failures.append(f"{label}: text smaller than 11px ({info['minFont']})")
            for href in info["links"]:
                if href.startswith("/") and page.request.get(urljoin(base, href)).status != 200:
                    failures.append(f"{label}: {href} does not resolve")
            if name == "about" or (name == "home" and vp_name in ("desktop", "mobile")):
                page.locator(".site-footer").scroll_into_view_if_needed()
                element_shot(page, ".site-footer", f"footer/footer-{name}-{vp_name}.png")
            report[label] = info
            page.close()
    return report


def about_and_home_captures(browser, base, ready, failures):
    report = {}
    for vp_name in ("desktop", "mobile"):
        page = browser.new_page(viewport=VIEWPORTS[vp_name], device_scale_factor=1)
        ready(page, "/about/")
        shot(page, f"about/about-{vp_name}-full.png", full_page=True)
        element_shot(page, ".about__body", f"about/about-{vp_name}-emblem.png")
        report[f"about/{vp_name}"] = page.evaluate("() => ({ trees: document.querySelectorAll('img[src*=about-tree]').length, monograms: [...document.images].filter(i => /monogram/.test(i.src)).length })")
        if report[f"about/{vp_name}"] != {"trees": 1, "monograms": 1}:
            failures.append(f"about/{vp_name}: {report[f'about/{vp_name}']}")
        ready(page, "/")
        shot(page, f"home/home-{vp_name}-first-view.png", full_page=False)
        page.close()
    return report


def discovery_checks(browser, base, failures):
    page = browser.new_page()
    report = {}
    for path in ("/sitemap.xml", "/robots.txt"):
        r = page.request.get(urljoin(base, path))
        report[path] = {"status": r.status, "type": r.headers.get("content-type"), "body": r.text()}
        if r.status != 200:
            failures.append(f"{path}: HTTP {r.status}")
    sitemap = report["/sitemap.xml"]["body"]
    locs = [line.split("<loc>")[1].split("</loc>")[0] for line in sitemap.splitlines() if "<loc>" in line]
    report["sitemapUrls"] = locs
    for loc in locs:
        local = urljoin(base, urlparse(loc).path)
        if page.request.get(local).status != 200:
            failures.append(f"sitemap: {loc} is not served locally")
        if not loc.startswith("https://tylerbaum.dev/"):
            failures.append(f"sitemap: {loc} is not on the production origin")
    if "Sitemap: https://tylerbaum.dev/sitemap.xml" not in report["/robots.txt"]["body"]:
        failures.append("robots.txt does not name the sitemap")
    canon = page.goto(urljoin(base, "/work/brigid/"))
    report["canonicalBrigid"] = page.evaluate("() => document.querySelector('link[rel=canonical]').href")
    if report["canonicalBrigid"] != "https://tylerbaum.dev/work/brigid/":
        failures.append(f"canonical: {report['canonicalBrigid']}")
    page.close()
    return report


def fixture_checks(browser, ready, watch, checks_js, failures):
    """Writing and the Résumé link, on the fixture site."""
    report = {}
    probe = browser.new_page()
    try:
        status = probe.request.get(FIXTURE).status
    except Exception as exc:  # noqa: BLE001 - report, don't crash the run
        status = f"unreachable: {exc}"
    probe.close()
    if status != 200:
        failures.append(f"fixture site not available at {FIXTURE} ({status}); run tools/art/fixture_site.py and start fixture-preview")
        return {"available": False}
    report["available"] = True
    pages = {"home": "/", "writing": "/writing/", "article": "/writing/fixture-article/", "about": "/about/", "work": "/work/"}
    for name, path in pages.items():
        for vp_name in ("desktop", "tablet", "mobile", "narrow"):
            page = browser.new_page(viewport=VIEWPORTS[vp_name], device_scale_factor=1)
            bad = watch(page)
            response = page.goto(urljoin(FIXTURE, path), wait_until="networkidle")
            page.evaluate(INSTANT)
            checks = page.evaluate(checks_js)
            nav = page.evaluate("""() => { const n = document.querySelector('.site-nav');
                const links = [...n.querySelectorAll('.site-nav__link')];
                const hr = document.querySelector('.site-header').getBoundingClientRect();
                return { labels: links.map(a => a.textContent), hrefs: links.map(a => a.getAttribute('href')),
                         overflowing: links.filter(a => a.getBoundingClientRect().right > innerWidth || a.getBoundingClientRect().left < 0).length,
                         overlaps: links.some((a, i) => links.some((b, j) => i < j && (() => { const x = a.getBoundingClientRect(), y = b.getBoundingClientRect();
                             return x.left < y.right && y.left < x.right && x.top < y.bottom && y.top < x.bottom; })())) }; }""")
            label = f"fixture/{name}/{vp_name}"
            if response.status != 200 or checks["horizontalOverflow"] or bad:
                failures.append(f"{label}: status {response.status}, overflow {checks['horizontalOverflow']}, problems {bad}")
            if nav["hrefs"] != ["/", "/work/", "/writing/", "/about/", "/resume.pdf", "/#contact"]:
                failures.append(f"{label}: nav {nav['hrefs']}")
            if nav["overflowing"] or nav["overlaps"]:
                failures.append(f"{label}: nav links overflow or overlap {nav}")
            if name in ("writing", "article") and vp_name in ("desktop", "mobile"):
                shot(page, f"fixture/{name}-{vp_name}-full.png", full_page=True)
            if name == "home" and vp_name in ("desktop", "mobile"):
                page.locator("#writing").scroll_into_view_if_needed()
                element_shot(page, "#writing", f"fixture/home-writing-preview-{vp_name}.png")
            if name == "about":
                shot(page, f"fixture/nav-{vp_name}.png", clip={"x": 0, "y": 0, "width": VIEWPORTS[vp_name]["width"], "height": 220})
                if vp_name in ("desktop", "mobile"):
                    page.locator(".site-footer").scroll_into_view_if_needed()
                    element_shot(page, ".site-footer", f"fixture/footer-{vp_name}.png")
            report[label] = {"nav": nav["labels"]}
            page.close()
    page = browser.new_page()
    resume = page.request.get(urljoin(FIXTURE, "/resume.pdf"))
    draft = page.request.get(urljoin(FIXTURE, "/writing/fixture-draft/"))
    sitemap = page.request.get(urljoin(FIXTURE, "/sitemap.xml")).text()
    report["resume"] = {"status": resume.status, "type": resume.headers.get("content-type"), "head": resume.body()[:5].decode("latin-1")}
    report["draftStatus"] = draft.status
    report["sitemapWriting"] = "/writing/fixture-article/" in sitemap
    if resume.status != 200 or report["resume"]["head"] != "%PDF-":
        failures.append(f"fixture résumé: {report['resume']}")
    if draft.status != 404 or "fixture-draft" in sitemap:
        failures.append("fixture: the draft article is reachable or in the sitemap")
    if not report["sitemapWriting"] or "resume" in sitemap:
        failures.append("fixture sitemap: writing missing or résumé listed")
    page.close()
    return report


def phase05_checks(browser, base, pages, ready, watch, checks_js, failures):
    os.makedirs(PHASE05_OUT, exist_ok=True)
    report = {
        "pages": page_checks(browser, base, pages, ready, watch, checks_js, failures),
        "work": work_index_checks(browser, base, ready, failures),
        "projectNav": project_nav_checks(browser, base, failures),
        "contact": contact_checks(browser, base, failures),
        "footer": footer_checks(browser, base, failures),
        "aboutAndHome": about_and_home_captures(browser, base, ready, failures),
        "discovery": discovery_checks(browser, base, failures),
        "fixture": fixture_checks(browser, ready, watch, checks_js, failures),
    }
    with open(f"{PHASE05_OUT}/checks.json", "w") as fh:
        fh.write(json.dumps(report, indent=2, default=str))
        fh.write("\n")
    return report

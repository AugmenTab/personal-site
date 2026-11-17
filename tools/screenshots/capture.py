"""Capture proof screenshots and run browser checks on every generated page.

Development tool only; runs in the pinned Playwright container against the
static preview service:

    docker compose up -d preview
    docker compose --profile tools run --rm screenshots

Homepage captures keep their Phase 00 names in design/proof/latest/ (the visual
regression check compares latest/desktop-first-view.png with design/regression/).
Interior pages are captured into design/proof/latest/pages/. Results, including
the crawl-based link check and the no-JavaScript navigation walk, go to
design/proof/checks.txt. Exits 1 if any check fails.
"""

import json
import os
import sys
from urllib.parse import urldefrag, urljoin, urlparse

from playwright.sync_api import sync_playwright

from phase04 import PHASE04_OUT, phase04_captures
from phase05 import PHASE05_OUT, phase05_checks

BASE = os.environ.get("PREVIEW_URL", "http://localhost:8080/")
OUT = "design/proof/latest"
PAGES_OUT = f"{OUT}/pages"

# Every generated page, by capture name. The 404 document is also requested
# at a deep, non-existent path, where the preview server serves it (as a
# static host would) to prove its root-absolute URLs resolve anywhere.
PAGES = {
    "home": "/",
    "work": "/work/",
    "project-black": "/work/black/",
    "project-brigid": "/work/brigid/",
    "project-lockdown": "/work/lockdown/",
    "about": "/about/",
    "404": "/404.html",
    "404-deep": "/no/such/page/",
}

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


# Capture only: the site uses smooth scrolling, so a programmatic scroll (or
# the scroll that follows keyboard focus) is still animating when a
# screenshot is taken, and captures varied from run to run. Scrolling is made
# instant for captures; nothing static on the page depends on it.
INSTANT_SCROLL_JS = "() => { document.documentElement.style.scrollBehavior = 'auto'; }"

LOAD_ALL_JS = """
async () => {
  document.documentElement.style.scrollBehavior = 'auto';
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


def ready(page, path="/"):
    response = page.goto(urljoin(BASE, path), wait_until="networkidle")
    page.evaluate("document.fonts.ready")
    page.evaluate(LOAD_ALL_JS)
    return response


def watch(page, expected_404=None):
    """Collect HTTP errors and console errors/warnings for a page.

    expected_404 is the URL of a document deliberately requested at a missing
    path: its own 404 status (and Chromium's console report of it) is the
    point of the test, not a failure. Any other 4xx/5xx still counts."""
    bad = []

    def on_response(r):
        if r.status >= 400 and r.url != expected_404:
            bad.append(f"{r.status} {r.url}")

    def on_console(m):
        if m.type in ("error", "warning") and m.location.get("url") != expected_404:
            bad.append(f"console.{m.type}: {m.text}")

    page.on("response", on_response)
    page.on("console", on_console)
    return bad


def same_site(url):
    return urlparse(url).netloc == urlparse(BASE).netloc


def crawl(browser, failures):
    """Follow every internal link from the homepage (plus the 404 page).

    Each internal href/src must answer 200, and each #fragment must name an
    element on its target page. Returns the report for checks.txt."""
    page = browser.new_page()
    queue = [urljoin(BASE, "/"), urljoin(BASE, "/404.html")]
    seen = set()
    status = {}       # internal URL (no fragment) -> HTTP status
    ids = {}          # crawled page URL -> element ids on it
    fragments = []    # (source page, target page, fragment)
    problems = []
    while queue:
        url = queue.pop(0)
        if url in seen:
            continue
        seen.add(url)
        response = page.goto(url, wait_until="networkidle")
        if response is None or response.status != 200:
            problems.append(f"{url}: HTTP {response.status if response else 'no response'}")
            continue
        ids[url] = set(page.evaluate("() => [...document.querySelectorAll('[id]')].map(e => e.id)"))
        refs = page.evaluate("""() => [
            ...[...document.querySelectorAll('a[href]')].map(a => ['a', a.href]),
            ...[...document.querySelectorAll('img[src]')].map(i => ['img', i.src]),
            ...[...document.querySelectorAll('link[href]')].map(l => ['link', l.href]),
        ]""")
        for kind, ref in refs:
            if not same_site(ref):
                continue
            target, fragment = urldefrag(ref)
            if target not in status:
                status[target] = page.request.get(target).status
            if status[target] != 200:
                problems.append(f"{url}: {kind} {ref} -> HTTP {status[target]}")
            if kind == "a":
                if fragment:
                    fragments.append((url, target, fragment))
                queue.append(target)
    for source, target, fragment in fragments:
        if fragment not in ids.get(target, set()):
            problems.append(f"{source}: #{fragment} not found on {target}")
    page.close()
    if problems:
        failures.append(f"link check: {problems}")
    return {
        "pagesCrawled": sorted(urlparse(u).path for u in seen),
        "internalUrlsChecked": len(status),
        "fragmentLinksChecked": len(set(fragments)),
        "problems": problems,
    }


def no_js_walk(browser, failures):
    """Navigate the site by clicking real links with JavaScript disabled.

    Reduced motion makes in-page jumps instant (no smooth scrolling), so a
    link clicked after a same-page jump is not still moving."""
    context = browser.new_context(viewport=VIEWPORTS["desktop"], java_script_enabled=False, reduced_motion="reduce")
    page = context.new_page()
    page.goto(urljoin(BASE, "/"), wait_until="networkidle")
    steps = [
        ("nav Work", ".site-nav >> text=Work", "/work/"),
        ("Brigid card", ".project-card__link[href='/work/brigid/']", "/work/brigid/"),
        ("sidebar All projects", ".project-nav__back", "/work/"),
        ("nav About", ".site-nav >> text=About", "/about/"),
        ("About: get in touch", ".about__onward a", "/#contact"),
        ("monogram", ".site-nav__mark", "/"),
        ("hero CTA", ".hero__actions .button--primary", "/#selected-work"),
        ("hero secondary CTA", ".hero__actions .button--secondary", "/#contact"),
        ("nav Contact", ".site-nav >> text=Contact", "/#contact"),
        ("footer Work", ".site-footer__nav >> text=Work", "/work/"),
        ("footer About", ".site-footer__nav >> text=About", "/about/"),
        ("nav Home", ".site-nav >> text=Home", "/"),
    ]
    walk = []
    for label, selector, expected in steps:
        page.click(selector)
        page.wait_for_load_state("networkidle")
        parsed = urlparse(page.url)
        got = parsed.path + (f"#{parsed.fragment}" if parsed.fragment else "")
        walk.append(f"{label} -> {got}")
        if got != expected:
            failures.append(f"no-JS navigation: {label} went to {got}, expected {expected}")
    page.goto(urljoin(BASE, "/404.html"), wait_until="networkidle")
    page.click(".not-found__action a")
    page.wait_for_load_state("networkidle")
    walk.append(f"404 home button -> {urlparse(page.url).path}")
    if urlparse(page.url).path != "/":
        failures.append("no-JS navigation: 404 button did not reach /")
    page.screenshot(path=f"{OUT}/no-javascript.png", full_page=False)
    context.close()
    return walk


PROJECT_PAGES = {name: path for name, path in PAGES.items() if name.startswith("project-")}


def project_sidebar_checks(browser, failures):
    """The project sidebar on every project page, at every viewport:

    - it exists, with All projects, the current project and section links;
    - every section link names an element on the page, and clicking it with
      JavaScript disabled moves to that section, which ends up in view and
      not under the sidebar;
    - on desktop it sits in its own column (no overlap with the content)
      and stays in view while the page scrolls (sticky);
    - keyboard: Tab reaches the sidebar links in order, each visibly
      focused.
    """
    report = {}
    os.makedirs(PAGES_OUT, exist_ok=True)
    for page_name, path in PROJECT_PAGES.items():
        report[page_name] = {}
        for vp_name, viewport in VIEWPORTS.items():
            # Phase 05: at 900px and below the section links live in the
            # collapsed "On this page" disclosure (native <details>).
            compact = viewport["width"] <= 900
            link_selector = ".project-nav__index-list a" if compact else ".project-nav__sections a"
            context = browser.new_context(viewport=viewport, java_script_enabled=False)
            page = context.new_page()
            page.goto(urljoin(BASE, path), wait_until="networkidle")
            # Playwright's own scroll-into-view never settles under smooth
            # scrolling; see INSTANT_SCROLL_JS.
            page.evaluate(INSTANT_SCROLL_JS)
            links = page.eval_on_selector_all(
                link_selector, "els => els.map(a => a.getAttribute('href'))")
            entry = {"sectionLinks": links, "clicks": []}
            if not page.query_selector(".project-nav__back[href='/work/']"):
                failures.append(f"{page_name}/{vp_name}: sidebar has no All projects link")
            if not page.query_selector(".project-nav__current[aria-current='page']"):
                failures.append(f"{page_name}/{vp_name}: sidebar has no current project")
            if not links:
                failures.append(f"{page_name}/{vp_name}: sidebar has no section links")
            for href in links:
                if compact and not page.evaluate("() => document.querySelector('.project-nav__index').open"):
                    page.click(".project-nav__summary")
                page.click(f"{link_selector}[href='{href}']")
                page.wait_for_timeout(100)
                state = page.evaluate(
                    """(id) => { const t = document.getElementById(id); if (!t) return null;
                       const r = t.getBoundingClientRect();
                       const n = document.querySelector('.project-nav').getBoundingClientRect();
                       const sideBySide = n.right <= r.left;
                       return { hash: location.hash, top: Math.round(r.top),
                                inView: r.top >= 0 && r.top < innerHeight,
                                underSidebar: !sideBySide && r.top < n.bottom && n.bottom > 0 && n.top < innerHeight && getComputedStyle(document.querySelector('.project-nav')).position !== 'static' }; }""",
                    href[1:])
                entry["clicks"].append({href: state})
                if state is None:
                    failures.append(f"{page_name}/{vp_name}: {href} has no target")
                elif state["hash"] != href or not state["inView"] or state["underSidebar"]:
                    failures.append(f"{page_name}/{vp_name}: {href} navigation problem {state}")
            if vp_name == "desktop":
                geometry = page.evaluate(
                    """() => { const n = document.querySelector('.project-nav').getBoundingClientRect();
                       const c = (document.querySelector('.project__body') || document.querySelector('.project')).getBoundingClientRect();
                       window.scrollTo(0, document.body.scrollHeight);
                       const after = document.querySelector('.project-nav').getBoundingClientRect();
                       return { navRight: Math.round(n.right), contentLeft: Math.round(c.left),
                                stickyTopAfterScroll: Math.round(after.top),
                                position: getComputedStyle(document.querySelector('.project-nav')).position }; }""")
                entry["desktopGeometry"] = geometry
                if geometry["navRight"] > geometry["contentLeft"]:
                    failures.append(f"{page_name}: sidebar overlaps the content {geometry}")
                if geometry["position"] != "sticky":
                    failures.append(f"{page_name}: sidebar is not sticky on desktop")
            context.close()

            # Keyboard order through the sidebar (JavaScript on, default motion).
            # Compact: All projects, the summary (Enter opens it), the links.
            page = browser.new_page(viewport=viewport)
            page.goto(urljoin(BASE, path), wait_until="networkidle")
            page.evaluate(INSTANT_SCROLL_JS)
            page.focus(".project-nav__back")
            stops = [page.evaluate("() => document.activeElement.getAttribute('href')")]
            describe = (
                "() => { const e = document.activeElement; const s = getComputedStyle(e);"
                " const name = e.tagName === 'SUMMARY' ? 'summary' : e.getAttribute('href');"
                " return name + (s.outlineStyle !== 'none' && parseFloat(s.outlineWidth) > 0 ? '' : ' (no outline)'); }")
            for i in range(1 + len(links)):
                page.keyboard.press("Tab")
                stops.append(page.evaluate(describe))
                if compact and i == 0:
                    page.keyboard.press("Enter")
            expected = ["/work/", "summary" if compact else path] + links
            entry["keyboardStops"] = stops
            if stops != expected:
                failures.append(f"{page_name}/{vp_name}: sidebar keyboard order {stops}, expected {expected}")
            if vp_name == "desktop":
                page.screenshot(path=f"{PAGES_OUT}/{page_name}-sidebar-focus.png", full_page=False)
            page.close()
            report[page_name][vp_name] = entry
    return report


def focus_checks(browser, failures):
    """On every page, the first Tab focuses the skip link and activating it
    moves to <main>; record the first few focus stops."""
    report = {}
    for name, path in PAGES.items():
        page = browser.new_page(viewport=VIEWPORTS["desktop"])
        page.goto(urljoin(BASE, path), wait_until="networkidle")
        order = []
        for _ in range(7):
            page.keyboard.press("Tab")
            order.append(page.evaluate(
                "() => { const e = document.activeElement;"
                " return `${e.tagName.toLowerCase()} \"${(e.innerText || e.getAttribute('aria-label') || '').trim().replace(/\\s+/g,' ')}\" -> ${e.getAttribute('href')}`; }"))
        page.goto(urljoin(BASE, path), wait_until="networkidle")
        page.keyboard.press("Tab")
        skip = page.evaluate("() => document.activeElement.classList.contains('skip-link')")
        page.keyboard.press("Enter")
        landed = page.evaluate("() => location.hash")
        visible = page.evaluate("() => { const r = document.activeElement.getBoundingClientRect(); return r.width > 0 && r.height > 0; }")
        if not skip:
            failures.append(f"{name}: first Tab did not focus the skip link")
        if landed != "#main":
            failures.append(f"{name}: skip link went to {landed!r}")
        report[name] = {"firstTabIsSkipLink": skip, "skipLinkTarget": landed, "focusOrder": order, "focusVisible": visible}
        page.close()
    return report


PHASE03_OUT = f"{OUT}/phase-03"

# The required homepage order (Phase 03 §11; Phase 05 replaced About with
# Contact). #writing is conditional.
HOME_SECTIONS = ["top", "black", "selected-work", "philosophy", "writing", "contact"]

SECTION_CAPTURES = {
    "desktop": ["black", "selected-work", "philosophy", "writing", "contact"],
    "tablet": ["black", "selected-work", "philosophy", "contact"],
    "mobile": ["black", "selected-work", "philosophy", "contact"],
}

HOME_STRUCTURE_JS = """
() => {
  const ids = [...document.querySelectorAll('main > *, main .stage > section')]
    .map(e => e.id).filter(Boolean);
  const cards = [...document.querySelectorAll('#selected-work .project-card')].map(c => {
    const t = c.querySelector('.project-card__title');
    return { title: t.textContent, href: c.querySelector('.project-card__link').getAttribute('href'),
             titleClipped: t.scrollWidth > t.clientWidth + 1,
             height: Math.round(c.getBoundingClientRect().height),
             width: Math.round(c.getBoundingClientRect().width) };
  });
  const black = document.getElementById('black');
  const controls = black.querySelectorAll('button, input, textarea, select, [contenteditable], form').length;
  const blackLinks = [...black.querySelectorAll('a')].map(a => a.getAttribute('href'));
  const lede = document.querySelector('.philosophy__lede');
  const frame = document.querySelector('.feature__frame').getBoundingClientRect();
  return { sectionOrder: ids, cards, blackControls: controls, blackLinks,
           philosophyLedeWidth: lede ? Math.round(lede.getBoundingClientRect().width) : null,
           featureFrameTop: Math.round(frame.top + scrollY),
           writingPresent: !!document.getElementById('writing') };
}
"""


def phase03_captures(browser, failures):
    """Phase 03 evidence: full-page and per-section captures of the
    homepage at every viewport (plus a wide desktop), its section order,
    the Selected Work cards' destinations, and the Black teaser's lack of
    controls. Writes into design/proof/latest/phase-03/."""
    os.makedirs(PHASE03_OUT, exist_ok=True)
    report = {}
    viewports = dict(VIEWPORTS, wide={"width": 1920, "height": 1080})
    for vp_name, viewport in viewports.items():
        page = browser.new_page(viewport=viewport, device_scale_factor=1)
        ready(page)
        page.screenshot(path=f"{PHASE03_OUT}/home-{vp_name}-full.png", full_page=True)
        page.screenshot(path=f"{PHASE03_OUT}/home-{vp_name}-hero.png", full_page=False)
        info = page.evaluate(HOME_STRUCTURE_JS)
        expected = [s for s in HOME_SECTIONS if s != "writing" or info["writingPresent"]]
        if info["sectionOrder"] != expected:
            failures.append(f"home/{vp_name}: section order {info['sectionOrder']}, expected {expected}")
        if info["blackControls"]:
            failures.append(f"home/{vp_name}: the Black teaser contains {info['blackControls']} control(s)")
        for card in info["cards"]:
            if card["titleClipped"]:
                failures.append(f"home/{vp_name}: card title clipped: {card['title']}")
            status = page.request.get(urljoin(BASE, card["href"])).status
            card["status"] = status
            if status != 200 or not card["href"].startswith("/work/"):
                failures.append(f"home/{vp_name}: card {card['title']} -> {card['href']} (HTTP {status})")
        for href in info["blackLinks"]:
            if page.request.get(urljoin(BASE, href)).status != 200:
                failures.append(f"home/{vp_name}: Black teaser link {href} does not resolve")
        for section in SECTION_CAPTURES.get(vp_name, []):
            locator = page.locator(f"#{section}")
            if locator.count():
                locator.screenshot(path=f"{PHASE03_OUT}/{vp_name}-{section}.png")
        report[vp_name] = info
        page.close()

    # Without JavaScript the whole page is still there.
    context = browser.new_context(viewport=VIEWPORTS["desktop"], java_script_enabled=False)
    page = context.new_page()
    page.goto(BASE, wait_until="networkidle")
    page.screenshot(path=f"{PHASE03_OUT}/home-desktop-no-javascript-full.png", full_page=True)
    report["noJavaScriptSections"] = page.eval_on_selector_all(
        "main section[id]", "els => els.filter(e => e.getBoundingClientRect().height > 0).map(e => e.id)")
    context.close()
    return report


def main() -> int:
    report = {}
    failures = []
    with sync_playwright() as p:
        browser = p.chromium.launch()

        os.makedirs(PAGES_OUT, exist_ok=True)
        report["pages"] = {}
        for page_name, path in PAGES.items():
            for name, viewport in VIEWPORTS.items():
                page = browser.new_page(viewport=viewport, device_scale_factor=1)
                bad = watch(page, urljoin(BASE, path) if page_name == "404-deep" else None)
                response = ready(page, path)
                page.evaluate("document.fonts.ready")
                label = name if page_name == "home" else f"{page_name}/{name}"
                if page_name == "home":
                    # Phase 00 names: the regression check reads these.
                    page.screenshot(path=f"{OUT}/{name}.png", full_page=True)
                    page.screenshot(path=f"{OUT}/{name}-first-view.png", full_page=False)
                else:
                    page.screenshot(path=f"{PAGES_OUT}/{page_name}-{name}.png", full_page=True)
                checks = page.evaluate(CHECKS_JS)
                checks["httpStatus"] = response.status if response else None
                checks["httpErrorsAndConsole"] = bad
                if page_name == "home":
                    report[name] = checks
                else:
                    report["pages"].setdefault(page_name, {})[name] = {
                        k: checks[k] for k in ("httpStatus", "horizontalOverflow", "headings", "brokenFragmentLinks", "httpErrorsAndConsole")
                    } | {"imagesLoaded": all(i["loaded"] for i in checks["images"])}
                expected_status = 404 if page_name == "404-deep" else 200
                if checks["httpStatus"] != expected_status:
                    failures.append(f"{label}: HTTP {checks['httpStatus']}, expected {expected_status}")
                if checks["horizontalOverflow"]:
                    failures.append(f"{label}: horizontal overflow ({checks['scrollWidth']} > {checks['clientWidth']})")
                if checks["brokenFragmentLinks"]:
                    failures.append(f"{label}: broken fragment links {checks['brokenFragmentLinks']}")
                if any(not i["loaded"] for i in checks["images"]):
                    failures.append(f"{label}: image(s) failed to load")
                if sum(1 for h in checks["headings"] if h.startswith("h1:")) != 1:
                    failures.append(f"{label}: expected exactly one h1, got {checks['headings']}")
                if bad:
                    failures.append(f"{label}: http/console problems {bad}")
                page.close()

        report["linkCheck"] = crawl(browser, failures)
        report["noJavaScriptNavigation"] = no_js_walk(browser, failures)
        report["focus"] = focus_checks(browser, failures)
        report["projectSidebar"] = project_sidebar_checks(browser, failures)

        # Branding close-ups at desktop: the About composition (tree emblem,
        # on the About page since Phase 05) and the nav medallion + divider
        # beneath the name.
        page = browser.new_page(viewport=VIEWPORTS["desktop"])
        ready(page)
        page.evaluate("document.fonts.ready")
        page.screenshot(path=f"{OUT}/branding-nav-divider.png",
                        clip={"x": 360, "y": 0, "width": 720, "height": 300})
        ready(page, "/about/")
        page.locator(".about__body").screenshot(path=f"{OUT}/about-section.png")
        page.close()
        report["monogramImages"] = {}
        for page_name, path in PAGES.items():
            page = browser.new_page(viewport=VIEWPORTS["desktop"])
            page.goto(urljoin(BASE, path), wait_until="networkidle")
            placement = page.evaluate(
                "() => [...document.images].filter(i => /monogram/.test(i.src)).map(i => i.closest('nav') ? 'nav' : 'elsewhere')")
            report["monogramImages"][page_name] = placement
            if placement != ["nav"]:
                failures.append(f"{page_name}: monogram must appear once, in the nav: {placement}")
            page.close()
        page = browser.new_page(viewport=VIEWPORTS["mobile"])
        ready(page, "/about/")
        page.evaluate("document.fonts.ready")
        page.locator(".about__body").screenshot(path=f"{OUT}/about-section-mobile.png")
        page.close()

        # Keyboard: tab from the top of the page and record the focus order.
        page = browser.new_page(viewport=VIEWPORTS["desktop"])
        page.goto(BASE, wait_until="networkidle")
        page.evaluate("document.fonts.ready")
        page.evaluate(INSTANT_SCROLL_JS)
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
        page.evaluate(INSTANT_SCROLL_JS)
        # skip link, Home, Work, monogram, About, Contact, primary CTA
        for _ in range(7):
            page.keyboard.press("Tab")
        page.wait_for_timeout(500)  # let focus/hover transitions (<= 200ms) finish
        page.screenshot(path=f"{OUT}/keyboard-focus.png", full_page=False)
        # Keep tabbing (secondary CTA, Explore Black, ...) to the first
        # Selected Work card link; every stop on the way must show a ring.
        homeStops = []
        for _ in range(12):
            page.keyboard.press("Tab")
            stop = page.evaluate(
                "() => { const e = document.activeElement; const s = getComputedStyle(e);"
                " const ring = s.outlineStyle !== 'none' && parseFloat(s.outlineWidth) > 0;"
                " const after = getComputedStyle(e, '::after');"
                " const cardRing = e.classList.contains('project-card__link') && after.outlineStyle !== 'none';"
                " return { href: e.getAttribute('href'), focusVisible: ring || cardRing,"
                "          card: e.classList.contains('project-card__link') }; }")
            homeStops.append(stop)
            if not stop["focusVisible"]:
                failures.append(f"home keyboard: no visible focus on {stop['href']}")
            if stop["card"]:
                break
        report["homeKeyboardToFirstCard"] = homeStops
        if not homeStops or not homeStops[-1]["card"]:
            failures.append("home keyboard: never reached a Selected Work card")
        page.evaluate("document.activeElement.closest('article').scrollIntoView({block: 'center', behavior: 'instant'})")
        page.wait_for_timeout(500)
        page.screenshot(path=f"{OUT}/keyboard-focus-card.png", full_page=False)
        page.close()

        report["phase03"] = phase03_captures(browser, failures)
        report["phase04"] = phase04_captures(browser, BASE, PROJECT_PAGES, VIEWPORTS, ready, failures)
        report["phase05"] = phase05_checks(browser, BASE, PAGES, ready, watch, CHECKS_JS, failures)

        # Reduced motion: confirm animations and smooth scrolling are off.
        context = browser.new_context(viewport=VIEWPORTS["desktop"], reduced_motion="reduce")
        report["reducedMotion"] = {}
        for page_name, path in PAGES.items():
            page = context.new_page()
            page.goto(urljoin(BASE, path), wait_until="networkidle")
            page.evaluate("document.fonts.ready")
            result = page.evaluate(
                "() => ({ runningAnimations: document.getAnimations().length,"
                " scrollBehavior: getComputedStyle(document.documentElement).scrollBehavior })")
            report["reducedMotion"][page_name] = result
            if result["runningAnimations"] != 0:
                failures.append(f"{page_name}: reduced motion: animations still running")
            if result["scrollBehavior"] != "auto":
                failures.append(f"{page_name}: reduced motion: smooth scrolling still enabled")
            if page_name == "home":
                page.screenshot(path=f"{OUT}/reduced-motion.png", full_page=False)
            page.close()
        context.close()

        browser.close()

    report["failures"] = failures
    with open(f"{OUT}/checks.txt", "w") as fh:
        fh.write(json.dumps(report, indent=2))
        fh.write("\n")
    # The container runs as root; hand the evidence to whoever owns the
    # bind-mounted proof directory (matters on Linux hosts only).
    st = os.stat(OUT)
    for directory in (OUT, PAGES_OUT, PHASE03_OUT, PHASE04_OUT, PHASE05_OUT):
        for name in [""] + os.listdir(directory):
            try:
                os.chown(os.path.join(directory, name), st.st_uid, st.st_gid)
            except PermissionError:
                pass
    print(json.dumps(report, indent=2))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

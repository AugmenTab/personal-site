"""Phase 06: accessibility audit, keyboard walk, contrast, target size,
zoom/reflow, text spacing, motion, deterministic captures.

Development tool only. Runs in the pinned Playwright container against the
static preview (and the fixture preview for Writing and the Résumé):

    docker compose up -d preview
    docker compose --profile tools up -d fixture-preview
    docker compose --profile tools run --rm screenshots python3 tools/screenshots/phase06.py

Writes design/proof/latest/phase-06/ (git-ignored): audit.json, a
summary in audit.txt and the deterministic captures in stable/. Exits 1 on
any failure. Performance is measured separately by perf.py.
"""

import hashlib
import io
import json
import os
import sys
from urllib.parse import urljoin

import numpy as np
from PIL import Image
from playwright.sync_api import sync_playwright

import stable

BASE = os.environ.get("PREVIEW_URL", "http://localhost:8080/")
FIXTURE = os.environ.get("FIXTURE_URL", "http://fixture-preview/")
OUT = "design/proof/latest/phase-06"
AXE = "/opt/axe/axe.min.js"

PAGES = {
    "home": "/",
    "work": "/work/",
    "black": "/work/black/",
    "brigid": "/work/brigid/",
    "lockdown": "/work/lockdown/",
    "about": "/about/",
    "404": "/404.html",
}
FIXTURE_PAGES = {
    "fixture-home": "/",
    "fixture-writing": "/writing/",
    "fixture-article": "/writing/fixture-article/",
}

VIEWPORTS = {
    "narrow": {"width": 320, "height": 640},
    "mobile": {"width": 390, "height": 844},
    "tablet": {"width": 768, "height": 1024},
    "laptop": {"width": 1280, "height": 800},
    "desktop": {"width": 1440, "height": 900},
    "wide": {"width": 1920, "height": 1080},
}

AXE_TAGS = ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa", "best-practice"]


def url_for(name, path):
    return urljoin(FIXTURE if name.startswith("fixture-") else BASE, path)


def all_pages():
    return {**PAGES, **FIXTURE_PAGES}


# ---------------------------------------------------------------------------
# axe-core

def axe_scan(browser, failures):
    report = {}
    for name, path in all_pages().items():
        for vp in ("desktop", "mobile"):
            ctx = stable.new_context(browser, VIEWPORTS[vp])
            page = ctx.new_page()
            page.goto(url_for(name, path), wait_until="networkidle")
            stable.settle(page)
            page.add_script_tag(path=AXE)
            result = page.evaluate(
                "async (tags) => { const r = await axe.run(document, { runOnly: { type: 'tag', values: tags }, resultTypes: ['violations', 'incomplete'] });"
                " const slim = list => list.map(v => ({ id: v.id, impact: v.impact, tags: v.tags.filter(t => t.startsWith('wcag') || t === 'best-practice'),"
                "   help: v.help, nodes: v.nodes.slice(0, 8).map(n => ({ target: n.target.join(' '), summary: (n.failureSummary || n.any.map(a => a.message).join('; ')).slice(0, 300) })) }));"
                " return { violations: slim(r.violations), incomplete: slim(r.incomplete), passes: r.passes ? r.passes.length : null }; }",
                AXE_TAGS)
            label = f"{name}/{vp}"
            report[label] = result
            for v in result["violations"]:
                wcag = any(t.startswith("wcag") for t in v["tags"])
                if wcag:
                    failures.append(f"axe {label}: {v['id']} ({v['impact']}) {[n['target'] for n in v['nodes']]}")
            ctx.close()
    return report


# ---------------------------------------------------------------------------
# Contrast against the rendered background

def luminance(rgb):
    c = np.asarray(rgb, dtype=np.float64) / 255.0
    c = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    return 0.2126 * c[..., 0] + 0.7152 * c[..., 1] + 0.0722 * c[..., 2]


def ratio(l1, l2):
    hi, lo = max(l1, l2), min(l1, l2)
    return (hi + 0.05) / (lo + 0.05)


TEXT_BOXES_JS = """
() => {
  // Rects are in viewport coordinates at the current scroll position; only
  // runs wholly inside the viewport are returned (the caller scrolls).
  const inside = r => r.top >= 0 && r.left >= 0 && r.bottom <= innerHeight && r.right <= innerWidth;
  const out = [];
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  const seen = new Map();
  while (walker.nextNode()) {
    const t = walker.currentNode;
    if (!t.textContent.trim()) continue;
    const el = t.parentElement;
    if (!el || el.closest('.visually-hidden, script, style, [hidden], .skip-link')) continue;
    const s = getComputedStyle(el);
    if (s.visibility === 'hidden' || s.display === 'none' || parseFloat(s.opacity) === 0) continue;
    const range = document.createRange();
    range.selectNodeContents(t);
    const rects = [...range.getClientRects()].filter(r => r.width > 0 && r.height > 0);
    if (!rects.length || !rects.every(inside)) continue;
    let entry = seen.get(el);
    if (!entry) {
      const m = s.color.match(/[\\d.]+/g).map(Number);
      const fill = s.webkitTextFillColor || '';
      const gradient = (s.backgroundClip === 'text' || s.webkitBackgroundClip === 'text') || /rgba?\\(0, 0, 0, 0\\)/.test(fill) && s.backgroundImage !== 'none';
      const inheritedGradient = !!el.closest('.hero__name-word, .project-hero .project__title');
      entry = { selector: el.tagName.toLowerCase() + (el.className && typeof el.className === 'string' ? '.' + el.className.trim().split(/\\s+/).join('.') : ''),
                text: '', color: m.slice(0, 3), alpha: m.length > 3 ? m[3] : 1,
                fontSize: parseFloat(s.fontSize), fontWeight: parseInt(s.fontWeight, 10),
                gradient: gradient || inheritedGradient, rects: [] };
      seen.set(el, entry);
      out.push(entry);
    }
    entry.text = (entry.text + ' ' + t.textContent.trim()).trim().slice(0, 60);
    for (const r of rects) entry.rects.push([r.left, r.top, r.width, r.height]);
  }
  return out;
}
"""

TOGGLE_HIDE_JS = """
([on, css]) => {
  let s = document.getElementById('__p06_hide');
  if (!s) { s = document.createElement('style'); s.id = '__p06_hide'; s.textContent = css; document.head.appendChild(s); }
  s.disabled = !on;
}
"""

HIDE_TEXT_CSS = """
*, *::before, *::after { color: transparent !important; -webkit-text-fill-color: transparent !important;
  text-shadow: none !important; text-decoration-color: transparent !important; caret-color: transparent !important; }
"""

# The same, but the text's own shadow (a dark halo, drawn even when the
# glyphs are transparent) stays: the background the glyphs are really read
# against. Pass/fail uses this; the shadow-free figure is reported too.
HIDE_TEXT_KEEP_SHADOW_CSS = HIDE_TEXT_CSS.replace("text-shadow: none !important; ", "")


def full_png(page):
    return np.asarray(Image.open(io.BytesIO(page.screenshot(full_page=True))).convert("RGB"))


def contrast_scan(browser, failures):
    """Each text run: its computed colour against the 95th-percentile
    (lightest) background pixel under it, from a capture with all text made
    transparent. The page grain, artwork, gradients and the text's own dark
    halo (text-shadow) are included: the background the glyphs are read
    against. The figure without the halo is reported as well."""
    report = {}
    for name, path in all_pages().items():
        for vp in ("desktop", "mobile"):
            ctx = stable.new_context(browser, VIEWPORTS[vp])
            page = ctx.new_page()
            page.goto(url_for(name, path), wait_until="networkidle")
            stable.settle(page)
            # Viewport-sized slices: a full-page capture resizes the
            # viewport, which moves vh-sized layout away from measured rects.
            height = page.evaluate("() => document.documentElement.scrollHeight")
            step = VIEWPORTS[vp]["height"] // 2
            measured_keys = set()
            work = []
            for y in range(0, height, step):
                page.evaluate("(y) => window.scrollTo(0, y)", y)
                stable.settle(page)
                boxes = page.evaluate(TEXT_BOXES_JS)
                shots = []
                for css in (HIDE_TEXT_KEEP_SHADOW_CSS, HIDE_TEXT_CSS):
                    page.evaluate(TOGGLE_HIDE_JS, [True, css])
                    stable.settle(page)
                    shots.append(np.asarray(Image.open(io.BytesIO(page.screenshot())).convert("RGB")))
                    page.evaluate("() => document.getElementById('__p06_hide').remove()")
                for b in boxes:
                    key = (b["selector"], b["text"])
                    if key in measured_keys:
                        continue
                    measured_keys.add(key)
                    work.append((b, shots))
            results = []
            for b, (bg, bare) in work:
                h, w, _ = bg.shape
                if b["gradient"]:
                    results.append({"selector": b["selector"], "text": b["text"], "note": "gradient-filled display text; measured separately"})
                    continue
                pixels, bare_pixels = [], []
                for x, y, rw, rh in b["rects"]:
                    x0, y0 = max(0, int(x)), max(0, int(y))
                    x1, y1 = min(w, int(x + rw + 0.999)), min(h, int(y + rh + 0.999))
                    if x1 > x0 and y1 > y0:
                        pixels.append(bg[y0:y1, x0:x1].reshape(-1, 3))
                        bare_pixels.append(bare[y0:y1, x0:x1].reshape(-1, 3))
                if not pixels:
                    continue
                px = np.concatenate(pixels)
                bare95 = float(np.percentile(luminance(np.concatenate(bare_pixels)), 95))
                lum = luminance(px)
                bg95 = float(np.percentile(lum, 95))
                bgmed = float(np.median(lum))
                color = np.array(b["color"], dtype=np.float64)
                if b["alpha"] < 1:
                    # Blend against the median background (an approximation for translucent text).
                    med = px[np.argsort(lum)[len(lum) // 2]].astype(np.float64)
                    color = b["alpha"] * color + (1 - b["alpha"]) * med
                lt = float(luminance(color))
                large = b["fontSize"] >= 24 or (b["fontSize"] >= 18.66 and b["fontWeight"] >= 700)
                need = 3.0 if large else 4.5
                worst = ratio(lt, bg95)
                entry = {"selector": b["selector"], "text": b["text"], "fontSize": b["fontSize"],
                         "large": large, "worst": round(worst, 2), "median": round(ratio(lt, bgmed), 2),
                         "worstWithoutShadow": round(ratio(lt, bare95), 2), "need": need}
                results.append(entry)
                if worst < need:
                    failures.append(f"contrast {name}/{vp}: {b['selector']} \"{b['text'][:30]}\" {worst:.2f} < {need}")
            measured = [r for r in results if "worst" in r]
            report[f"{name}/{vp}"] = {
                "measured": len(measured),
                "lowest": sorted(measured, key=lambda r: r["worst"] / r["need"])[:6],
                "gradientText": [r for r in results if "note" in r],
            }
            ctx.close()
    return report


def gradient_text_contrast(browser):
    """The gilded display text (hero name; a hero dossier title) is filled
    with a gradient whose darkest stop is #9B7E4B. Measure that stop and the
    lightest stop against the lightest background pixel behind the words."""
    report = {}
    ctx = stable.new_context(browser, VIEWPORTS["desktop"])
    page = ctx.new_page()
    page.goto(url_for("home", "/"), wait_until="networkidle")
    stable.settle(page)
    rect = page.evaluate("() => { const r = document.querySelector('.hero__name').getBoundingClientRect(); return [r.left, r.top, r.width, r.height]; }")
    page.add_style_tag(content=HIDE_TEXT_CSS + " .hero__name-word { background: none !important; } .hero__name { filter: none !important; }")
    stable.settle(page)
    bg = np.asarray(Image.open(io.BytesIO(page.screenshot())).convert("RGB"))
    x, y, w, h = [int(v) for v in rect]
    lum = luminance(bg[y:y + h, x:x + w].reshape(-1, 3))
    bg95 = float(np.percentile(lum, 95))
    darkest = float(luminance(np.array([0x9B, 0x7E, 0x4B])))
    report["heroName"] = {"bg95": round(bg95, 4), "darkestStop": round(ratio(darkest, bg95), 2),
                          "note": "large text (>=24px): 3:1 required; the drop shadow behind the words is excluded"}
    ctx.close()
    return report


# ---------------------------------------------------------------------------
# Non-text contrast: the focus indicator against what it replaces

def focus_indicator_scan(browser, failures):
    """For every focusable element on each page (desktop and mobile): the
    pixels that change when it receives keyboard focus, compared with the
    same pixels unfocused (WCAG 1.4.11: 3:1 against adjacent colours). The
    figure is the 90th-percentile contrast among changed pixels, so a
    single anti-aliased edge cannot pass or fail it."""
    report = {}
    for name, path in all_pages().items():
        for vp in ("desktop", "mobile"):
            ctx = stable.new_context(browser, VIEWPORTS[vp])
            page = ctx.new_page()
            page.goto(url_for(name, path), wait_until="networkidle")
            # Disclosures open, so the links inside them are tested too (the
            # collapsed state's summary is covered by the keyboard walk).
            page.evaluate("() => document.querySelectorAll('details').forEach(d => { d.open = true; })")
            stable.settle(page)
            count = page.evaluate("() => { const els = [...document.querySelectorAll('a[href], button, input, summary, [tabindex]:not([tabindex=\"-1\"])')]"
                                  ".filter(e => e.checkVisibility({ contentVisibilityAuto: true, opacityProperty: true, visibilityProperty: true })); els.forEach((e, i) => e.dataset.p06 = i); return els.length; }")
            rows = []
            for i in range(count):
                # Reach the element the way a keyboard user does: focus the
                # previous stop's position, then Tab (so :focus-visible applies).
                sel = f"[data-p06='{i}']"
                el = page.query_selector(sel)
                if el is None:
                    continue
                el.scroll_into_view_if_needed()
                box = el.bounding_box()
                if not box or box["width"] == 0:
                    continue
                pad = 10
                clip = {"x": max(0, box["x"] - pad), "y": max(0, box["y"] - pad),
                        "width": box["width"] + 2 * pad, "height": box["height"] + 2 * pad}
                vw = VIEWPORTS[vp]["width"]
                clip["width"] = min(clip["width"], vw - clip["x"])
                page.evaluate("() => document.activeElement && document.activeElement.blur()")
                page.mouse.move(0, 0)
                stable.settle(page)
                before = np.asarray(Image.open(io.BytesIO(page.screenshot(clip=clip))).convert("RGB"))
                page.evaluate("(s) => { const e = document.querySelector(s); e.focus({ focusVisible: true }); }", sel)
                visible = page.evaluate("(s) => document.querySelector(s).matches(':focus-visible')", sel)
                if not visible:
                    # Programmatic focus does not always count as keyboard
                    # focus; press Shift+Tab then Tab to arrive by keyboard.
                    page.keyboard.press("Shift+Tab")
                    page.keyboard.press("Tab")
                    visible = page.evaluate("(s) => document.querySelector(s) === document.activeElement", sel)
                stable.settle(page)
                after = np.asarray(Image.open(io.BytesIO(page.screenshot(clip=clip))).convert("RGB"))
                if before.shape != after.shape:
                    continue
                changed = np.any(np.abs(before.astype(int) - after.astype(int)) > 24, axis=2)
                n = int(changed.sum())
                label = page.evaluate("(s) => { const e = document.querySelector(s); return (e.tagName.toLowerCase() + ' ' + (e.getAttribute('href') || e.textContent.trim().slice(0, 30))).trim(); }", sel)
                if n < 8:
                    rows.append({"element": label, "changedPixels": n, "contrast": None})
                    failures.append(f"focus indicator {name}/{vp}: {label} shows no visible change")
                    continue
                lb = luminance(before[changed])
                la = luminance(after[changed])
                ratios = (np.maximum(lb, la) + 0.05) / (np.minimum(lb, la) + 0.05)
                c = float(np.percentile(ratios, 90))
                rows.append({"element": label, "changedPixels": n, "contrast": round(c, 2)})
                if c < 3.0:
                    failures.append(f"focus indicator {name}/{vp}: {label} contrast {c:.2f} < 3")
            report[f"{name}/{vp}"] = {"checked": len(rows), "lowest": sorted([r for r in rows if r["contrast"]], key=lambda r: r["contrast"])[:4],
                                      "none": [r for r in rows if r["contrast"] is None]}
            ctx.close()
    return report


# ---------------------------------------------------------------------------
# Keyboard: a full Tab walk on every page

WALK_JS = """
(n) => {
  const e = document.activeElement;
  if (!e || e === document.body) return { body: true };
  const r = e.getBoundingClientRect();
  const s = getComputedStyle(e);
  const after = getComputedStyle(e, '::after');
  const ring = (s.outlineStyle !== 'none' && parseFloat(s.outlineWidth) > 0)
            || (after.outlineStyle !== 'none' && parseFloat(after.outlineWidth) > 0);
  const hiddenAncestor = !!e.closest('[hidden], [aria-hidden="true"], [inert]');
  const all = [...document.querySelectorAll('*')];
  return {
    body: false,
    index: all.indexOf(e),
    label: (e.tagName.toLowerCase() + ' ' + (e.getAttribute('href') || e.id || e.textContent.trim().slice(0, 24))).trim(),
    inViewport: r.bottom > 0 && r.top < innerHeight && r.right > 0 && r.left < innerWidth,
    size: [Math.round(r.width), Math.round(r.height)],
    ring, hiddenAncestor,
  };
}
"""


def keyboard_walk(browser, failures):
    report = {}
    for name, path in all_pages().items():
        for vp in ("desktop", "mobile", "narrow"):
            ctx = stable.new_context(browser, VIEWPORTS[vp], reduced_motion="reduce")
            page = ctx.new_page()
            page.goto(url_for(name, path), wait_until="networkidle")
            stops = []
            for _ in range(120):
                page.keyboard.press("Tab")
                st = page.evaluate(WALK_JS, 0)
                if st["body"] or (stops and st["index"] == stops[0]["index"]):
                    break
                stops.append(st)
            label = f"{name}/{vp}"
            problems = []
            for a, b in zip(stops, stops[1:]):
                if b["index"] < a["index"]:
                    problems.append(f"order: {b['label']} after {a['label']}")
            for st in stops:
                if not st["inViewport"]:
                    problems.append(f"focus off screen: {st['label']}")
                if not st["ring"]:
                    problems.append(f"no outline: {st['label']}")
                if st["hiddenAncestor"]:
                    problems.append(f"focus inside hidden content: {st['label']}")
                if st["size"][0] == 0 or st["size"][1] == 0:
                    problems.append(f"zero-size focus: {st['label']}")
            # No trap: Shift+Tab from the last stop walks back to the first.
            back = 0
            for _ in range(len(stops) + 2):
                page.keyboard.press("Shift+Tab")
                st = page.evaluate(WALK_JS, 0)
                if st["body"] or st["index"] == stops[0]["index"]:
                    break
                back += 1
            if stops and back > len(stops) + 1:
                problems.append("Shift+Tab did not return to the start")
            report[label] = {"stops": [s["label"] for s in stops], "problems": problems}
            for p in problems:
                failures.append(f"keyboard {label}: {p}")
            ctx.close()
    return report


# ---------------------------------------------------------------------------
# Target size (WCAG 2.5.8 minimum; 44px comfortable)

TARGETS_JS = """
() => {
  const els = [...document.querySelectorAll('a[href], button, input, summary')].filter(e => e.offsetParent !== null);
  const rects = els.map(e => e.getBoundingClientRect());
  return els.map((e, i) => {
    const r = rects[i];
    // Inline links inside running text are exempt (2.5.8 "inline").
    const block = e.closest('p, li, dd, figcaption');
    const inline = getComputedStyle(e).display === 'inline' && block && block.textContent.trim().length > e.textContent.trim().length + 2;
    // Spacing exception: a 24px circle centred on the target touches no other target.
    const cx = r.left + r.width / 2, cy = r.top + r.height / 2;
    const clear = rects.every((o, j) => j === i || (Math.max(o.left - cx, 0, cx - o.right) ** 2 + Math.max(o.top - cy, 0, cy - o.bottom) ** 2) >= 144);
    return { label: (e.tagName.toLowerCase() + ' ' + (e.getAttribute('href') || e.textContent.trim().slice(0, 24))).trim(),
             w: Math.round(r.width), h: Math.round(r.height), inline, clear };
  });
}
"""


def target_sizes(browser, failures):
    report = {}
    for name, path in all_pages().items():
        for vp in ("mobile", "narrow", "desktop"):
            ctx = stable.new_context(browser, VIEWPORTS[vp])
            page = ctx.new_page()
            page.goto(url_for(name, path), wait_until="networkidle")
            stable.settle(page)
            rows = page.evaluate(TARGETS_JS)
            small = [r for r in rows if (r["w"] < 24 or r["h"] < 24) and not r["inline"] and not r["clear"]]
            under44 = [r for r in rows if (r["w"] < 44 or r["h"] < 44) and not r["inline"]]
            report[f"{name}/{vp}"] = {"targets": len(rows), "below24": small,
                                      "below44": [f"{r['label']} {r['w']}x{r['h']}" for r in under44]}
            for r in small:
                failures.append(f"target size {name}/{vp}: {r['label']} {r['w']}x{r['h']}")
            ctx.close()
    return report


# ---------------------------------------------------------------------------
# Zoom 200%, reflow and text spacing

CLIP_JS = """
() => {
  const doc = document.documentElement;
  const clipped = [...document.querySelectorAll('h1,h2,h3,p,li,a,span,dt,dd,label,button,summary,figcaption')]
    .filter(e => e.offsetParent !== null && e.textContent.trim() && !e.closest('pre, .artifact__viewport, .visually-hidden, .skip-link'))
    .filter(e => { const r = e.getBoundingClientRect(); return r.width > 0 && (r.right > innerWidth + 1 || r.left < -1); })
    .map(e => `${e.tagName.toLowerCase()}.${e.className}: ${e.textContent.trim().slice(0, 30)}`);
  // Text cut off inside its own box (overflow hidden with content larger than the box).
  const cut = [...document.querySelectorAll('body *')].filter(e => {
    if (e.offsetParent === null || e.closest('pre, .artifact__viewport, .visually-hidden, .project-card__visual, .stage, .project-hero__art')) return false;
    const s = getComputedStyle(e);
    // Deliberately visually hidden text (a 1px clipped box for screen readers).
    if (e.offsetWidth <= 1 && e.offsetHeight <= 1 && s.clip !== 'auto') return false;
    if (!/(hidden|clip)/.test(s.overflowX + s.overflowY)) return false;
    return e.scrollHeight > e.clientHeight + 2 || e.scrollWidth > e.clientWidth + 2;
  }).map(e => `${e.tagName.toLowerCase()}.${e.className}`);
  const nav = [...document.querySelectorAll('.site-nav__link, .site-nav__mark')].map(a => a.getBoundingClientRect());
  const navClipped = nav.some(r => r.right > innerWidth + 1 || r.left < -1);
  const overlap = nav.some((a, i) => nav.some((b, j) => i < j && a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom));
  return { overflow: doc.scrollWidth > doc.clientWidth, scrollWidth: doc.scrollWidth, clipped, cut, navClipped, navOverlap: overlap };
}
"""

TEXT_SPACING_CSS = """
* { line-height: 1.5 !important; letter-spacing: 0.12em !important; word-spacing: 0.16em !important; }
p { margin-bottom: 2em !important; }
"""


def reflow_checks(browser, failures):
    """200% zoom on a 1280px laptop is a 640 CSS-pixel viewport at device
    scale 2; 400% (the 320px reflow case) is the narrow viewport. Then the
    WCAG 1.4.12 text-spacing overrides at 320 and 1440."""
    report = {}
    cases = {
        "zoom200": ({"width": 640, "height": 400}, 2, None),
        "reflow320": ({"width": 320, "height": 256}, 4, None),
        "textSpacing320": (VIEWPORTS["narrow"], 1, TEXT_SPACING_CSS),
        "textSpacing1440": (VIEWPORTS["desktop"], 1, TEXT_SPACING_CSS),
    }
    os.makedirs(f"{OUT}/zoom", exist_ok=True)
    for case, (viewport, scale, css) in cases.items():
        for name, path in all_pages().items():
            ctx = stable.new_context(browser, viewport, device_scale_factor=scale)
            page = ctx.new_page()
            page.goto(url_for(name, path), wait_until="networkidle")
            if css:
                page.add_style_tag(content=css)
            stable.settle(page)
            info = page.evaluate(CLIP_JS)
            label = f"{case}/{name}"
            report[label] = info
            if info["overflow"] or info["clipped"] or info["navClipped"] or info["navOverlap"]:
                failures.append(f"reflow {label}: {info}")
            if info["cut"]:
                failures.append(f"reflow {label}: content cut off in {info['cut'][:5]}")
            if case == "zoom200" and name in ("home", "work", "black"):
                page.screenshot(path=f"{OUT}/zoom/{name}-zoom200-first-view.png")
            ctx.close()
    return report


# ---------------------------------------------------------------------------
# Motion: real behaviour, not the frozen capture mode

def motion_checks(browser, failures):
    report = {}
    for motion in ("no-preference", "reduce"):
        ctx = browser.new_context(viewport=VIEWPORTS["desktop"], reduced_motion=motion)
        for name, path in all_pages().items():
            page = ctx.new_page()
            page.goto(url_for(name, path), wait_until="networkidle")
            info = page.evaluate("""async () => {
              await new Promise(r => setTimeout(r, 300));
              const infinite = document.getAnimations().filter(a => a.effect && a.effect.getTiming().iterations === Infinity).length;
              const durations = [...document.querySelectorAll('body *')].map(e => getComputedStyle(e).transitionDuration)
                .filter(d => d && d !== '0s').length;
              const longest = Math.max(0, ...[...document.querySelectorAll('body *')].flatMap(e =>
                getComputedStyle(e).transitionDuration.split(',').map(d => parseFloat(d) * (d.includes('ms') ? 1 : 1000)))
                .filter(Number.isFinite));
              return { running: document.getAnimations().length, infinite, elementsWithTransitions: durations,
                       longestTransitionMs: longest, scrollBehavior: getComputedStyle(document.documentElement).scrollBehavior };
            }""")
            report[f"{motion}/{name}"] = info
            if info["infinite"]:
                failures.append(f"motion {motion}/{name}: {info['infinite']} perpetual animation(s)")
            if motion == "reduce" and (info["running"] or info["elementsWithTransitions"] or info["scrollBehavior"] != "auto"):
                failures.append(f"motion reduce/{name}: {info}")
            if motion == "no-preference" and info["longestTransitionMs"] > 400:
                failures.append(f"motion {name}: a transition lasts {info['longestTransitionMs']}ms")
            page.close()
        ctx.close()
    # The nav underline does animate by default (so the frozen capture mode
    # is genuinely what removes it from static captures).
    ctx = browser.new_context(viewport=VIEWPORTS["desktop"])
    page = ctx.new_page()
    page.goto(url_for("home", "/"), wait_until="networkidle")
    page.hover(".site-nav__link[href='/work/']")
    report["hoverTransitionRunning"] = page.evaluate("() => document.getAnimations().length")
    if not report["hoverTransitionRunning"]:
        failures.append("motion: hovering a nav link starts no transition by default")
    ctx.close()
    return report


# ---------------------------------------------------------------------------
# No-JavaScript: every page, nothing empty, every control has a destination

def no_js_checks(browser, failures):
    report = {}
    for name, path in all_pages().items():
        ctx = stable.new_context(browser, VIEWPORTS["mobile"], java_script_enabled=False)
        page = ctx.new_page()
        page.goto(url_for(name, path), wait_until="networkidle")
        info = page.evaluate("""() => ({
            visibleButtons: [...document.querySelectorAll('button')].filter(b => b.offsetParent !== null).length,
            visibleInputs: [...document.querySelectorAll('input')].filter(b => b.offsetParent !== null).length,
            emptyContainers: [...document.querySelectorAll('main section, main ul, main article')].filter(e => e.offsetParent !== null && !e.textContent.trim() && !e.querySelector('img')).map(e => e.className),
            links: document.querySelectorAll('a[href]').length,
            cards: document.querySelectorAll('.project-card').length,
        })""")
        report[name] = info
        if info["visibleButtons"] or info["visibleInputs"] or info["emptyContainers"]:
            failures.append(f"no-JavaScript {name}: {info}")
        ctx.close()
    return report


# ---------------------------------------------------------------------------
# Deterministic captures: the same capture twice must be byte-identical

STABLE_SHOTS = [
    ("home", "/", "desktop", None),
    ("home", "/", "mobile", None),
    ("work", "/work/", "desktop", None),
    ("work", "/work/", "mobile", None),
    ("black", "/work/black/", "desktop", None),
    ("black", "/work/black/", "mobile", None),
    ("brigid", "/work/brigid/", "desktop", None),
    ("lockdown", "/work/lockdown/", "desktop", None),
    ("about", "/about/", "desktop", ".about__body"),
    ("about", "/about/", "mobile", ".about__body"),
    ("contact", "/", "desktop", "#contact"),
    ("footer", "/about/", "desktop", ".site-footer"),
    ("footer", "/about/", "mobile", ".site-footer"),
    ("black-index-open", "/work/black/", "mobile", "open-index"),
    ("work-chip", "/work/", "desktop", "chip"),
    ("work-empty", "/work/", "desktop", "empty"),
]


def capture(browser, name, path, vp, target):
    ctx = stable.new_context(browser, VIEWPORTS[vp])
    page = ctx.new_page()
    page.goto(url_for(name, path), wait_until="networkidle")
    stable.settle(page)
    if target == "open-index":
        page.click(".project-nav__summary")
        stable.settle(page)
        png = page.locator(".project-nav").screenshot()
    elif target == "chip":
        page.focus("#work-search")
        page.keyboard.press("Tab")
        page.keyboard.press("Tab")
        page.keyboard.press("Space")
        stable.settle(page)
        png = page.locator("#work-filter").screenshot()
    elif target == "empty":
        page.fill("#work-search", "rust")
        page.click(".work-filter__chip[data-category='libraries-tooling']")
        stable.settle(page)
        png = page.locator(".work").screenshot()
    elif target:
        png = page.locator(target).first.screenshot()
    else:
        png = page.screenshot(full_page=False)
    ctx.close()
    return png


def determinism(browser, failures):
    os.makedirs(f"{OUT}/stable", exist_ok=True)
    report = {}
    for name, path, vp, target in STABLE_SHOTS:
        first = capture(browser, name, path, vp, target)
        second = capture(browser, name, path, vp, target)
        same = first == second
        fname = f"{name}-{vp}.png"
        with open(f"{OUT}/stable/{fname}", "wb") as fh:
            fh.write(first)
        report[fname] = {"identical": same, "sha256": hashlib.sha256(first).hexdigest()[:16]}
        if not same:
            a = np.asarray(Image.open(io.BytesIO(first)).convert("RGB")).astype(int)
            b = np.asarray(Image.open(io.BytesIO(second)).convert("RGB")).astype(int)
            report[fname]["differingPixels"] = int(np.any(a != b, axis=2).sum()) if a.shape == b.shape else "size differs"
            failures.append(f"determinism: {fname} differs between two captures ({report[fname]['differingPixels']})")
    return report


# ---------------------------------------------------------------------------

def summary(report, failures):
    lines = ["Phase 06 audit", "=" * 14, ""]
    axe = report["axe"]
    v = sorted({(x["id"], x["impact"]) for r in axe.values() for x in r["violations"]})
    inc = sorted({x["id"] for r in axe.values() for x in r["incomplete"]})
    lines.append(f"axe-core 4.10.2 ({', '.join(AXE_TAGS)}): {len(axe)} page/viewport scans")
    lines.append(f"  violations: {v or 'none'}")
    lines.append(f"  needs review (incomplete): {inc or 'none'}")
    lines.append("")
    lines.append("Lowest text contrast per page (worst = against the lightest 5% of background pixels):")
    for label, r in report["contrast"].items():
        low = r["lowest"][0] if r["lowest"] else None
        if low:
            lines.append(f"  {label:24} {low['worst']:5.2f} (need {low['need']}) {low['selector']} \"{low['text'][:28]}\"")
    lines.append(f"  gradient display text: {report['gradientText']}")
    lines.append("")
    lines.append("Lowest focus-indicator contrast per page:")
    for label, r in report["focusIndicator"].items():
        low = r["lowest"][0] if r["lowest"] else None
        if low:
            lines.append(f"  {label:24} {low['contrast']:5.2f} {low['element']}")
    lines.append("")
    lines.append("Keyboard walk stops per page:")
    for label, r in report["keyboard"].items():
        lines.append(f"  {label:24} {len(r['stops'])} stops, problems: {r['problems'] or 'none'}")
    lines.append("")
    lines.append("Targets under 44px (not inline):")
    for label, r in report["targets"].items():
        if r["below44"]:
            lines.append(f"  {label:24} {r['below44']}")
    lines.append("")
    lines.append(f"Deterministic captures: {sum(1 for r in report['determinism'].values() if r['identical'])}/{len(report['determinism'])} byte-identical")
    lines.append("")
    lines.append(f"failures: {len(failures)}")
    lines += [f"  - {f}" for f in failures]
    return "\n".join(lines) + "\n"


def main() -> int:
    os.makedirs(OUT, exist_ok=True)
    failures = []
    report = {}
    only = sys.argv[1:]
    with sync_playwright() as p:
        browser = p.chromium.launch()
        report["browser"] = browser.version
        steps = [
            ("axe", axe_scan), ("contrast", contrast_scan), ("focusIndicator", focus_indicator_scan),
            ("keyboard", keyboard_walk), ("targets", target_sizes), ("reflow", reflow_checks),
            ("motion", motion_checks), ("noJavaScript", no_js_checks), ("determinism", determinism),
        ]
        for key, fn in steps:
            if only and key not in only:
                continue
            report[key] = fn(browser, failures)
        if not only or "contrast" in only:
            report["gradientText"] = gradient_text_contrast(browser)
        browser.close()
    report["failures"] = failures
    with open(f"{OUT}/audit.json", "w") as fh:
        json.dump(report, fh, indent=2, default=str)
    if not only:
        text = summary(report, failures)
        with open(f"{OUT}/audit.txt", "w") as fh:
            fh.write(text)
        print(text)
    else:
        print(json.dumps({"steps": only, "failures": failures}, indent=2))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

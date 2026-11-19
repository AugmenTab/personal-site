"""Post-Phase 07 update 1: final navigation, permanent Writing index, Resume.

Checks two states, each at desktop, laptop, tablet, phone and narrow phone:

  real     (dist/ on :8080)         no articles, the owner's résumé: Writing
                                    leads to the "Coming soon." page; Resume
                                    opens content/resume.pdf in a new tab
  fixture  (.local/fixture-site on :8082)  a published fixture article and a
                                    fixture PDF: Writing lists the article;
                                    Resume sits between About and Contact and
                                    opens the PDF

For each: the visible nav order, every link inside the viewport with no
overlap and no page overflow, the Writing page, the Resume link, every
sitemap URL and every internal link (crawl). Header captures (deterministic
mode) go to design/proof/latest/phase-07-update1/.
"""
import json
import os
import sys
from urllib.parse import urljoin, urlparse

from playwright.sync_api import sync_playwright

import stable

OUT = "design/proof/latest/phase-07-update1"
SITES = {
    "real": os.environ.get("PREVIEW_URL", "http://preview/"),
    "fixture": os.environ.get("FIXTURE_URL", "http://fixture-preview/"),
}
EXPECTED = {
    "real": ["Home", "Work", "Writing", "About", "Resume", "Contact"],
    "fixture": ["Home", "Work", "Writing", "About", "Resume", "Contact"],
}
VIEWPORTS = {
    "desktop": {"width": 1440, "height": 900},
    "laptop": {"width": 1280, "height": 800},
    "tablet": {"width": 768, "height": 1024},
    "mobile": {"width": 390, "height": 844},
    "narrow": {"width": 320, "height": 640},
}

NAV_JS = """() => {
  const links = [...document.querySelectorAll('.site-nav__link')];
  const mark = document.querySelector('.site-nav__mark').getBoundingClientRect();
  const boxes = links.map(a => { const r = a.getBoundingClientRect();
    return { label: a.childNodes[0].textContent.trim(), href: a.getAttribute('href'),
             note: (a.querySelector('.visually-hidden') || {}).textContent || '',
             x: r.left, y: r.top, r: r.right, b: r.bottom, w: r.width, h: r.height,
             before: r.right <= mark.left + 1, after: r.left >= mark.right - 1 }; });
  const overlaps = [];
  for (let i = 0; i < boxes.length; i++) for (let j = i + 1; j < boxes.length; j++) {
    const a = boxes[i], b = boxes[j];
    if (a.x < b.r - 1 && b.x < a.r - 1 && a.y < b.b - 1 && b.y < a.b - 1) overlaps.push([a.label, b.label]);
  }
  return { boxes, overlaps,
           overflow: document.documentElement.scrollWidth > document.documentElement.clientWidth,
           outside: boxes.filter(b => b.x < 0 || b.r > innerWidth || b.h === 0).map(b => b.label),
           extended: document.body.classList.contains('page--nav-extended') };
}"""


def crawl(page, base, failures, label):
    seen, queue, checked = set(), ["/"], 0
    sitemap = page.request.get(urljoin(base, "/sitemap.xml"))
    import re
    for loc in re.findall(r"<loc>([^<]+)</loc>", sitemap.text()):
        path = urlparse(loc).path
        queue.append(path)
        status = page.request.get(urljoin(base, path)).status
        if status != 200:
            failures.append(f"{label}: sitemap {path} HTTP {status}")
    while queue:
        path = queue.pop()
        if path in seen:
            continue
        seen.add(path)
        r = page.request.get(urljoin(base, path))
        checked += 1
        if r.status != 200:
            failures.append(f"{label}: {path} HTTP {r.status}")
            continue
        if "text/html" not in r.headers.get("content-type", ""):
            continue
        for href in re.findall(r'href="([^"]+)"', r.text()):
            if href.startswith(("http:", "https:", "mailto:")):
                continue
            target = urlparse(urljoin(urljoin(base, path), href)).path
            if target not in seen:
                queue.append(target)
    return {"sitemap": sitemap.status, "pagesAndFilesChecked": checked}


def main() -> int:
    os.makedirs(OUT, exist_ok=True)
    failures, report = [], {}
    with sync_playwright() as p:
        browser = p.chromium.launch()
        for site, base in SITES.items():
            report[site] = {}
            for vp_name, viewport in VIEWPORTS.items():
                context = stable.new_context(browser, viewport)
                page = context.new_page()
                for path in ("/", "/writing/", "/about/"):
                    page.goto(urljoin(base, path), wait_until="networkidle")
                    stable.settle(page)
                    nav = page.evaluate(NAV_JS)
                    labels = [b["label"] for b in nav["boxes"]]
                    key = f"{vp_name} {path}"
                    report[site][key] = {"labels": labels, "extended": nav["extended"],
                                         "overlaps": nav["overlaps"], "outside": nav["outside"],
                                         "overflow": nav["overflow"]}
                    if labels != EXPECTED[site]:
                        failures.append(f"{site} {key}: nav order {labels}")
                    if nav["overlaps"] or nav["outside"] or nav["overflow"]:
                        failures.append(f"{site} {key}: overlaps {nav['overlaps']}, outside {nav['outside']}, overflow {nav['overflow']}")
                    if vp_name in ("desktop", "laptop", "tablet"):
                        sides = {b["label"]: ("left" if b["before"] else "right" if b["after"] else "?") for b in nav["boxes"]}
                        want = {l: ("left" if l in ("Home", "Work", "Writing") else "right") for l in EXPECTED[site]}
                        if sides != want:
                            failures.append(f"{site} {key}: monogram sides {sides}")
                    small = [f"{b['label']} {b['w']:.0f}x{b['h']:.0f}" for b in nav["boxes"] if b["w"] < 24 or b["h"] < 24]
                    if small:
                        failures.append(f"{site} {key}: targets under 24px {small}")
                    if path == "/":
                        page.screenshot(path=f"{OUT}/{site}-{vp_name}-header.png",
                                        clip={"x": 0, "y": 0, "width": viewport["width"], "height": min(viewport["height"], 420)})
                    if path == "/writing/" and vp_name in ("desktop", "mobile"):
                        page.screenshot(path=f"{OUT}/{site}-{vp_name}-writing.png", full_page=False)
                context.close()

            # The Writing page itself, and the Resume destination.
            context = stable.new_context(browser, VIEWPORTS["desktop"])
            page = context.new_page()
            page.goto(urljoin(base, "/writing/"), wait_until="networkidle")
            writing = page.evaluate("""() => ({
              h1: document.querySelector('main h1').textContent.trim(),
              empty: (document.querySelector('.writing__empty') || {}).textContent || null,
              items: [...document.querySelectorAll('.writing__item a')].map(a => a.getAttribute('href')),
              canonical: document.querySelector('link[rel=canonical]').href,
              current: document.querySelector('.site-nav__link[aria-current=page]').getAttribute('href') })""")
            report[site]["writingPage"] = writing
            if writing["h1"] != "Writing" or writing["canonical"] != "https://tylerbaum.dev/writing/" or writing["current"] != "/writing/":
                failures.append(f"{site}: writing page {writing}")
            if site == "real" and (writing["empty"] != "Coming soon." or writing["items"]):
                failures.append(f"real: expected the Coming soon state {writing}")
            if site == "fixture" and (writing["empty"] is not None or not writing["items"]):
                failures.append(f"fixture: expected the article list {writing}")
            for item in writing["items"]:
                r = page.request.get(urljoin(base, item))
                if r.status != 200:
                    failures.append(f"{site}: article {item} HTTP {r.status}")

            resume = page.evaluate("""() => [...document.querySelectorAll('.site-nav__link, .site-footer__link')]
              .filter(a => a.getAttribute('href') === '/resume.pdf')
              .map(a => ({ text: a.textContent.trim(), region: a.closest('footer') ? 'footer' : 'nav',
                             target: a.getAttribute('target'), rel: a.getAttribute('rel') }))""")
            report[site]["resumeLinks"] = resume
            if sorted(r["region"] for r in resume) != ["footer", "nav"] or any(r["text"] != "Resume (PDF, opens in a new tab)" or r["target"] != "_blank" or r["rel"] != "noopener noreferrer" for r in resume):
                failures.append(f"{site}: Resume links {resume}")
            r = page.request.get(urljoin(base, "/resume.pdf"))
            body = r.body()
            pdf = {"status": r.status, "type": r.headers.get("content-type"), "magic": body[:5].decode("latin-1"), "bytes": len(body)}
            with page.expect_download() as dl:
                page.evaluate("() => { const a = document.createElement('a'); a.href = '/resume.pdf'; a.download = ''; document.body.appendChild(a); a.click(); }")
            pdf["downloaded"] = os.path.getsize(dl.value.path())
            report[site]["resumePdf"] = pdf
            if pdf["status"] != 200 or pdf["type"] != "application/pdf" or pdf["magic"] != "%PDF-" or pdf["downloaded"] != pdf["bytes"]:
                failures.append(f"{site}: resume.pdf {pdf}")
            if site == "real" and os.path.isfile("content/resume.pdf") and pdf["bytes"] != os.path.getsize("content/resume.pdf"):
                failures.append(f"real: served resume.pdf differs from content/resume.pdf {pdf}")
            report[site]["links"] = crawl(page, base, failures, site)
            sitemap = page.request.get(urljoin(base, "/sitemap.xml")).text()
            report[site]["sitemapHasWriting"] = "https://tylerbaum.dev/writing/</loc>" in sitemap
            if not report[site]["sitemapHasWriting"] or "resume" in sitemap:
                failures.append(f"{site}: sitemap must list /writing/ and never the PDF")
            context.close()
        browser.close()

    report["failures"] = failures
    with open(f"{OUT}/nav-check.json", "w") as fh:
        json.dump(report, fh, indent=2)
    for site in SITES:
        print(f"{site}: writing {report[site]['writingPage']}")
        print(f"{site}: resume {report[site].get('resumePdf', report[site]['resumeLinks'])}; links {report[site]['links']}")
        for key, val in report[site].items():
            if isinstance(val, dict) and "labels" in val:
                stacked = val["extended"] and key.split()[0] in ("mobile", "narrow")  # the class only acts at <= 640px
                print(f"  {key:22} {' '.join(val['labels'])}{'  [stacked phone header]' if stacked else ''}")
    print("failures:", json.dumps(failures, indent=2))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

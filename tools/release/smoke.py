"""Release smoke tests against any base URL (Phase 07).

  smoke.py --url URL [--manifest FILE] [--headers FILE] [--origin ORIGIN]
           [--no-browser] [--wait SECONDS] [--out PREFIX]

URL is any deployment: the local Wrangler emulation (scripts/release.sh
dry-run), a workers.dev preview, or production. Nothing is hard-coded to
production. Checks:

  HTTP     every sitemap page, every packaged file (with --manifest) or every
           file the pages reference, content types, the 404 page and status,
           trailing-slash redirects without loops, security headers (exactly
           the packaged _headers with --headers), no immutable caching, and
           no source, marker or provider-file leakage
  HTML     titles, meta descriptions, canonical and og:url origins, internal
           links and fragments, the Contact anchor, every published project
           linked from Work
  Browser  (Playwright, if installed) navigation, Work search and filters,
           the compact project index, the no-JavaScript experience, desktop
           and phone widths, console errors and CSP violations

Exits 1 with a list of failures, 0 when every check passes.
"""

import argparse
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from html.parser import HTMLParser

CANONICAL_ORIGIN = "https://tylerbaum.dev"

CONTENT_TYPES = {
    ".html": ("text/html",),
    ".css": ("text/css",),
    ".js": ("text/javascript", "application/javascript"),
    ".svg": ("image/svg+xml",),
    ".webp": ("image/webp",),
    ".png": ("image/png",),
    ".woff2": ("font/woff2",),
    ".txt": ("text/plain",),
    ".xml": ("application/xml", "text/xml"),
    ".pdf": ("application/pdf",),
}

# Must never be served. Each must answer 404.
LEAK_PATHS = [
    "/.personal-site-output", "/_headers", "/_redirects", "/.git/HEAD", "/.env",
    "/README.md", "/wrangler.toml", "/package.json", "/release/_headers",
    "/content/projects/black/project.json", "/content/projects/black/body.md",
    "/content/settings.json", "/src/Site/Build.hs", "/dist/index.html",
    "/.release/evidence/release.json", "/SHA256SUMS", "/release.json",
    "/design/visual-direction.md", "/.local/", "/stack.yaml",
]
LEAK_MARKERS = ["/Users/", "/home/", "/stack-root", ".stack-work", "CLOUDFLARE_API_TOKEN"]

REQUIRED_HEADERS = {
    "content-security-policy": None,  # exact value checked with --headers
    "x-content-type-options": "nosniff",
    "referrer-policy": None,
    "x-frame-options": "DENY",
    "permissions-policy": None,
}


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


OPENER = urllib.request.build_opener(NoRedirect)


class Response:
    def __init__(self, status, headers, body):
        self.status = status
        self.headers = {k.lower(): v for k, v in headers.items()}
        self.body = body

    @property
    def text(self):
        return self.body.decode("utf-8", errors="replace")

    def header(self, name):
        return self.headers.get(name.lower(), "")


def fetch(base, path, method="GET"):
    url = urllib.parse.urljoin(base, path)
    req = urllib.request.Request(url, method=method, headers={"User-Agent": "release-smoke/1"})
    try:
        with OPENER.open(req, timeout=30) as r:
            return Response(r.status, dict(r.headers), r.read())
    except urllib.error.HTTPError as e:
        return Response(e.code, dict(e.headers or {}), e.read() if e.fp else b"")


class PageParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.title, self._in_title = "", False
        self.meta, self.links, self.ids, self.refs = {}, [], set(), []
        self.canonical = None

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if "id" in a:
            self.ids.add(a["id"])
        if tag == "title":
            self._in_title = True
        elif tag == "meta":
            key = a.get("name") or a.get("property")
            if key:
                self.meta[key] = a.get("content", "")
        elif tag == "link":
            if a.get("rel") == "canonical":
                self.canonical = a.get("href")
            elif a.get("href"):
                self.refs.append(a["href"])
        elif tag == "a" and a.get("href"):
            self.links.append(a["href"])
        elif tag in ("img", "script", "source") and a.get("src"):
            self.refs.append(a["src"])

    def handle_endtag(self, tag):
        if tag == "title":
            self._in_title = False

    def handle_data(self, data):
        if self._in_title:
            self.title += data


def parse(html):
    p = PageParser()
    p.feed(html)
    p.title = p.title.strip()
    return p


def wait_for(base, seconds):
    deadline = time.time() + seconds
    while True:
        try:
            fetch(base, "/")
            return
        except (urllib.error.URLError, ConnectionError, OSError):
            if time.time() > deadline:
                raise
            time.sleep(1)


def read_headers_file(path):
    """The header lines that apply to /* in a Cloudflare _headers file."""
    expected, active = {}, False
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            if not line.startswith((" ", "\t")):
                active = line.strip() == "/*"
                continue
            if active:
                name, _, value = line.strip().partition(":")
                expected[name.strip().lower()] = value.strip()
    return expected


def content_type_ok(path, response):
    ext = "." + path.rsplit(".", 1)[-1].lower() if "." in path.rsplit("/", 1)[-1] else ".html"
    allowed = CONTENT_TYPES.get(ext)
    ctype = response.header("content-type").split(";")[0].strip().lower()
    return allowed is None or ctype in allowed, ctype


def http_checks(base, args, failures, report):
    expected_headers = read_headers_file(args.headers) if args.headers else {}

    def check_headers(label, response):
        missing = []
        for name in sorted(set(REQUIRED_HEADERS) | set(expected_headers)):
            got = response.header(name)
            want = expected_headers.get(name) or REQUIRED_HEADERS.get(name)
            if not got:
                missing.append(name)
            elif want and got != want:
                failures.append(f"{label}: header {name} is {got!r}, expected {want!r}")
        if missing:
            failures.append(f"{label}: missing headers {', '.join(missing)}")
        csp = response.header("content-security-policy")
        if csp and ("unsafe-inline" in csp or "unsafe-eval" in csp or "default-src 'none'" not in csp):
            failures.append(f"{label}: CSP must deny by default and allow no unsafe-inline/unsafe-eval: {csp!r}")
        if "immutable" in response.header("cache-control").lower():
            failures.append(f"{label}: cache-control {response.header('cache-control')!r} is immutable (asset names are not versioned)")

    sitemap = fetch(base, "/sitemap.xml")
    if sitemap.status != 200:
        failures.append(f"/sitemap.xml: HTTP {sitemap.status}")
        return {}
    pages = []
    for loc in re.findall(r"<loc>([^<]+)</loc>", sitemap.text):
        parsed = urllib.parse.urlparse(loc)
        if f"{parsed.scheme}://{parsed.netloc}" != args.origin:
            failures.append(f"sitemap entry {loc} is not on {args.origin}")
        pages.append(parsed.path)
    report["sitemapPages"] = pages
    robots = fetch(base, "/robots.txt")
    if robots.status != 200 or f"Sitemap: {args.origin}/sitemap.xml" not in robots.text:
        failures.append(f"/robots.txt: HTTP {robots.status}, or it does not name {args.origin}/sitemap.xml")

    parsed_pages, files = {}, set()
    for path in pages:
        r = fetch(base, path)
        ok, ctype = content_type_ok(path, r)
        if r.status != 200 or not ok:
            failures.append(f"{path}: HTTP {r.status}, content-type {ctype}")
            continue
        check_headers(path, r)
        page = parse(r.text)
        parsed_pages[path] = page
        if not page.title:
            failures.append(f"{path}: empty <title>")
        if not page.meta.get("description"):
            failures.append(f"{path}: no meta description")
        if page.canonical != args.origin + path:
            failures.append(f"{path}: canonical {page.canonical!r}, expected {args.origin + path!r}")
        if page.meta.get("og:url") != args.origin + path:
            failures.append(f"{path}: og:url {page.meta.get('og:url')!r}")
        files.update(ref for ref in page.refs if ref.startswith("/"))
        for marker in LEAK_MARKERS:
            if marker in r.text:
                failures.append(f"{path}: contains {marker!r}")

    # Files: everything packaged (exact) or everything referenced.
    if args.manifest:
        with open(args.manifest, encoding="utf-8") as fh:
            manifest = [line.strip() for line in fh if line.strip()]
        for rel in manifest:
            if rel == "404.html":
                # Served for unknown paths (checked below). Requested by name,
                # html_handling redirects /404.html to /404, which is fine.
                continue
            if rel.endswith("index.html"):
                files.add("/" + rel[: -len("index.html")])
            else:
                files.add("/" + rel)
        html_pages = {"/" + rel[: -len("index.html")] for rel in manifest if rel.endswith("index.html")}
        unlisted = sorted(html_pages - set(pages))
        if unlisted:
            failures.append(f"pages packaged but not in the sitemap: {unlisted}")
    css_checked = set()
    for path in sorted(files - set(pages)):
        r = fetch(base, path)
        ok, ctype = content_type_ok(path, r)
        if r.status != 200 or not ok:
            failures.append(f"{path}: HTTP {r.status}, content-type {ctype}")
            continue
        check_headers(path, r)
        if path.endswith(".css") and path not in css_checked:
            css_checked.add(path)
            for ref in re.findall(r"url\(\s*['\"]?(/[^'\")\s]+)", r.text):
                rr = fetch(base, ref)
                if rr.status != 200:
                    failures.append(f"{path} references {ref}: HTTP {rr.status}")
    report["filesChecked"] = len(files - set(pages))

    # 404: a real status, the custom page, the same headers.
    missing = fetch(base, "/this-path-does-not-exist-phase07/")
    if missing.status != 404 or "Page not found" not in missing.text:
        failures.append(f"unknown URL: HTTP {missing.status}, custom page served: {'Page not found' in missing.text}")
    else:
        check_headers("404 response", missing)
    report["notFound"] = missing.status

    # Trailing slashes: one redirect to the canonical form, never a loop.
    redirects = {}
    for path, target in [("/work", "/work/"), ("/about", "/about/"), ("/work/black", "/work/black/"),
                         ("/index.html", "/"), ("/work/index.html", "/work/")]:
        hops, current = [], path
        for _ in range(5):
            r = fetch(base, current)
            if r.status in (301, 302, 307, 308):
                current = urllib.parse.urlparse(urllib.parse.urljoin(base + current, r.header("location"))).path
                hops.append((r.status, current))
                continue
            break
        redirects[path] = {"hops": hops, "final": r.status}
        if r.status != 200 or current != target or len(hops) > 1:
            failures.append(f"{path}: expected one redirect to {target}, got {hops} ending in HTTP {r.status}")
    report["redirects"] = redirects

    # Leakage: none of these may be served.
    leaks = {}
    for path in LEAK_PATHS:
        r = fetch(base, path)
        leaks[path] = r.status
        if r.status != 404:
            failures.append(f"{path}: HTTP {r.status} (must not be served)")
    report["leakProbes"] = leaks
    report["cacheControl"] = {p: fetch(base, p).header("cache-control") for p in ("/", "/assets/styles/site.css")}
    report["headersOnHome"] = {k: fetch(base, "/").header(k) for k in list(REQUIRED_HEADERS) + ["cross-origin-opener-policy", "cache-control", "etag"]}
    return parsed_pages


def html_checks(base, pages, failures, report):
    known = set(pages)
    for path, page in pages.items():
        for href in page.links:
            if href.startswith(("http://", "https://", "mailto:")):
                continue
            target, _, frag = urllib.parse.urljoin(path, href).partition("#")
            target = target or path
            if target in pages:
                if frag and frag not in pages[target].ids:
                    failures.append(f"{path}: link {href} has no #{frag} on {target}")
            elif target not in known:
                r = fetch(base, target)
                if r.status != 200:
                    failures.append(f"{path}: broken link {href} (HTTP {r.status})")
                known.add(target)
    home = pages.get("/")
    if not home or "contact" not in home.ids:
        failures.append("homepage: no #contact section")
    work = pages.get("/work/")
    projects = sorted(p for p in pages if re.fullmatch(r"/work/[a-z0-9-]+/", p))
    if work:
        unlinked = [p for p in projects if p not in work.links]
        if unlinked:
            failures.append(f"/work/ does not link to {unlinked}")
    report["projectPages"] = projects
    report["titles"] = {p: pg.title for p, pg in pages.items()}


CSP_LISTENER = """
window.__cspViolations = [];
document.addEventListener('securitypolicyviolation', e =>
  window.__cspViolations.push(e.violatedDirective + ' ' + (e.blockedURI || 'inline')));
"""


# Chrome logs this as a console error whenever COOP arrives over plain HTTP
# (the local emulation). It is expected there and impossible over HTTPS.
COOP_INSECURE = "The Cross-Origin-Opener-Policy header has been ignored, because the URL's origin was untrustworthy"


def browser_checks(base, pages, failures, report):
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        report["browser"] = "skipped: Playwright is not installed"
        return
    insecure = base.startswith("http://")

    def counts(message):
        return not (insecure and message.text.startswith(COOP_INSECURE))

    results = {}
    with sync_playwright() as p:
        browser = p.chromium.launch()
        for name, viewport in (("desktop", {"width": 1440, "height": 900}), ("mobile", {"width": 390, "height": 844})):
            context = browser.new_context(viewport=viewport)
            context.add_init_script(CSP_LISTENER)
            for path in pages:
                page = context.new_page()
                errors = []
                page.on("console", lambda m, e=errors: e.append(m.text) if m.type == "error" and counts(m) else None)
                page.on("pageerror", lambda exc, e=errors: e.append(str(exc)))
                page.goto(urllib.parse.urljoin(base, path), wait_until="networkidle")
                csp = page.evaluate("window.__cspViolations")
                overflow = page.evaluate("document.documentElement.scrollWidth > document.documentElement.clientWidth")
                results[f"{path} {name}"] = {"consoleErrors": errors, "csp": csp, "overflow": overflow}
                if errors or csp:
                    failures.append(f"browser {path} {name}: console errors {sorted(set(e[:200] for e in errors))}, "
                                    f"CSP violations {sorted(set(csp))}")
                if overflow:
                    failures.append(f"browser {path} {name}: horizontal overflow")
                page.close()

            page = context.new_page()
            page.goto(base, wait_until="networkidle")
            if name == "desktop":
                page.click(".site-nav a[href='/work/']")
                page.wait_for_load_state("networkidle")
                if urllib.parse.urlparse(page.url).path != "/work/":
                    failures.append(f"browser: nav Work led to {page.url}")
                visible = "() => [...document.querySelectorAll('li.work__item[data-search]')].filter(e => e.offsetParent !== null).length"
                total = page.evaluate(visible)
                page.fill("input[type='search']", "haskell")
                page.wait_for_timeout(300)
                searched = page.evaluate(visible)
                page.fill("input[type='search']", "")
                chips = page.locator(".work-filter__chip")
                chip_counts = []
                for i in range(1, chips.count()):
                    chips.nth(i).click()
                    page.wait_for_timeout(200)
                    chip_counts.append(page.evaluate(visible))
                results["workFilter"] = {"all": total, "search haskell": searched, "chips": chip_counts}
                if not (0 < searched < total) or not chip_counts or any(c < 1 or c > total for c in chip_counts):
                    failures.append(f"browser: Work search/filters did not narrow the list {results['workFilter']}")
            else:
                projects = [p for p in pages if re.fullmatch(r"/work/[a-z0-9-]+/", p)]
                if projects:
                    page.goto(urllib.parse.urljoin(base, projects[0]), wait_until="networkidle")
                    page.click(".project-nav__summary")
                    opened = page.evaluate("document.querySelector('.project-nav__index').open")
                    links = page.locator(".project-nav__index-list a").count()
                    results["compactIndex"] = {"page": projects[0], "opened": opened, "links": links}
                    if not opened or links < 1:
                        failures.append(f"browser: compact project index {results['compactIndex']}")
            page.close()
            context.close()

        context = browser.new_context(viewport={"width": 1440, "height": 900}, java_script_enabled=False)
        page = context.new_page()
        page.goto(urllib.parse.urljoin(base, "/work/"), wait_until="networkidle")
        cards = page.evaluate("[...document.querySelectorAll('li.work__item[data-search]')].filter(e => e.offsetParent !== null).length")
        controls = page.evaluate("[...document.querySelectorAll('.work-filter input, .work-filter button')].filter(e => e.offsetParent !== null).length")
        page.goto(base, wait_until="networkidle")
        sections = page.evaluate("[...document.querySelectorAll('main section[id]')].map(s => s.id)")
        results["noJavaScript"] = {"workCards": cards, "visibleControls": controls, "homeSections": sections}
        expected_cards = len([p for p in pages if re.fullmatch(r"/work/[a-z0-9-]+/", p)])
        if cards != expected_cards or controls or "contact" not in sections:
            failures.append(f"browser without JavaScript: {results['noJavaScript']}")
        context.close()
        browser.close()
    report["browser"] = results


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--url", required=True)
    parser.add_argument("--manifest")
    parser.add_argument("--headers")
    parser.add_argument("--origin", default=CANONICAL_ORIGIN)
    parser.add_argument("--no-browser", action="store_true")
    parser.add_argument("--wait", type=int, default=0)
    parser.add_argument("--out")
    args = parser.parse_args(argv)
    base = args.url if args.url.endswith("/") else args.url + "/"
    if not base.startswith(("http://", "https://")):
        print("smoke: --url must be an http(s) URL", file=sys.stderr)
        return 2

    failures, report = [], {"url": base, "origin": args.origin}
    try:
        if args.wait:
            wait_for(base, args.wait)
        pages = http_checks(base, args, failures, report)
        html_checks(base, pages, failures, report)
        if not args.no_browser:
            try:
                browser_checks(base, pages, failures, report)
            except Exception as err:  # noqa: BLE001 - any browser error is a smoke failure, not a crash
                failures.append(f"browser checks stopped: {type(err).__name__}: {str(err).splitlines()[0]}")
    except (urllib.error.URLError, OSError) as err:
        failures.append(f"cannot reach {base}: {err}")
    report["failures"] = failures

    lines = [f"Smoke test of {base} (canonical origin {args.origin})",
             f"  sitemap pages: {len(report.get('sitemapPages', []))}, other files: {report.get('filesChecked', 0)}",
             f"  404 status: {report.get('notFound')}",
             f"  redirects: {json.dumps(report.get('redirects', {}))}",
             f"  leak probes: {sum(1 for s in report.get('leakProbes', {}).values() if s == 404)}/{len(LEAK_PATHS)} answered 404",
             f"  headers on /: {json.dumps(report.get('headersOnHome', {}), indent=None)}",
             f"  browser: {'skipped' if args.no_browser else json.dumps({k: v for k, v in report.get('browser', {}).items() if k in ('workFilter', 'compactIndex', 'noJavaScript')}) if isinstance(report.get('browser'), dict) else report.get('browser')}"]
    lines += ["FAILED:"] + [f"  - {f}" for f in failures] if failures else ["PASS: every smoke check passed"]
    text = "\n".join(lines)
    print(text)
    if args.out:
        with open(args.out + ".json", "w", encoding="utf-8") as fh:
            json.dump(report, fh, indent=2)
        with open(args.out + ".txt", "w", encoding="utf-8") as fh:
            fh.write(text + "\n")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

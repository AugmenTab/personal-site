"""Phase 06: laboratory performance measurement.

Development tool only. Chromium (Playwright's pinned build) loads each page
from the static preview with Chrome DevTools Protocol throttling and reports
paint, layout-shift and long-task timings from the browser's own
PerformanceObserver entries, plus every network response.

    docker compose up -d preview
    docker compose --profile tools run --rm screenshots python3 tools/screenshots/perf.py [label] [runs]

Writes design/proof/latest/phase-06/perf-{label}.json and .txt.

These are LABORATORY numbers from one machine. They are not field data and
not Core Web Vitals; INP cannot be measured this way (no real interaction).
Lighthouse is not installed in the tools image (no Node); this script is the
documented, reproducible alternative. The throttling profile is DevTools
("applied") throttling, which is stricter on latency than Lighthouse's
simulated throttling, so the mobile numbers here are not Lighthouse scores.

Profiles:
  mobile   390x844 @2x, 4x CPU slowdown, 150 ms RTT, 1.6 Mbit/s down,
           750 kbit/s up (Lighthouse's "Slow 4G" figures)
  desktop  1440x900 @1x, no CPU slowdown, 40 ms RTT, 10 Mbit/s down

Each page is loaded cold (a fresh browser context: empty cache) and then
warm (reloaded in the same context: HTTP cache primed), N times each. The
report gives the median and the min/max of each metric.

The preview server (nginx, docker/preview.conf) does not compress responses
and sends no cache headers; text sizes are therefore uncompressed. Gzip
sizes are computed alongside for reference. A production host compresses.
"""

import gzip
import json
import os
import statistics
import sys
from urllib.parse import urljoin, urlparse

from playwright.sync_api import sync_playwright

BASE = os.environ.get("PREVIEW_URL", "http://localhost:8080/")
OUT = "design/proof/latest/phase-06"

PAGES = {
    "home": "/",
    "work": "/work/",
    "black": "/work/black/",
    "brigid": "/work/brigid/",
    "lockdown": "/work/lockdown/",
    "about": "/about/",
    "404": "/404.html",
}

PROFILES = {
    "mobile": {"viewport": {"width": 390, "height": 844}, "scale": 2, "cpu": 4,
               "latency": 150, "down": 1.6 * 1024 * 1024 / 8, "up": 750 * 1024 / 8},
    "desktop": {"viewport": {"width": 1440, "height": 900}, "scale": 1, "cpu": 1,
                "latency": 40, "down": 10 * 1024 * 1024 / 8, "up": 5 * 1024 * 1024 / 8},
}

OBSERVE_JS = """
window.__perf = { lcp: null, lcpElement: null, lcpUrl: null, cls: 0, shifts: [], longTasks: [] };
new PerformanceObserver(l => { for (const e of l.getEntries()) {
  window.__perf.lcp = e.startTime;
  const el = e.element;
  window.__perf.lcpElement = el ? el.tagName.toLowerCase() + (el.className ? '.' + String(el.className).split(' ')[0] : '') : null;
  window.__perf.lcpUrl = e.url || null;
} }).observe({ type: 'largest-contentful-paint', buffered: true });
new PerformanceObserver(l => { for (const e of l.getEntries()) if (!e.hadRecentInput) {
  window.__perf.cls += e.value;
  window.__perf.shifts.push({ value: e.value, t: e.startTime,
    sources: (e.sources || []).map(s => s.node ? (s.node.className || s.node.nodeName) : '?') });
} }).observe({ type: 'layout-shift', buffered: true });
new PerformanceObserver(l => { for (const e of l.getEntries()) window.__perf.longTasks.push({ start: e.startTime, duration: e.duration }); })
  .observe({ type: 'longtask', buffered: true });
"""

COLLECT_JS = """
async () => {
  // Let LCP and late shifts settle: two frames after the load event, then
  // a quiet second (LCP candidates stop at the first input; there is none).
  await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
  await new Promise(r => setTimeout(r, 1000));
  const nav = performance.getEntriesByType('navigation')[0];
  const fcp = performance.getEntriesByName('first-contentful-paint')[0];
  const p = window.__perf;
  const fcpTime = fcp ? fcp.startTime : 0;
  const tbt = p.longTasks.filter(t => t.start >= fcpTime).reduce((s, t) => s + Math.max(0, t.duration - 50), 0);
  const fontsReady = performance.now();
  return {
    ttfb: nav.responseStart, domContentLoaded: nav.domContentLoadedEventEnd, load: nav.loadEventEnd,
    fcp: fcp ? fcp.startTime : null, lcp: p.lcp, lcpElement: p.lcpElement, lcpUrl: p.lcpUrl,
    cls: p.cls, shifts: p.shifts, tbt, longTasks: p.longTasks.length,
    fontsLoaded: [...document.fonts].filter(f => f.status === 'loaded').map(f => `${f.family} ${f.weight} ${f.style}`),
    resources: performance.getEntriesByType('resource').map(r => ({
      url: r.name, type: r.initiatorType, start: Math.round(r.startTime), end: Math.round(r.responseEnd),
      transfer: r.transferSize, body: r.decodedBodySize, priority: r.fetchPriority || null,
      renderBlocking: r.renderBlockingStatus || null })),
    images: [...document.images].map(i => ({ src: i.currentSrc.replace(location.origin, ''), natural: [i.naturalWidth, i.naturalHeight],
      rendered: [Math.round(i.getBoundingClientRect().width * devicePixelRatio), Math.round(i.getBoundingClientRect().height * devicePixelRatio)],
      loading: i.loading, fetchpriority: i.getAttribute('fetchpriority'), decoding: i.decoding,
      dims: i.hasAttribute('width') && i.hasAttribute('height') })),
  };
}
"""


def throttle(page, profile):
    cdp = page.context.new_cdp_session(page)
    cdp.send("Network.enable")
    cdp.send("Network.emulateNetworkConditions", {
        "offline": False, "latency": profile["latency"],
        "downloadThroughput": profile["down"], "uploadThroughput": profile["up"]})
    cdp.send("Emulation.setCPUThrottlingRate", {"rate": profile["cpu"]})
    return cdp


def one_run(browser, url, profile):
    ctx = browser.new_context(viewport=profile["viewport"], device_scale_factor=profile["scale"])
    ctx.add_init_script(OBSERVE_JS)
    page = ctx.new_page()
    throttle(page, profile)
    page.goto(url, wait_until="load")
    cold = page.evaluate(COLLECT_JS)
    page.reload(wait_until="load")
    warm = page.evaluate(COLLECT_JS)
    ctx.close()
    return cold, warm


def med(values):
    vals = [v for v in values if v is not None]
    if not vals:
        return None
    return {"median": round(statistics.median(vals), 3), "min": round(min(vals), 3), "max": round(max(vals), 3)}


def summarise(runs):
    keys = ("ttfb", "fcp", "lcp", "load", "cls", "tbt")
    out = {k: med([r[k] for r in runs]) for k in keys}
    first = runs[0]
    out["lcpElement"] = sorted({str(r["lcpElement"]) for r in runs})
    out["lcpUrl"] = sorted({str(r["lcpUrl"]) for r in runs})
    out["requests"] = len(first["resources"]) + 1
    out["transferBytes"] = sum(r["transfer"] for r in first["resources"])
    out["bodyBytes"] = sum(r["body"] for r in first["resources"])
    by_type = {}
    for r in first["resources"]:
        kind = os.path.splitext(urlparse(r["url"]).path)[1] or r["type"]
        by_type.setdefault(kind, [0, 0])
        by_type[kind][0] += 1
        by_type[kind][1] += r["body"]
    out["byType"] = by_type
    out["shiftSources"] = sorted({s for r in runs for sh in r["shifts"] for s in sh["sources"]})
    return out


def gzip_sizes(browser):
    page = browser.new_page()
    sizes = {}
    for url in ("/", "/work/", "/work/black/", "/assets/styles/site.css", "/assets/scripts/work-filter.js"):
        body = page.request.get(urljoin(BASE, url)).body()
        sizes[url] = {"bytes": len(body), "gzip9": len(gzip.compress(body, 9))}
    page.close()
    return sizes


def main() -> int:
    label = sys.argv[1] if len(sys.argv) > 1 else "run"
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 5
    os.makedirs(OUT, exist_ok=True)
    report = {"label": label, "runs": n, "base": BASE, "profiles": PROFILES, "pages": {}}
    with sync_playwright() as p:
        browser = p.chromium.launch()
        report["browser"] = f"Chromium {browser.version} (Playwright 1.49.1, headless)"
        for name, path in PAGES.items():
            for prof_name, profile in PROFILES.items():
                colds, warms = [], []
                for _ in range(n):
                    cold, warm = one_run(browser, urljoin(BASE, path), profile)
                    colds.append(cold)
                    warms.append(warm)
                report["pages"][f"{name}/{prof_name}"] = {
                    "cold": summarise(colds), "warm": summarise(warms),
                    "images": colds[0]["images"], "fonts": colds[0]["fontsLoaded"],
                    "resources": colds[0]["resources"],
                }
        report["gzip"] = gzip_sizes(browser)
        browser.close()

    lines = [f"Performance ({label}): {report['browser']}, {n} cold + {n} warm runs per page/profile, medians [min-max]", ""]
    lines.append(f"{'page/profile':20} {'cache':5} {'FCP ms':>16} {'LCP ms':>18} {'CLS':>14} {'TBT ms':>12} {'req':>4} {'KiB':>7}  LCP element")
    for key, r in report["pages"].items():
        for cache in ("cold", "warm"):
            s = r[cache]

            def f(m, d=0):
                return "-" if m is None else f"{m['median']:.{d}f} [{m['min']:.{d}f}-{m['max']:.{d}f}]"
            lines.append(f"{key:20} {cache:5} {f(s['fcp']):>16} {f(s['lcp']):>18} {f(s['cls'], 3):>14} {f(s['tbt']):>12} {s['requests']:>4} {s['bodyBytes'] / 1024:7.1f}  {','.join(s['lcpElement'])}")
    lines.append("")
    lines.append(f"gzip reference sizes: {report['gzip']}")
    text = "\n".join(lines) + "\n"
    with open(f"{OUT}/perf-{label}.json", "w") as fh:
        json.dump(report, fh, indent=2)
    with open(f"{OUT}/perf-{label}.txt", "w") as fh:
        fh.write(text)
    print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())

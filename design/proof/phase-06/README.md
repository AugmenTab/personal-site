# Phase 06 evidence: accessibility, performance and visual stability

Date: 2026-11-17. Starting commit: `3e8dcc7` (Merge post-Phase 05 technical
remediation). Everything here was measured on the local preview (nginx,
`:8080`) and the fixture preview (`:8082`, Writing and Résumé fixtures)
with the pinned tools image: Playwright 1.49.1, Chromium 131.0.6778.33 and
axe-core 4.10.2. These are **lab measurements in headless Chromium**, not
field data, a human audit or a screen-reader session.

Files in this folder:

| File | What it is |
| --- | --- |
| `audit.txt` | Final `phase06.py` run: axe, measured contrast, focus indicators, keyboard walk, target sizes, determinism (0 failures) |
| `perf-before.txt` | Baseline performance, preview without compression (as it was before this phase) |
| `perf-before-gzip.txt` | Baseline code, preview with compression (the fair "before") |
| `perf-after-preload.txt` | Rejected experiment: font preloads |
| `perf-after.txt` | Final code |

Regenerate with the commands in the README section "Accessibility,
performance and deterministic captures". Fresh output goes to
`design/proof/latest/phase-06/`.

## 1. Accessibility report (WCAG 2.2 AA target)

### Method

- axe-core with the `wcag2a`, `wcag2aa`, `wcag21a`, `wcag21aa`, `wcag22aa`
  and `best-practice` tags. It scanned all 7 real pages and 3 fixture pages
  (Writing index, article, homepage with Writing) at 1440×900 and 390×844:
  20 scans in all.
- Text contrast measured from **rendered pixels**, not from CSS values.
  - Each text run's foreground colour is compared with the background
    pixels behind it, captured with the text made transparent.
  - That background includes the text-shadow halo. A second figure
    excludes the halo.
  - The reported value is the worst case: the background is taken at the
    95th-percentile lightness under the run.
  - Captures are viewport-sized slices at real scroll positions, because a
    full-page screenshot resizes the viewport and moves viewport-relative
    layout.
- Focus-indicator contrast: each focusable element is screenshotted focused
  and unfocused. The changed pixels must reach 3:1 against the unfocused
  pixels.
- Keyboard: Tab is pressed through every page at 1440, 390 and 320 px wide,
  checking for:
  - visible focus at every stop
  - no focus on hidden elements
  - no traps
  - a skip link first
  - DOM order matching visual order
- Reflow and zoom:
  - 320 px width with no horizontal scroll and no clipped text
  - 200% zoom at 1280 px (equivalent to 640 CSS px)
  - the WCAG 1.4.12 text-spacing override at 320 px and 1440 px
- Widths 320, 390, 768, 1280, 1440 and 1920 are covered by the
  `capture.py`, `phase05.py` and `phase06.py` suites together.
- Motion: transitions exist by default, are removed under
  `prefers-reduced-motion: reduce`, and nothing animates perpetually.
- No JavaScript: every page renders. The Work index shows every card and
  hides the filter controls. Every navigation path works.

### Findings and corrections

| # | Finding | Route(s) | Severity | Reproduction | Correction | Verification |
| --- | --- | --- | --- | --- | --- | --- |
| A1 | The Black pipeline diagram scrolls sideways on narrow screens but could not be reached by keyboard (axe `scrollable-region-focusable`; WCAG 2.1.1) | `/work/black/` ≤ 640 px | Serious (the only axe violation) | Load at 390 px wide and Tab past the diagram: it never takes focus, so arrow keys cannot scroll it | The viewport is focusable (`tabindex="0"`), with `role="group"` and the label "Diagram (scrolls sideways on narrow screens)" (`src/Site/Pages/Work.hs`). Image artifacts that do not scroll stay unfocusable | axe: no violations. Haskell test updated (`test/DossierTests.hs`). The keyboard walk reaches it and shows the focus ring |
| A2 | Small labels on raised panels measured below 4.5:1 | Project pages (code-language labels such as "haskell", the compact index's "N sections" count) | Moderate (WCAG 1.4.3) | Measured 4.27 to 4.43:1 against the raised-panel fill | New token `--text-faint-raised: #989181` (same hue, slightly lighter), used only on raised panels | 4.80:1 or better (`audit.txt`) |
| A3 | "Résumé" in the six-link phone header sat over the eclipse's brightest rays | Every page when a résumé or Writing is published (fixture site), ≤ 640 px | Serious when that header appears (WCAG 1.4.3). It does not occur on the real site today | Fixture preview at 390 px: measured 2.76:1 | In the six-link state only (`.page--nav-extended`), the hero plate starts at `7rem` instead of `5.5rem`, the same clearance as the approved four-link header, and the links get a darker text shadow. The four-link header and the homepage composition are unchanged | Worst text contrast on fixture pages is 4.88:1. The hero-band regression is still 0.00 |
| A4 | Phone nav links and "All projects" were below the 44 px comfortable target size (they already met the 24 px AA minimum, WCAG 2.5.8) | All pages ≤ 640 px; homepage | Minor (enhancement) | Element boxes measured 37 px high on phones | Invisible `::before` touch extensions (nav links extend 0.35 rem vertically; "All projects" 0.3 rem by 0.5 rem). Nothing moves visually | Every target is at least 24 px. Element boxes under 44 px are listed in `audit.txt`; see limitation L2 |
| A5 | The "All projects" arrow's hover moved it by animating `margin-left`, which triggers layout | Home, `/work/` links | Minor (polish) | Hover the link | `transform: translateX(0.2em)` instead, the same end position; `transform: none` under reduced motion | The motion check passes; captures differ only by sub-pixel rendering of the arrow (section 3) |

There were no other findings:

- **Keyboard:** no traps, no focus on hidden elements, and the skip link is
  first on every page.
- **Focus indicators:** at least 8.40:1 everywhere.
- **Reflow, zoom and text spacing:** no horizontal scroll and no clipped
  text.
- **Reduced motion:** honoured.
- **No-JavaScript paths:** all work.

### Contrast measurements (final)

Lowest text contrast per page (`audit.txt`): 4.80:1 to 4.88:1 against the
lightest 5% of the background, so every text run passes 4.5:1.

The hero name "Tyler Baum" is gradient display text. Its darkest gradient
stop measures 4.67:1 on the hero, against the 3:1 required for large text.

axe returns `color-contrast` as "needs review" rather than pass or fail,
because the grain texture overlay prevents it from computing a background.
The pixel measurement above is the answer to that review.

### Keyboard results

| Page | Stops (desktop / 390 px / 320 px) | Problems |
| --- | --- | --- |
| Home | 15 / 15 / 15 | none |
| Work | 17 / 17 / 17 | none |
| Black | 22 / 14 / 14 | none |
| Brigid | 20 / 13 / 13 | none |
| Lockdown | 15 / 11 / 11 | none |
| About | 10 / 10 / 10 | none |
| 404 | 10 / 10 / 10 | none |
| Fixture: home with Writing, Writing, article | 21, 14, 14 at every width | none |

On phones the dossier sidebar collapses into one disclosure, so phones have
fewer stops.

### Limitations

- **L1.** There has been no human screen-reader pass (VoiceOver, NVDA).
  - Landmarks, names, roles and heading structure are covered by axe and
    by the Haskell render tests.
  - Spoken output has not been checked.
- **L2.** Target sizes are measured on element boxes. The invisible
  `::before` extensions from A4 are not counted, so the sub-44 px list is
  conservative.
- **L3.** Only Chromium has been measured. Firefox and WebKit are not in
  the pinned image. The browser matrix in the README marks them "not
  verified".
- **L4.** Forced-colours / Windows High Contrast mode was not emulated.

## 2. Performance report

### Method (`tools/screenshots/perf.py`)

- **Browser:** headless Chromium 131 with Chrome DevTools Protocol (CDP)
  network and CPU throttling.
  - Mobile profile: 390×844 at device pixel ratio 2, "Slow 4G" (150 ms
    round trip, 1.6 Mbps down, 750 kbps up) and 4× CPU slowdown.
  - Desktop profile: 1440×900, unthrottled.
- **Runs:** 5 cold runs (new context, empty cache) and 5 warm runs (same
  context, reload) per page and profile. The tables show medians; the
  `.txt` files also give min and max.
- **Metrics:**
  - First Contentful Paint (FCP), from the Paint Timing API.
  - Largest Contentful Paint (LCP), with its element.
  - Cumulative Layout Shift (CLS): the sum of layout shifts not caused by
    user input.
  - Total Blocking Time (TBT): the sum of long-task time over 50 ms, from
    `PerformanceObserver`.
  - Request count and transferred size.
- **Server:** the measurements run against the local nginx preview, so
  network figures are lab figures and absolute numbers mean little.
  Compare the rows with each other.
- **Not measured:** INP is not measured (no field data and no scripted
  interactions). Lighthouse is not used.

### Before and after (cold medians)

| Page / profile | LCP before (no compression) | LCP before (compression) | LCP after | CLS before → after |
| --- | --- | --- | --- | --- |
| Home / mobile | 1582 ms | 952 ms | 969 ms | 0.005 → 0.005 |
| Home / desktop | 403 ms | 252 ms | 285 ms | 0.031 → 0.042 (range 0.031 to 0.053 in both) |
| Work / mobile | 936 ms | 520 ms | 545 ms | 0.001 → 0.001 |
| Black / mobile | 941 ms | 488 ms | 525 ms | 0.022 → 0.022 |
| About / mobile | 2089 ms | 1750 ms | 1754 ms | 0.003 → 0.003 |
| 404 / mobile | 800 ms | 457 ms | 482 ms | 0.004 → 0.004 |

TBT is 0 ms (median) on every page in every run.

What this shows, honestly:

1. **Compression is the only material improvement.**
   - The preview served the 86 KiB stylesheet uncompressed.
   - Adding gzip to `docker/preview.conf` (19 KiB compressed) cut throttled
     phone LCP by 35 to 50%.
   - This changes **only the local preview**. Production hosting compresses
     by default (Phase 07). The "before (compression)" column is therefore
     the fair baseline.
2. **The Phase 06 code changes are performance-neutral.**
   - "After" is within 0 to 40 ms of the fair baseline. Run-to-run spread
     is of that order.
   - The stylesheet grew by 1.5 KiB.
   - Nothing got measurably faster from the code changes, and this report
     does not claim otherwise.
3. **Font preloading was tried and rejected** (`perf-after-preload.txt`).
   - It cut desktop CLS from 0.031 to 0.022.
   - It made cold FCP and LCP on phones 150 to 200 ms worse, because the
     fonts compete with the stylesheet and the hero plate on a slow link.
4. **The About tree image (210 KiB WebP, already lossy at q78) is the
   heaviest LCP.**
   - It is a protected design element, and LCP (1.75 s on throttled
     mobile) is within the 2.5 s "good" threshold, so it was left alone.
5. **Every page is within the Core Web Vitals "good" thresholds in this
   lab setup:**
   - LCP ≤ 2.5 s
   - CLS ≤ 0.1
   - TBT ≈ 0 (the INP proxy)

### Owner note: Brigid and `<link rel="preload">`

Brigid 0.4 (pinned at `e0f4d45`) does not allow `Rel_Preload` on `<link>`.
The type checker rejects it, although preload is valid there in HTML. The
experiment above used `customAttribute` as a workaround and was then
reverted, so nothing in the site depends on this. It is a small upstream gap
worth fixing in Brigid.

## 3. Visual diff report

### Deterministic capture mode (`tools/screenshots/stable.py`)

Deterministic mode runs only in the test browser. Neither `assets/` nor
`dist/` changes. It does the following:

- Fixes the viewport, scale factor, locale, time zone and colour scheme.
- Injects a stylesheet that cuts every transition and animation to its end
  state.
- Turns off smooth scrolling and hides the text caret.
- Waits for fonts and decoded images, then two animation frames.

Pages with JavaScript disabled are detected synchronously and frozen
without awaiting the page. An unattended run once hung on that case. Real
motion is tested separately and never through this mode.

Result: **16 of 16 repeated captures are byte-identical** (`audit.txt`,
"Deterministic captures").

### Committed evidence compared with fresh captures (`tools/art/evidence_diff.py`)

43 identical, 22 different, 38 not regenerated (comparison sheets and
one-off records). All 22 differences are accounted for:

| Captures | Region | Cause | Kind |
| --- | --- | --- | --- |
| `phase-04/{black,brigid,lockdown}-mobile-first-view.png`, `phase-05/project/*-nav-collapsed.png` | The "N sections" count | A2 colour token | Intended |
| `phase-05/project/*-nav-expanded.png`, `phase-05/project/black-mobile-first-view.png` | Chevron and count | A2. The old capture also caught the chevron mid-rotation (it showed `›` on a closed index; closed is `⌄`) | Intended, plus old capture noise |
| `phase-05/fixture/nav-mobile.png`, `nav-narrow.png`, `home-writing-preview-mobile.png` | Six-link phone header and hero below it | A3 (plate offset and link shadow, six-link state only) | Intended |
| `desktop.png`, `keyboard-focus-card.png` | 142×11 px at the "All projects →" link | A5 (the arrow is now an inline-block that moves by `transform`; sub-pixel glyph placement) | Intended |
| `phase-05/work/work-filter-category.png`, `work-no-results.png` | Filter chips | The old captures were taken mid-transition (noted in the remediation review) | Old capture noise |
| `keyboard-focus.png` | 4×55 px, no visible change | Not reproducible in deterministic captures; attributed to the old capture's timing | Old capture noise |

These 22 files were refreshed from `latest/` in this commit, following
`design/proof/README.md`.

**Not changed:**

- The regression baseline `design/regression/desktop-1440x900.png`.
- The homepage hero band. `regression.py --hero-band` reports mean |dL|
  0.00 and worst tile 0.00: PASS.
- No hero art, monogram, typography, homepage hierarchy, dossier layout,
  work card, footer, About tree or copy was redesigned or rewritten.
- The "About & Contact" hero call to action is untouched.

## 4. Browser test matrix

| Browser | Engine | Verified how | Status |
| --- | --- | --- | --- |
| Chromium 131 (desktop and mobile emulation) | Blink | Every suite in this phase | Verified |
| Chrome / Edge current | Blink | Same engine as above | Expected; not separately run |
| Firefox | Gecko | Not in the pinned tools image | Not verified |
| Safari macOS / iOS | WebKit | Not in the pinned tools image | Not verified |

The site uses no engine-specific features beyond standard CSS (custom
properties, `clamp()`, `:focus-visible`, `details`/`summary`) and one ES
module. Before a public launch, a manual pass in Safari and Firefox is
recommended.

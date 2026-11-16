# Phase 05 evidence

Captured 2026-11-16 by `tools/screenshots/capture.py` (which calls
`phase05.py`) against the real site (`dist/`, preview on :8080) and the
fixture site (`.local/fixture-site/`, :8082). Full machine-readable results:
[`checks.json`](checks.json) here and [`../checks.txt`](../checks.txt)
(all phases). **Result: `failures: []`.**

## Index

| Folder | What |
| --- | --- |
| `home/` | Homepage first view, desktop and mobile (the full pages, with the new Contact section and footer, are in `../phase-03/home-*-full.png`, refreshed by this run) |
| `work/` | Work index full pages at 1920, 1440, 1280, 768, 390 and 320; search (`haskell`), category filter, no results, keyboard-selected chip (first views); no-JavaScript full page |
| `project/` | Desktop first views (sidebar, all three hero-less dossiers); compact index collapsed and expanded at 768, 390 and 320 (Black for every width, Brigid and Lockdown at 390); Black mobile first view |
| `contact/` | `/#contact` reached from a project page; the homepage Contact section at 1440, 390 and 320 |
| `footer/` | Footer on About at every width, and on the homepage (no contact column) |
| `about/` | About full page and the emblem composition, desktop and mobile |
| `pages/` | Home, Work, About and Black at 320px (every page is checked at 1920, 1280 and 320; only the narrowest is kept) |
| `fixture/` | Writing index and article (full pages), the homepage's Writing preview, the six-link navigation at every width, the footer with Writing and Résumé. **Fixture content only** (a labelled article and PDF that are never published) |

## What the browser checks assert

- Every page at 1920, 1440, 1280, 768, 390 and 320: no horizontal overflow,
  images load, fragments resolve, no console or HTTP errors. At 1920,
  1280 and 320, no text element extends past the viewport (this catches
  text clipped inside overflow-hidden boxes, which page-overflow checks
  miss; it was added after the hero's disciplines and the teaser's
  code-bar label were found clipped at 320px and fixed).
- Crawl: every internal link and asset answers 200; 34 fragment links
  resolve. A no-JavaScript walk follows the nav, the cards, All projects,
  About's "Get in touch", the hero's two CTAs, Contact and the footer.
- Work: 2 columns at 1100px and wider, 1 below. Gaps of at least 24px,
  equal card heights per row. Search by name, description, technology and
  topic (case and whitespace ignored); category chips; combined filters;
  empty state and reset (focus returns to the field); a chip operated with
  the keyboard shows a focus ring; focus leaves a card that a filter hides;
  cumulative layout shift 0.001. Without JavaScript: 3 cards, no controls.
- Project pages: desktop sidebar sticky and unchanged. At 900px and below:
  All projects plus a collapsed "On this page" (under 110px tall), opening
  does not scroll the page, every link reaches its section, and the
  keyboard order is back link, summary (Enter opens it), then the links.
- Contact: from a project page lands on `/#contact` in view, with no fixed
  or sticky UI over it; on the homepage, no reload. One control per
  destination.
- Footer: no images, no overflow, text at least 11px, every link resolves.
- Discovery: every sitemap URL is served; robots.txt names the sitemap;
  the canonical URL is the production URL.
- Fixture: the six-link nav has no overflow or overlap at any width;
  `/resume.pdf` is a PDF; the draft article answers 404 and is not in the
  sitemap.

## Visual regression

`regression.py --hero-band`: mean 0.00, worst tile 0.00: **PASS** (the
approved hero is unchanged). The whole first view reads 3.97, the same
pre-existing Phase 03 teaser difference recorded in Phase 04.

## Command evidence

- `stack test`: **210/210** (169 at the Phase 04 baseline; 41 new Phase 05
  tests).
- `site check`: OK, 7 pages and 29 files (now including
  `assets/scripts/work-filter.js`, `robots.txt` and `sitemap.xml`).
- Determinism: two independent builds are identical (`diff -r`: no output).
- Negative CLI runs (`tools/art/negative_cases.py`, `site check --root …`):

```text
legacy-category      field "category": invalid value "Haskell library"; expected one of: programming-languages, libraries-tooling, ai-automation, simulation-games, creative-technology (categories are a controlled vocabulary; see README "Taxonomy")
unknown-topic        field "topics": [1]: unknown topic "type-sytems"; expected one of: type-systems, …
duplicate-topic      field "topics": lists "game-engines" more than once
misfiled-technology  field "technologies": "Type systems" is the topic "type-systems"; list it under "topics"
duplicate-technology field "technologies": lists "haskell" more than once (ignoring case)
resume-not-pdf       content/resume.pdf: is not a PDF (it does not start with %PDF-)
missing-script       required asset(s) missing from the source tree: assets/scripts/work-filter.js
```

  A build from `resume-not-pdf` over existing output fails and leaves that
  output byte-identical.

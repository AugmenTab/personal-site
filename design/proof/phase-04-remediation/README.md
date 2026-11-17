# Phase 04 layout remediation: evidence

All hero captures here show the **development stand-in test card**, which is
labelled as such in the image. They are never project art. The stand-in was
built from a throwaway copy of the sources in `.local/hero-preview/` (README
"Previewing a hero"). The repository's `content/` never contained it, and no
committed page has a hero.

> **Pruned 2026-11-16 (post-Phase 05 remediation).** The full-page and
> tablet captures named below (for example `black-desktop-full.png`) were
> removed from the working tree; first views, hero close-ups, the focus
> capture, both comparison sheets and every `checks.json` remain. The full
> set is in Git history at tag `evidence-archive-2026-11-16`:
> `git show evidence-archive-2026-11-16:design/proof/phase-04-remediation/right-focus/black-desktop-full.png > black-desktop-full.png`.
> See [`../README.md`](../README.md).

## Comparisons

| File | Shows |
| --- | --- |
| `compare-desktop.png` | Before: the Phase 04 full-width hero with the sidebar below it. After: the hero in the main column with the sidebar beside it. Then the approved project render, for structure only (its compiler panel is not built) |
| `compare-mobile.png` | Before and after at 390×844 |

## Stand-in cases (each with `checks.json`, 0 failures)

| Directory | Hero metadata | Shows |
| --- | --- | --- |
| `right-focus/` | `focus: { desktop: {x: 80, y: 35}, mobile: {x: 90, y: 20} }` | Right-shifted focus. Desktop and tablet crop at `80% 35%`, phone at `90% 20%` (asserted from computed `object-position`). Desktop: the first view shows the global navigation, the sidebar and the hero together. `black-desktop-full.png` shows the sidebar column beside the whole dossier and the wide exhibit (pipeline diagram) below the hero. Tablet and phone full pages: no horizontal overflow |
| `centred-long-title/` | no `focus` (the default, centre); title "Blackwater Interstitial Compilation Laboratory" and a long summary | Default focus `50% 50%`. Long text wraps inside the hero at every width, and the first section still starts within the first desktop screen |

The no-hero fallback is the real site: `../phase-04/{black,brigid,lockdown}-*`
and `../pages/project-*`, recaptured for this remediation. The header opens
the main column beside the sidebar. Below 900px the order is header,
section index, dossier.

## What the browser checks assert

From `tools/screenshots/phase04.py`, run on every real project page by
`capture.py` (`../checks.txt`, `failures: []`) and on each preview by
`hero_check.py`:

- the opening, sidebar and body are all children of the article;
- above 900px, the sidebar starts beside the opening (within 40px of its top),
  in its own column, and is sticky;
- at 900px and below, the opening, sidebar and body are stacked in that order;
- the hero is in the dossier's column (above 640px), or edge to edge (phones);
- the hero image is loaded and not focusable; the title and summary are
  inside the hero and not clipped;
- the computed `object-position` equals the configured focus for the
  viewport;
- on desktop, the first section starts within the first screen;
- there is no horizontal overflow, and every sidebar link has a target
  (also clicked with JavaScript disabled, at every viewport);
- every dossier link takes a visible focus ring;
- there are no console errors and no HTTP errors.

## CLI evidence (size policy and invalid focus, via the preview tree)

```text
$ hero_preview.py black --stand-in --grain --focus 80,35            # 1095026-byte WebP
$ site check --root .local/hero-preview
warning: content/projects/black/project.json: field "hero": image "hero.webp" is 1.04 MiB (1095026 bytes), over the 1.00 MiB (1048576 bytes) budget (accepted up to 8.00 MiB (8388608 bytes))
OK: 7 pages and 27 files validated; nothing written.

$ hero_preview.py black --stand-in --grain --format png             # 6727252-byte PNG
$ site build --root .local/hero-preview --out .local/hero-preview/html
warning: content/projects/black/project.json: field "hero": image "hero.png" is 6.42 MiB (6727252 bytes), over the 1.00 MiB (1048576 bytes) budget (accepted up to 8.00 MiB (8388608 bytes))
Wrote 7 pages (50720 bytes of HTML) and 27 assets and media files to .local/hero-preview/html/.

$ hero_preview.py black --stand-in --grain --format png --canvas 3200,1600   # 12776775 bytes
$ site build --root .local/hero-preview --out .local/hero-preview/html
Build failed: invalid content:
content/projects/black/project.json:
  field "hero": image "hero.png" is 12.18 MiB (12776775 bytes); the ceiling is 8.00 MiB (8388608 bytes) (budget 1.00 MiB (1048576 bytes)). Re-export it from the source PNG with tools/art/promote_hero.py

$ hero_preview.py black --stand-in --focus 62,135
$ site check --root .local/hero-preview
Build failed: invalid content:
content/projects/black/project.json:
  field "hero": field "focus": field "desktop": field "x": must be a multiple of 5 (e.g. 60 or 65), got 62 field "y": must be from 0 to 100, got 135
```

## Repository checks (final state)

```text
$ docker compose run --rm site-build stack test
All 169 tests passed            (161 at baseline 6d70ae8, tag phase-04-remediation-baseline; +8 net)
$ docker compose run --rm site-build stack exec -- site check
OK: 7 pages and 26 files validated; nothing written.
$ docker compose run --rm site-build
Wrote 7 pages (50629 bytes of HTML) and 26 assets and media files to dist/.
$ docker compose --profile tools run --rm screenshots
"failures": []
$ docker compose --profile tools run --rm art python3 tools/art/regression.py --hero-band
mean |dL| = 0.00 (limit 1.5)   worst tile = 0.00 (limit 12.0)   PASS
```

The homepage captures (`../desktop*.png`, `../tablet*.png`,
`../mobile*.png`, `../phase-03/*`) were regenerated byte-identical to Phase
04. `../keyboard-focus.png` varies by a few bytes from run to run (focus
transition timing), so the committed copy was kept.

# Design proof: what is kept, and why

This folder holds **curated, frozen** visual evidence. No tool writes here
during a normal run: every screenshot and comparison tool writes into
[`latest/`](latest/), which Git ignores. Committed files change only when
someone deliberately copies a reviewed capture in.

Classification and pruning were done on 2026-11-16 (post-Phase 05 technical
remediation). Tracked files went from about 237 MiB to about 81 MiB.

## Classes

| Class | Where | Rule |
| --- | --- | --- |
| 1. Authoritative references | `design/references/` (approved homepage render 02, approved project render 03, monogram sources, Eclipsing Eden brand boards and style guide), `design/monogram*.svg`, `design/visual-direction.md` | Never removed or replaced |
| 2. Active regression baselines | `design/regression/desktop-1440x900.png` (the accepted Phase 00 baseline that `regression.py` reads), `design/regression/desktop-1440-full.png` | Never removed; replaced only after the owner approves a visual change |
| 3. Current review evidence (curated) | This folder: the Phase 00 design-gate record (below), `phase-03/` comparison sheets and its `before/` captures, `phase-04/` first views and focus captures plus the `stand-in-hero/` record, `phase-04-remediation/` sheets, first views, hero close-ups and `checks.json`, `phase-05/` README, `checks.json` and the targeted captures, `phase-06/` (accessibility, performance and visual-diff reports with their text evidence), `phase-07/` (release package hashes, dry-run, smoke and guardrail-test evidence) | Kept; refreshed only deliberately |
| 4. Historical intermediate captures | Full pages, every layout close-up, tablet variants and the `pages/` folder from Phases 03 to 05 | Removed from the working tree; kept in Git history at tag `evidence-archive-2026-11-16` |
| 5. Regenerable evidence | Everything the capture suite writes | Written to `latest/` (git-ignored) on every run |

### The Phase 00 design-gate record (kept in this folder's root)

Cited by [`DESIGN_GATE.md`](../../DESIGN_GATE.md) and
[`comparison.md`](comparison.md): `compare/` (registered comparison against
the approved render), `desktop.png`, `desktop-first-view.png`,
`tablet-first-view.png`, `mobile-first-view.png`, `about-section*.png`,
`branding-nav-divider.png`, `hero-mask.png`, `hero-cleaned.png`,
`keyboard-focus*.png`, `reduced-motion.png`, `no-javascript.png`,
`monogram-*.png`, `regression-diff-hero-band.png`, and the text evidence
(`checks.txt`, `build-evidence.txt`, `content-evidence.txt`,
`test-results.txt`). The homepage captures were last refreshed by the
Phase 05 run, before this folder was frozen.

## Regenerating evidence

```sh
docker compose run --rm site-build                    # dist/
docker compose up -d preview                          # :8080
docker compose --profile tools run --rm screenshots   # every capture and browser check -> design/proof/latest/
docker compose --profile tools run --rm art python3 tools/art/regression.py --hero-band
docker compose --profile tools run --rm art python3 tools/art/evidence_diff.py
```

The Phase 05 Writing and Résumé checks also need the fixture site (README,
"Screenshots"). `evidence_diff.py` compares each committed screenshot with
its fresh counterpart in `latest/` pixel by pixel. Until Phase 06 a few
captures of animated controls (the compact index's caret, the Work filter
chips) differed by a few pixels between runs because the screenshot landed
mid-transition. The capture tools now use the deterministic capture mode
(`tools/screenshots/stable.py`), so fresh captures repeat exactly. A
committed capture taken before Phase 06 can still show the old
mid-transition state; that is the old capture, not a regression.

To refresh curated evidence after an approved change, copy the specific
files from `latest/` to the same relative path here and commit them with
the change that caused them. Do not copy whole folders.

## Recovering archived files

Nothing was rewritten: removed files remain in Git history, so cloning the
repository is not yet any smaller. Only the working tree is. To restore one:

```sh
git show evidence-archive-2026-11-16:design/proof/pages/work-desktop.png > work-desktop.png
git ls-tree -r --name-only evidence-archive-2026-11-16 design/proof   # list everything archived
```

The tag points at `91205ea` (Merge Phase 05), which is on `main` at GitHub.
The tag itself must be pushed (`git push origin evidence-archive-2026-11-16`)
to be visible there.

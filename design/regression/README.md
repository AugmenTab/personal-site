# Visual regression reference

These captures are the **owner-approved Phase 00 homepage** (gate approved
2026-11-14). Treat them as the visual baseline for later phases. Any
intentional change to the hero, header or teaser should be reviewed against
them, and the reference should be replaced only with explicit owner
approval.

| File | What |
| --- | --- |
| `desktop-1440x900.png` | First view at the authoritative 1440×900 viewport. This is the comparison target |
| `desktop-1440-full.png` | Full page at 1440 wide, for context |

Both were captured in Chromium (Playwright 1.49.1) at device scale 1 by
`tools/screenshots/capture.py`, against the static preview.

## Checking for regressions

```sh
docker compose run --rm site-build
docker compose up -d preview
docker compose --profile tools run --rm screenshots
docker compose --profile tools run --rm art python3 tools/art/regression.py
```

`regression.py` compares `design/proof/desktop-first-view.png` with
`desktop-1440x900.png`. It reports two values:

- the mean absolute luminance difference (limit 1.5/255);
- the worst 32×32 tile (limit 12/255), which catches local breakage that a
  whole-frame mean would hide.

It also writes `design/proof/regression-diff.png`. A failure means "look at
the diff". Content changes that the owner has approved are expected to fail
it; refresh the reference only after that approval.

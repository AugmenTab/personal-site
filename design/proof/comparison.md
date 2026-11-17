# Visual comparison against the approved second render (remediation 2)

## Method

- **Reference.** The **full-resolution** approved render from the reference
  kit (`.local/kit/01_approved_visuals/homepage-render-02.png`, 1586×992),
  resized to the authoritative 1440×900.
- **Proof.** A Chromium capture of the live Brigid page at 1440×900.
- **Registration.** None is needed: the page's artwork is drawn at the same
  scale and origin as the render.
- **Regeneration.** `docker compose --profile tools run --rm art python3 tools/art/compare.py`
  (after the screenshots service).

## Evidence

| # | Evidence | File |
| --- | --- | --- |
| 1 | Approved reference at 1440×900 | `compare/01-reference-1440x900.png` |
| 2 | Revised browser screenshot at 1440×900 | `compare/02-proof-1440x900.png` (= `desktop-first-view.png`) |
| 3 | Registered 50% opacity overlay | `compare/03-overlay-50.png` |
| 4 | Absolute difference (×3) | `compare/04-difference.png` |
| 5 | Left architecture | `compare/05-arch-left.png` |
| 6 | Right architecture | `compare/06-arch-right.png` |
| 7 | Left / right cloud banks | `compare/07-clouds-left.png`, `compare/07-clouds-right.png` |
| 8 | Eclipse and corona | `compare/08-eclipse.png` |
| 9 | Grayscale luminance comparison | `compare/09-luminance.png` |
| 10 | Desktop, tablet and mobile captures | `desktop.png`, `desktop-first-view.png`, `tablet-first-view.png`, `mobile-first-view.png` (the tablet and mobile full pages were pruned on 2026-11-16; they are at tag `evidence-archive-2026-11-16`, and `design/proof/latest/` has fresh ones after a capture run) |
| 11 | About section with the tree emblem | `about-section.png` (1440), `about-section-mobile.png` (390) |
| 12 | Nav monogram and the divider beneath the name | `branding-nav-divider.png` |
| — | What was removed from the render, and the cleaned artwork | `hero-mask.png` (magenta = inpainted text/UI, blue = synthesised panel area), `hero-cleaned.png` |
| — | Numeric support | `compare/metrics.md` |
| — | Interaction states | `keyboard-focus.png`, `keyboard-focus-card.png`, `reduced-motion.png`, `no-javascript.png`, `checks.txt` |

## Numbers

Mean absolute luminance difference, on a 0–255 scale. Full table in
`compare/metrics.md`.

**Artwork-only regions** (no text or controls on either side)

| Region | Difference |
| --- | --- |
| Both architecture clusters beside the hero text | 2.1 |
| Both architecture clusters beside the teaser panel | 4.2–4.5 |
| Both cloud banks | 2.0–2.3 |
| Corona band above the name | 12.5 |

- **Beside the panel:** the extra difference is the stage's bottom fade and
  the page grain, which fades back in there.
- **Corona band:** the box includes the medallion's lower edge and the area
  inpainted under the render's medallion.

**Whole-frame regions**, which include intentional content differences:

| Region | Difference |
| --- | --- |
| Full frame | 14.9 |
| Hero text band | 19.0 |
| CTA band and teaser | 19.6 |

These are not fidelity scores for the artwork. Per the brief, the numbers
support the visual judgment below; they do not replace it.

## Discrepancy register

### Fixed (compared with remediation 1)

| Item | Status |
| --- | --- |
| Buildings differed significantly from the reference | **Fixed.** Both clusters are now the render's own buildings, at the render's position and scale: silhouettes, setbacks, arches, edge light, recesses and materials. The overlay shows no ghosting, and the luminance maps match. |
| Clouds lacked volume, form, lighting and shadow | **Fixed.** These are the render's cloud banks, with their silhouettes, crimson highlights and near-black undersides. |
| Hero was too evenly exposed | **Fixed.** The render's shadow structure is used directly (see `09-luminance.png`). |
| Clean, geometric, uniformly lit surfaces | **Fixed.** The procedural painter and its assets are removed. |
| Eclipse | **Matches.** It is the render's disc, corona, rays, arcs and darkened lower half, at its size and position. |
| Second monogram beneath the name | **Fixed.** It is replaced by an Art Deco rule: tapering hairlines, gold bars, and a gold diamond with a blood-red core. The footer monogram was also removed. The monogram now appears **only** in the nav medallion; this is enforced by a smoke test and a browser check. |
| Tree emblem | **Added** to the About section: the standalone tree-and-eclipse, without the wordmark, beside the biography. |
| Name size and position | **Registered** to the render's name band: cap height about 52 px, spanning x ≈ 460–975 at 1440. |
| Header geometry | **Registered:** labels on y ≈ 22, rule on y ≈ 41, and a 60 px medallion centred on y ≈ 30, as in the render. |

### Deliberate differences (functionality and information architecture)

| Difference | Reason |
| --- | --- |
| The Black teaser is static: no Compile/Run/Examples controls and no "Compiled successfully … 5.0" | The PRD forbids a homepage compiler and fabricated output. |
| Two hero CTAs between the disciplines and the panel | The Phase 00 handoff requires them. The teaser therefore starts at about 425 px instead of 355 px. |
| Four nav items (no Writing or Résumé) | There is no content for them yet, and the PRD forbids dead links. |
| Real monogram in the medallion, instead of the render's stand-in glyph | It is the owner's personal signature. |
| "Software Engineer" role line above the name | A grounded role line is required. |
| One Selected Work card (Brigid) with accurate copy | Phase 00 scope. The render's Brigid description is inaccurate. |

### Remaining visual mismatches

| Item | Detail |
| --- | --- |
| Area under the render's panel | The render never shows what is behind its Black panel. That region is synthesised: each column fades from its last visible colour into dark ground. It is visible only as a 70–80 px band behind the CTAs, and as narrow slivers beside the teaser frame, where the building bases fade into darkness rather than continuing. |
| Name typeface | Cinzel is close to, but not the same as, the render's engraved serif. The render's letters are slightly narrower and more condensed. |
| Teaser frame | The teaser keeps the site's 9-slice stepped frame, which is lighter than the render's heavy bevelled gold frame. There is also no bottom-centre diamond. |
| Medallion area | The corona under the medallion is reconstructed by interpolating around the eclipse centre. It is always covered by the medallion, so it is never visible. |

### Technical limitations

| Limitation | Effect |
| --- | --- |
| Source resolution: the render is 1586 px wide | It is shown at 1:1 or below up to 1586 px viewports. Wider screens upscale it, to about 1.2× at 1920. On 2× displays the artwork is about half the device resolution: correct, but softer than the HTML text. A higher-resolution master of the same render would drop straight into the same slots. |
| No per-building alpha | The plates are cut as three overlapping strips with feathered seams, not as isolated buildings. At ≥1100 px they reproduce the render exactly. Below 1100 px the composition is **centre-cropped** at 1100 px scale: the eclipse, the clouds and the inner edges of the architecture stay visible, and the outer towers leave the viewport. Sliding the side plates further inward would cover the eclipse with their opaque sky. |
| Not reproducible from the repository | The reconstruction reads the owner's full-resolution render from the git-ignored kit. The finished plates are committed source assets, so the site build stays reproducible. The brief allows this. |

### Deferred beyond Phase 00

- A higher-resolution master of the approved render, for crisp 2× and
  ultra-wide display.
- Hand-separated building layers with true alpha. This would allow a
  recomposed phone layout that keeps the towers in view.
- Optional parallax (reduced-motion safe) using those layers.

## Responsive behaviour

- **≥1100 px.** The three plates tile back into the render exactly, at
  viewport width.
- **768 px.** A centre crop at 1100 px scale: the eclipse, clouds and the
  inner edges of both clusters. The role line moves down into the dark disc.
- **390 px.** The same crop. The plates start below the two-row nav with a
  feathered edge. CSS corner fans replace the render's fans, which are off
  screen.
- **No overflow** at any width (checked automatically).

## Interaction states

- **Focus.** The focus order is unchanged and has no traps. The teaser and
  the tree emblem have no focusable elements.
- **Reduced motion.** No animations run at all; the check counts zero
  `document.getAnimations()`. Scrolling is instant.
- **No JavaScript.** The page is identical; it ships no script.

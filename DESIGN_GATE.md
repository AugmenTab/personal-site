# Phase 00 Design Gate — Repo + Dockerized Haskell + Visual Proof

**Status: GATE PASSED. Approved by the owner on 2026-11-14, after visual
remediation 2.**

| Area | Status |
| --- | --- |
| Technical foundation | Approved |
| Monogram | Approved; the geometry is frozen for Phase 00 |
| Hero (reconstructed from the approved render) | Approved |
| Branding (nav-only monogram, divider under the name, tree emblem in About) | Approved |

```text
Phase: 00 — Repo + Dockerized Haskell + Visual Proof (visual remediation 2)
Status: gate passed (owner approval 2026-11-14)
Git branch/commit: main (the Phase 00 commit)
```

### Approval record

- **Approver and date.** The owner approved the remediation 2 evidence
  as-is on 2026-11-14, and asked for it to be merged to `main` and pushed.
- **Visual regression baseline.** The approved desktop page is preserved in
  `design/regression/`:
  - `desktop-1440x900.png` is the comparison target;
  - `desktop-1440-full.png` is the full page.

  `tools/art/regression.py` compares a fresh capture against the baseline
  and reports the mean and worst-tile luminance difference. A fresh capture
  of the approved build matched the reference exactly (0.00).
- **Carried open.** These items do not block approval and carry into Phase 01
  (§8):
  - the draft copy, including the Black teaser's copy and excerpt;
  - the contact details and résumé;
  - the remaining visual mismatches and technical limitations in R2.5;
  - the decision on keeping proof PNGs in the repository.
- **Next phase.** Phase 01 may now be planned. It has **not** been started,
  and will begin only when the owner asks.

The brief (`phase-00_update2.md`) refers to a supporting document, "PERSONAL
SITE — PHASE 00 VISUAL REMEDIATION 2". **That document was not in the
reference kit or `.local/plans/`**, so this work follows `phase-00_update2.md`
alone.

## R2. Remediation 2

### R2.1 What was rejected

- **Hero.** It was still visually unacceptable:
  - the architecture differed from the reference;
  - the clouds lacked volume and shadow;
  - the exposure was too even;
  - the surfaces were clean and geometric.
- **Monogram.** It was accepted, but repeated beneath the name.

### R2.2 Change of production strategy

As the brief requires, the procedural approach was abandoned.

**Removed:**
- `tools/art/paint.py`;
- `hero-sky.jpg` and `hero-arch-{left,right}.webp`.

**New pipeline:** `tools/art/reconstruct.py` reconstructs the hero from the
owner's **full-resolution approved render**. The brief permits use of the
owner's reference pixels.

1. **Remove everything the page draws itself in real HTML/CSS.** That is the
   nav labels and underline, the nav rule and its diamonds, the medallion,
   the name, the divider, the thesis, the disciplines, the Black panel and
   the Selected Work rule.
   - **Thin text** is found by absolute local contrast inside known boxes,
     dilated to catch its shadows, and filled by Telea inpainting. Synthetic
     grain matched to the render is added back.
   - **The medallion's footprint** is filled by interpolating around the
     eclipse centre, because the rays are radial.
   - **The region the render's panel hid** is synthesised: each column fades
     from its last visible colour into dark ground.
   - `design/proof/hero-mask.png` shows exactly what was removed.
     `hero-cleaned.png` is the result.
2. **Cut the cleaned 1586×800 artwork** into three overlapping, feathered
   plates: `hero-plate-{left,centre,right}.webp`, 116 KB in total.

**Text stays real HTML.** The navigation, heading, thesis, disciplines, CTAs
and teaser are all real HTML on top of the plates. The page is never a
flattened screenshot.

**Layout:**
- **≥1100 px.** The plates tile back into the render exactly, at viewport
  width. The header and hero text are registered to the render's own
  positions at 1440×900:
  - nav labels on y ≈ 22 and the rule on y ≈ 41;
  - a 60 px medallion;
  - the name's cap band on the render's name band;
  - the thesis and disciplines on the render's lines.
- **<1100 px.** The composition keeps its 1100 px scale and is centre-cropped.

**Grain.** The stage sits above the page-wide grain, so the reconstructed art
(which carries the render's own grain) is shown exactly as rendered. The
grain fades back in at the bottom of the stage, so there is no texture seam.

The ambient "breath" animation was removed. It would have pulsed against the
plate seams.

### R2.3 Branding corrections

- **Monogram.** The geometry is frozen and untouched.
  - It now appears **only in the navigation medallion**.
  - The monogram under the name is replaced by an Art Deco rule: tapering
    hairlines, short gold bars, and a gold diamond with a blood-red core.
  - The footer monogram is replaced by a small diamond-and-rule ornament.
  - This is enforced by a smoke test (one monogram reference in the HTML) and
    a browser check (the only monogram image is inside `nav`).
- **Tree-and-eclipse emblem.**
  - **Source:** `tools/art/emblem.py` takes the standalone emblem from the
    branding board `f42612e0…`: ring, eclipse, tree, skyline, gate and base
    rule. It excludes the ECLIPSING EDEN wordmark and the board border.
  - **Edge:** the board's ground is made transparent, so the emblem melts
    into the page.
  - **Placement:** it is shown in **About**, beside the biography (two
    columns on desktop, stacked on narrow screens), with a faint warm halo
    and a hairline separating it from the text.
  - **Restraint:** it appears once. It is decorative (`alt=""`,
    `aria-hidden`), lazy-loaded, and absent from the hero and nav.
  - **Test:** a smoke test checks that it is in the About section.

### R2.4 Verification (Pass E)

All evidence is in `design/proof/`. The full list and the **discrepancy
register** are in `design/proof/comparison.md`.

- **Evidence.**
  - Items 1–9: the reference and proof at 1440×900, the 50% overlay, the
    difference map, the left and right architecture, both cloud banks, the
    eclipse, and the luminance pair, all in `compare/`.
  - Items 10–12: the desktop, tablet and mobile captures; `about-section*.png`;
    and `branding-nav-divider.png`.
- **Artwork-only difference.** The mean absolute luminance difference from
  the render is **2.0–2.3 / 255** for both architecture clusters beside the
  hero and both cloud banks. Beside the panel it is 4.2–4.5, because of the
  bottom fade and grain. The overlay shows no ghosting of any building, cloud
  or arc.
- **Full frame.** The difference is 14.9, driven by the intentional content
  differences listed below.

### R2.5 Fixed / deliberate / remaining / limitations / deferred

**Fixed:**
- **Architecture:** both clusters now match the reference in massing,
  silhouettes, setbacks, arches, perspective, lighting and materials.
- **Clouds:** the reference's form, volume, crimson highlights and
  near-black undersides.
- **Shadow structure:** cinematic, the reference's own.
- **Eclipse:** faithful.
- **Monogram:** no longer repeated; nav only.
- **Tree emblem:** added to About.
- **Name and header geometry:** registered to the reference.

**Deliberate (functionality, not visual mismatch):**
- The static Black teaser: no controls, no fabricated output.
- Two hero CTAs; as a result the teaser starts about 70 px lower than the
  render's panel.
- Four nav items.
- The real monogram in the medallion.
- The role line.
- One accurate Selected Work card.

**Remaining visual mismatches:**
- **The area under the render's panel** is synthesised, because the render
  never shows it. It is visible only as about 75 px behind the CTAs and as
  slivers beside the teaser frame, where the building bases and the lower
  right cloud fade into darkness rather than continuing.
- **Cinzel** is slightly wider than the render's engraved serif.
- **The teaser frame** is lighter than the render's bevelled frame, with no
  bottom diamond.

**Technical limitations:**
- **Resolution.** The source render is 1586 px wide, so the art is soft on 2×
  screens and slightly upscaled above 1586 px viewports.
- **Plate seams.** The plates are strips, not per-building cut-outs, so
  narrow screens get a centre crop: the outer towers leave the viewport
  below 1100 px.
- **Reproducibility.** The pipeline reads the git-ignored kit, so it is not
  reproducible from the repository alone. Its outputs are committed, and the
  site build remains deterministic.

**Deferred beyond Phase 00:**
- a higher-resolution master render;
- hand-separated building layers, enabling a recomposed phone layout and
  optional parallax;
- the font substitution decision, if the owner wants a closer engraved face.

## R1. Remediation 1 (superseded)

Remediation 1 rebuilt the monogram from the first gold adaptation; that
geometry is now provisionally accepted and frozen. It also replaced the SVG
hero with procedurally painted raster plates. The owner rejected those
plates, and they are removed in R2. The monogram evidence remains in
`design/proof/monogram-comparison*.png`, `monogram-overlay.png` and
`design/monogram-review.md`.

## 1. What is in the tree

| Area | Files |
| --- | --- |
| Toolchain | `Dockerfile`, `compose.yaml`, `docker/entrypoint.sh`, `docker/build-site.sh`, `.dockerignore`, `.gitignore` |
| Haskell package | `stack.yaml`, `stack.yaml.lock`, `package.yaml` (+ generated `personal-site.cabal`) |
| Generator (proof only) | `app/Main.hs`, `src/Site/Assets.hs`, `src/Site/Proof.hs`, `src/Site/Build.hs` |
| Smoke tests | `test/Spec.hs` (13 tests) |
| Design system | `assets/styles/site.css`, `assets/fonts/*` (+ OFL licences) |
| Artwork | `assets/images/hero-plate-{left,centre,right}.webp` (reconstructed from the approved render), `about-tree.webp` (branding emblem), SVG `black-emblem.svg`, `card-brigid.svg`, `ornament-{corner,rule,frame}.svg`, `texture-grain.svg` |
| Monogram (frozen) | `design/monogram.svg`, `assets/brand/monogram-simple.svg`, `monogram-ornate.svg`, `favicon.svg` |
| Design docs | `design/visual-direction.md`, `design/monogram-review.md`, `design/proof/comparison.md` |
| Evidence | `design/proof/*.png`, `design/proof/compare/*`, `design/proof/checks.txt` |
| Dev tooling | `tools/Dockerfile`; `tools/screenshots/capture.py`; `tools/art/` (`reconstruct.py`, `emblem.py`, `compare.py`, `crop.py`, plus the monogram tools `overlay.py`, `profile.py`, `monogram_sheet.py`) |

## 2. Pinned toolchain

| Item | Pin |
| --- | --- |
| Image | `ghcr.io/flipstone/haskell-tools:debian-ghc-9.10.3-1e1d10c` @ `sha256:7cd1e197eb25e86dc0878ad1572ea5d2675c565226c3a199f5570d4b55c9e5ad` |
| GHC / Stack | 9.10.3 / 3.7.1 |
| Resolver | `lts-24.12` + `stack.yaml.lock` |
| Brigid | `AugmenTab/brigid@9344bfb561d5a9637f691ac7e734186667df4a61`, `brigid` package only |
| System packages | `libphonenumber-dev`, `libprotobuf-dev` (required by Brigid's core) |
| Dev tools image | Playwright 1.49.1 image + `playwright==1.49.1`, `numpy==2.1.3`, `scipy==1.14.1`, `pillow==11.0.0`, `opencv-python-headless==4.10.0.84` (OpenCV is **new in R2**, for inpainting) |

## 3. Commands and actual results (remediation 2)

macOS (Apple silicon), Docker 29.4.0, Compose v5.1.2. No host GHC, Stack or
Cabal was used.

| Command | Result |
| --- | --- |
| `docker compose run --rm site-build stack test` | exit 0: **All 13 tests passed** |
| `docker compose run --rm site-build` (twice, unchanged) | exit 0: `Wrote dist/index.html (6787 bytes) and 23 assets.` `index.html` SHA-256 `c84f231b…` and `site.css` `328085c1…` were identical across both builds. `dist/` is about 0.55 MB |
| `docker compose --profile tools run --rm screenshots` | exit 0, `"failures": []` at all three widths. Checks: no overflow; no broken anchors; all images loaded; no HTTP or console errors; the monogram only in the nav; zero running animations under reduced motion |
| `docker compose --profile tools run --rm art python3 tools/art/reconstruct.py` / `emblem.py` / `compare.py` | exit 0; outputs listed above |

**Smoke tests (13).** The earlier 11, adjusted, plus two new ones:

- **Adjusted:** the missing-asset test now deletes
  `images/hero-plate-centre.webp`.
- **New:** "the monogram appears only in the navigation medallion".
- **New:** "the About section carries the tree emblem".

**Earlier Phase 00 results**, with the infrastructure unchanged since:
- the cold clean-checkout build took 456 s;
- a warm rebuild took 1.5 s;
- the missing-asset build exits 1 with a clean message and leaves no output;
- Linux ownership was simulated.

## 4. Generated-file ownership

Unchanged:
- **macOS:** files are host-owned.
- **Linux:** the entrypoint drops to the repository owner's UID. This was
  simulated with UID 1234; a native Linux host has not been tested.
- **Tools:** the development tools chown their outputs to the bind-mount
  owner.

## 5. Accessibility and responsiveness

- **Real HTML.** All text and controls are real HTML.
- **Heading outline:** `h1 Tyler Baum → h2 Black → h2 Selected Work → h3
  Brigid → h2 About → h3 Contact`.
- **Decorative art.** The decorative images (plates, tree, emblem) are
  `alt=""` inside `aria-hidden` containers.
- **Keyboard order:**
  - Skip link → nav → CTAs → Brigid source → GitHub.
  - It has no traps.
  - The focus ring is visible (`keyboard-focus*.png`).
- **No horizontal overflow** at 1440, 768 or 390.
- **Reduced motion.** Nothing animates.
- **No JavaScript.** The page ships none.

## 6. New dependencies and why

| Dependency | Why |
| --- | --- |
| `opencv-python-headless==4.10.0.84` (dev tools image only) | Telea inpainting to remove text and UI from the render. It is not part of the site build and not shipped |

There are no new Haskell dependencies. There is no JavaScript, framework,
server or database.

## 7. Known limitations (non-visual)

- **Draft copy** needs owner review: the thesis, role line, disciplines,
  About text, and the Black description, differentiators and excerpt (not
  verified against Black).
- **Contact** has only GitHub.
- **Proof evidence** is about 29 MB of PNG.
- **Native Linux host** not tested.

## 8. Owner decisions

**Resolved at approval (2026-11-14):**
- The hero is approved.
- The tree in About is approved.
- The divider under the name is approved.
- The work is committed and pushed to `main`.

**Still open (carried into Phase 01):**
1. **Optionally, a higher-resolution master** of the approved render, to
   remove the 2× softness.
2. **Black teaser:** verified copy and excerpt.
3. **Contact details** and the résumé PDF.
4. **Proof PNGs:** whether to keep them in the repository long term.

**Phase 01 begins only when the owner asks.**

# Visual direction — Phase 00

Dark Art Deco noir. The opening is dramatic and everything after it is calmer.
The site borrows the *Eclipsing Eden* brand's style and ornament. It does not
use the setting's subjects.

## Reference provenance

Everything in `design/references/` is a non-production reference. It is never
copied to `dist/`. The files were curated from the owner-supplied Phase 00
kit (`portfolio-phase00-reference-kit.zip`, kept in the git-ignored `.local/`)
and downscaled to JPEG so the repository stays small.

| File | Source in kit | Role |
| --- | --- | --- |
| `homepage-render-02.jpg` | `01_approved_visuals/homepage-render-02.png` | **Authoritative homepage composition** (approved second render) |
| `project-render-03.jpg` | `01_approved_visuals/project-render-03.png` (owner-corrected) | Dossier continuity for Phase 01+ only; not implemented here |
| `monogram-original-handwritten.png` | `02_monogram/original-handwritten.png` | Monogram letterform relationships and crossing topology (precedence 2 since remediation 1) |
| `monogram-first-gold-adaptation.jpg` | `02_monogram/first-gold-adaptation.png` | **Primary monogram visual target** (precedence 1 since remediation 1) |
| `brand-boards/color-palette.jpg` | `source_boards/679c1c17…` | Palette values |
| `brand-boards/typography-direction.jpg` | `source_boards/29646e3f…` | Sharp engraved display serif with Deco geometry |
| `brand-boards/ornament-system.jpg` | `source_boards/9b0e056d…` | Dividers, corners, cartouches, textures |
| `brand-boards/corner-ornaments.jpg` | `source_boards/9d212681…461` | Corner vocabulary (the "B. Art-Deco" fan is used) |
| `brand-boards/cartouche-frame.jpg` | `source_boards/946ab278…` | Cartouche and medallion framing |
| `brand-boards/emblem-eclipse-architecture.jpg` | `source_boards/81bfa298…` | Eclipse over stepped architecture |
| `brand-boards/eclipse-ring-skyline.jpg` | `source_boards/f42612e0…` | Eclipse with sunburst, great ring, distant skyline |
| `eclipsing-eden-style-guide.md` | `03_eclipsing_eden_branding/style-guide.md` | Rendering and colour principles |

The kit's other boards were deliberately left out: the bullet emblem, the
apple-and-serpent emblem, the overgrown garden gate, and the parchment and map
"corner in context" sheet. Each leans on a prop or setting subject. The kit
contained no playable-race art.

**Addition in remediation 2.** The tree-and-eclipse emblem board
(`source_boards/f42612e0…`) is approved by the owner as a personal symbol,
because *Baum* means tree. Only the standalone emblem is used; the wordmark
and border are excluded.

## Hero artwork: reconstructed from the approved render

The approved second render is the **visual specification**, not inspiration
(remediation 2). Two earlier approaches were rejected: procedural SVG in
Phase 00, and procedurally painted raster in remediation 1. The hero
artwork is now the render's own, reconstructed for a live page.

`tools/art/reconstruct.py` works from the full-resolution kit render. It
removes everything the page draws itself:
- the nav, its rule and the medallion;
- the name, divider, thesis and disciplines;
- the Black panel and the Selected Work rule.

Thin text is inpainted with grain matched to the render. The medallion's
footprint is interpolated around the eclipse centre, because the rays are
radial. The region the panel hid is synthesised as columns fading into dark
ground.

The script then cuts the 1586×800 artwork into three overlapping, feathered
plates, which together ship 116 KB:

| Plate | Render x-range |
| --- | --- |
| `hero-plate-left.webp` | 0–640 |
| `hero-plate-centre.webp` | 470–1116 |
| `hero-plate-right.webp` | 946–1586 |

**How the plates are placed:**
- **≥1100 px.** The plates tile back into the render exactly. The header
  and hero text are registered to the render's positions at 1440×900.
- **<1100 px.** The composition keeps 1100 px scale and is centre-cropped.
- **Grain.** The stage sits above the page grain (the render carries its
  own), and the grain fades back in at the stage's foot.

Text and controls remain real HTML; the page is never a flattened
screenshot. SVG is kept for ornament, frames, the monogram and the card line
art.

**Evidence:**
- `design/proof/hero-mask.png` shows what was removed.
- `design/proof/compare/` holds the registered comparisons.

## Adopted motifs

- **Eclipse, clouds, architecture.** Exactly as in the approved render:
  - an oxblood disc with a gold-white upper corona, fine rays and great arcs;
  - blood-lit cumulus banks either side;
  - two distinct, monumental, rim-lit Art Deco clusters with arched
    gateways, running off the page edges.
- **Sharp engraved serif.** Cinzel for display, set in tracked capitals.
- **Aged-gold linework.** Hairline rules, diamond terminals, Deco corner fans,
  stepped-corner frames (`ornament-frame.svg` as a 9-slice border image) and
  chamfered cartouche buttons.
  - Beneath the name: a rule of tapering hairlines, short gold bars, and a
    diamond with a blood-red core.
- **Restrained accents.** Blood for the primary call to action and the
  current-page underline. Verdigris for project status.
- **Bone/parchment text** on void.
- **Texture.** One light warm grain over the page body.

## Branding hierarchy

| Element | Role | Where |
| --- | --- | --- |
| **Monogram** | Personal signature | The navigation medallion **only** (and the favicon). It is not repeated under the name or in the footer. |
| **Tree-and-eclipse emblem** | Symbolic emblem | The About section, once, beside the biography. Never in the hero or nav. |
| **Eclipse, architecture, Art Deco ornament** | Atmospheric visual language | The hero, frames, rules and dividers |


## Excluded motifs

Lore art, characters and races. Heavy occult props (bullets, serpents,
apples, blood drips, sigils). Floating runes and decorative "magic". Faux
terminals or RPG-codex interfaces. Constant framing: in the body only the
Black teaser and the project card get full frames. The render's interactive
compiler controls and fabricated "Compiled successfully" output: the Black
teaser is static, with no buttons and no output.

## Tokens

All tokens are in `assets/styles/site.css` §2.

| Token | Value | Use |
| --- | --- | --- |
| `--void` | `#0B0B0D` | page background |
| `--aged-gold` / `--gold` | `#C2A46A` | linework, ornament |
| `--bone` | `#E7E2D2` | primary text (15.6:1 on void) |
| `--blood` | `#7A0E14` | primary CTA fill, accents |
| `--verdigris` | `#51796B` | status (`--verdigris-bright #74A595` for small text) |
| `--surface-1` / `--surface-2` | `#121013` / `#1A1619` | card surfaces |
| `--text-muted` / `--text-faint` | `#BBB4A2` / `#8F8878` | secondary text (9.5:1 / 5.6:1) |
| `--text-gold` | `#D2B77E` | small gold text and links (9.8:1) |
| `--gold-bright` | `#E2C88C` | hover and **focus ring** |
| `--gold-line` / `--gold-hairline` | gold at 60% / 28% | rules and borders |

The palette's exact hex values are kept as tokens. Small text uses the
lighter functional variants so readability wins, as the PRD allows.

## Typography

| Role | Face | Licence | Fallbacks |
| --- | --- | --- | --- |
| Display | Cinzel 400/600 | SIL OFL 1.1 | Trajan Pro, Cormorant SC, Times New Roman, serif |
| Body | EB Garamond 400, 400 italic, 500 | SIL OFL 1.1 | Garamond, Iowan Old Style, Palatino, Georgia |
| Code | JetBrains Mono 400 (used by the Black teaser excerpt) | SIL OFL 1.1 | ui-monospace, SF Mono, Menlo, Consolas |

The fonts are self-hosted Latin subsets from Fontsource 5.1.0 (about 135 KB in
total), with `font-display: swap`. Licence files ship next to the fonts in
`dist/assets/fonts/`. Body text is 19 px because Garamond reads small.

## Composition and responsive rules

- **Geometry.** A `.stage` wrapper holds the three plates behind both the
  hero and the Black teaser. `--plate-w` is `max(100vw, 1100px)`; positions
  and the hero text offset are fractions of it, so the layout stays
  registered to the render at any width at or above 1100 px.
- **Desktop (>=1100 px).**
  - One-row nav on the render's header line, with the medallion on the rule.
  - Name, rule-and-diamond divider, thesis and disciplines on the render's lines.
  - Then the two CTAs, then the framed Black teaser inside the first view.
- **Tablet (641-1099 px).** A centre crop at 1100 px scale; CSS corner fans
  stand in for the render's (now off-screen). The role line moves into the
  dark disc. Disciplines form a 2x2 grid below 900 px and the teaser and
  About stack.
- **Mobile (<=640 px).** The medallion gets its own row; the plates start
  below the nav with a feathered edge; the name stacks across the disc;
  CTAs, teaser, card and About stack.

## Motion

No ambient animation (the earlier sky "breath" was removed: it pulsed
against the plate seams). Interaction transitions (nav underline, card
arrow, button fill) last up to 200 ms. With `prefers-reduced-motion:
reduce` all transitions are off and smooth scrolling is disabled. The page
ships no JavaScript.

## Phase 03: the scrolling homepage

The rhythm is **grand → intriguing → substantial → reflective →
personal**, carried by surface and ornament rather than by new imagery.

| Section | Treatment |
| --- | --- |
| Arrival | Unchanged and regression-gated (hero band pixel-identical to the approved baseline) |
| Black teaser | The same 9-slice frame over the stage art. The code panel is wider at ≥1100 px so the verified program fits unscrolled; below that, long lines wrap with a hanging indent beside their line number, so the whole program is readable on a phone without horizontal scrolling. A chamfered "Explore Black" cartouche (as in the render) replaces the render's fake Compile/Run controls. Labels wrap balanced (no orphaned words) |
| Selected Work | The render's framed horizontal cards (art panel left, text right), two or three per row; text-only cards use a single column. On the homepage the category sits above the verdigris status, so titles align across a row; tags follow the summary and the "View project" link is pinned to the card's foot above a hairline, so equal-height cards end on one ruled line. Below 900 px a single column; below 640 px art above text |
| Engineering Philosophy | No frame and no art: an engraved verdigris label, an italic Garamond heading (echoing the thesis), a diamond rule, and three principles divided by gold hairlines with Roman numerals. A faint band of eclipse light between two fading hairlines marks the change of mood |
| Writing (conditional) | A ruled article index: date column, title in tracked capitals, summary, "Read" link |
| About and Contact | The tree emblem (its one appearance) beside a lede and a quieter paragraph; contacts as small hairline cartouches showing label and destination |

Between sections: the existing ruled section titles (Selected Work, About,
Writing), hairlines and spacing. No additional eclipse, monogram or monument.

### Visual discrepancy register (Phase 03)

| Area | Difference from the approved render | Why |
| --- | --- | --- |
| Black teaser points | "Closed types and exhaustive matching / Integer arithmetic proved to fit its types / Compile-time contracts, for a first fragment" replace "Strong static guarantees / Effect and resource safety / A foundation for AI-native development" | Effects and ownership are reserved words in Black, not implemented; the AI-agent loop is planned, not built. Only implemented capabilities are claimed |
| Black excerpt | A real 15-line conformance program instead of the render's invented 10-line one | The render's syntax (`fn`, `IO Unit`, `F64`) is not Black's |
| Black teaser height | Taller than the Phase 00 teaser (15 lines, plus the link) | Follows from the verified program. The teaser frame's top edge is unchanged |
| Selected Work | Two cards (Brigid, Lockdown), not the render's three (Brigid, Crest, Lockstep) | Crest and Lockstep are withheld (see the Phase 03 retrospective); the render's card copy for Brigid described a language, which Brigid is not |
| Nav | No Writing or Résumé links | No published writing and no résumé yet; links appear only with real destinations |
| Code ligatures | Disabled in all code | JetBrains Mono drew `->` as an arrow, altering the verified source |

## Phase 04: project dossiers

Each dossier is a chamber in the same building: the shell is shared and
only the hero and the mix of section layouts differ.

| Element | Treatment |
| --- | --- |
| Hero (optional) | *(Revised in the layout remediation.)* The opening of the main column, beside the sidebar, as in render 03; not full-bleed. Shallow (`clamp(20rem, 46vh, 28rem)`), with no frame: a mask fades the art into the page on every side. Veils darken the lower left (where the text sits) and the foot. The text shares the dossier's left edge. It is cropped by `object-fit` at a validated focus point, with separate points for desktop and phones. Edge to edge and taller on phones. Title in gilded Cinzel (the homepage name's gradient), summary in italic Garamond, tags as hairline cartouches. A ruled diamond hands over to the first section |
| Overview | Prose, then a ruled fact strip: verdigris labels over bone values in hairline-divided columns (a two-column definition table on phones) |
| Wide exhibit | The artifact in the card's 9-slice Deco frame at full column width; the copy below as a caption, led by a short gold rule |
| Split | Prose (2 parts) beside the framed artifact (3 parts), side chosen per section; stacked in reading order below 1180px |
| Grid | A hairline lattice (gold gaps between dark cells), a diamond mark per item, titles in tracked gold capitals |
| Resources | Quiet: a hairline above, smaller muted title and text |
| Code panels | A tab with a diamond, the file label in mono gold and the language in faint capitals; lines wrap with a hanging indent instead of scrolling |
| Diagram (Black pipeline) | Hand-authored SVG in the palette: four chamfered chambers, verdigris numerals, a blood-red dashed evidence loop. Scrolls inside its frame on phones, with a link to the full-size file |

### Visual discrepancy register (Phase 04)

| Area | Difference from the brief or the approved render | Why |
| --- | --- | --- |
| Heroes | **Not delivered.** Black, Brigid and Lockdown use the plain header; no symbolic hero is on any committed page | `.local/heroes/` was empty throughout the phase. The banner was built and verified with stand-in art (the homepage plates composited; `design/proof/phase-04/stand-in-hero/`), which was not committed as a hero |
| Black dossier | No interactive compiler, no AST or output panels from render 03 | No live compiler exists; the exhibit is the real pipeline and two verbatim conformance programs (one accepted, one rejected) |
| Black "Key features" / "Design goals" (render) | Replaced by "Design principles": rules White enforces today | The render's items (effects and resource safety, AI-native tooling) are not implemented |
| Crest | No dossier | Withheld again: the repository has not changed since Phase 03 (last push 2026-10-24) |
| Diagram text | SVG text uses serif fallbacks (Georgia/Times), not Cinzel and EB Garamond | An SVG loaded through `<img>` cannot use the page's web fonts |
| Phone diagram | Scrolls sideways inside its frame | At 390px the full diagram's labels would be about 6px; a legible minimum width plus a full-size link is more useful |
| Heading rules on phones | A wrapped section title leaves its gold rule beside the last line | Pre-existing Phase 02 behaviour of `.project__section-title`; left unchanged (hidden only for the hero kicker) |
| Hero frame and corner fans (remediation) | Removed | The remediation brief asks for an atmospheric hero with no frame around the artwork; render 03 has none |
| Phone order (remediation) | The project header or hero now comes before the compact section index (it was index first) | The brief's suggested mobile order. Source order follows it, so reading and keyboard order match (ADR 0003, decision 11) |
| Long project names in the sidebar tab | A single word longer than the tab (about 11 capitals) overflows its chamfer where the browser cannot hyphenate (`hyphens: auto` is set; headless Chromium has no dictionary) | No real project name comes close; found with a stress-test title in the preview only |

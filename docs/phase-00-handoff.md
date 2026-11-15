# Implementer Handoff — Personal Technical Folio — Phase 00

**Status:** Ready to implement · **Date:** 2026-11-14  
**Phase:** 00 — Repository foundation, Dockerized Haskell build, and visual proof  
**Authority:** `personal-portfolio-prd.md` and `personal-portfolio-implementation-plan.md`; this handoff adds the explicitly requested repository/bootstrap and Docker requirements.  
**Hard stop:** Do **not** begin Phase 01 until the owner reviews and approves the visual gate.

## Mission

Establish a clean, reproducible repository with a Dockerized Stack/GHC build, prove that the **core Brigid library** can render a real page from a minimal Haskell executable, and deliver a polished browser-visible visual proof of the approved **dark Art Deco noir** homepage. The proof consists of a responsive header, theatrical hero, transition into Selected Work, and **one fully styled project card**. The source must be usable as the foundation for Phase 01, but must **not** become a premature site-generator framework.

**Phase 00 completion is visual credibility plus reproducible build, not feature breadth.**

## Sources and precedence

1. `personal-portfolio-prd.md` — product requirements and nonnegotiables.
2. `personal-portfolio-implementation-plan.md` — phase structure and original visual gate, as amended by this handoff.
3. `a_detailed_cinematic_dark_art_deco_portfolio_webs.png` — **approved SECOND website render**, authoritative homepage composition: monumental eclipse, architectural silhouettes, typographic identity, dark tactile atmosphere, then restrained scrolling content.
4. `a_detailed_high_resolution_cinematic_website_hom.png` — **approved THIRD render**, for future dossier continuity **only**, not for implementation in this phase.
5. `image(20261111-163124).png` — original handwritten monogram, **authoritative geometry**.
6. `art_deco_gold_tb_eclipse_emblem.png` — the **FIRST gold monogram adaptation** in the conversation, authoritative style direction; retain the original swoop **in front of the two vertical strokes**. The gold adaptation is a reference image, not a guaranteed vector master.
7. `eclipsing-eden-art.zip` → `01_branding/source_boards/` and `00_docs/eclipsing_eden_book_art_style_guide_v2_subject_neutral.md` — palette, ornament, typography, texture and atmosphere. **Ignore all playable-race concept art.** A curated `portfolio-phase00-reference-kit.zip` is supplied to avoid importing the entire art archive.

Do not copy generated concept mockups wholesale into a webpage as a flattened image. Reconstruct the UI with real HTML text, CSS/SVG, and layered decorative artwork. Avoid reproducing fantasy-specific lore/characters or turning the site into an RPG codex.

## Scope fence

**IN:** Initialize repository; Dockerfile/Compose/Stack package; smallest useful Haskell executable that renders a static proof via Brigid; design tokens and responsive CSS; original-mark-based vector logo; a working static preview; one complete card; screenshots and a visual comparison; reproducible build/test commands and a short retrospective.

**OUT:** Content discovery/JSON metadata, Markdown parsing, dynamic routes, full homepage sections, project dossiers, CMS, database, app server, Hakyll, Pandoc, Tailwind, React/Next/Astro, client-side routing, live Black editor/compiler, project-specific embedded demos, building a general-purpose SSG, CI Haskell builds, public deployment.

**Do not change Brigid itself** as part of the phase. If its public API blocks an essential proof, document the minimum blocker and stop rather than silently forking or expanding scope.

## Execution order and dependencies

### 00.0 — Initialize source control and reference inventory

- Create a new repository with a straightforward README, `.gitignore`, `.dockerignore`, `LICENSE` placeholder only if ownership/licensing is decided, and a clear `design/` and `assets/` tree. Use the existing repository if one has already been created; never overwrite unrelated work.
- Curate only the relevant brand boards and the selected logo/site references. Distinguish `design/references/` (not shipped) from `assets/` (production-bound). Do not commit the 287 MB Eclipsing Eden source archive, race art, or other unnecessary originals.
- Write `design/visual-direction.md`: adopted motifs (eclipse, monumental architecture, sharp serif, aged-gold linework, restrained blood/verdigris, parchment text) and excluded motifs (lore art, heavy occult props, decorative clutter). Document reference image provenance.
- Do not commit an unreviewed stock font or redistribute font binaries from system installations. Select properly licensed downloadable web fonts and document their licenses.

### 00.1 — Dockerized Haskell bootstrap (required hard gate)

- Create a **small Stack-based Haskell executable**, not a generic site generator. It must compile and render the hero + project-card proof **using the core Brigid library**, producing a complete HTML document and copying only the needed CSS/SVG/image assets to `dist/`.
- Dockerize **all Haskell build and execution commands**. The host should need only Docker Engine + Compose (and an ordinary browser); it should **not** need GHC, Stack, Cabal, Node, or Haskell dependencies installed. Native tooling may be optional but not required.
- Start from the known Brigid-compatible image/toolchain rather than inventing a new combination. Brigid's current repo demonstrates `ghcr.io/flipstone/haskell-tools:debian-ghc-9.10.3-1e1d10c` with Stack `lts-24.12`; verify the image and pinned resolver work in this new repository. If they fail, use a proven compatible combination, record the change and reason. Pin the image version (prefer an immutable digest when practical), resolver, `stack.yaml.lock`, and a **specific Brigid commit SHA**, never floating `main`. Check whether Brigid's documented system packages (`libphonenumber-dev`, `libprotobuf-dev`) are needed and install them in the image if so.
- **Only consume the `brigid` core package**, not `brigid-generation`, benchmarks, generated test data, or unrelated packages from the Brigid monorepo. Brigid's own core dependencies may still be substantial; the target is avoiding unnecessary generator/benchmark dependencies, not pretending cold compilation is free.
- Docker Compose must include (a) a one-shot `site-build` service and (b) an optional lightweight **static** `preview` service. `preview` serves the generated `dist/` directory, not Haskell/WAI/Warp. Suggested user-facing commands (exact syntax may be adjusted, but document the final equivalents):
  ```sh
  docker compose build site-build
  docker compose run --rm site-build
  docker compose up preview
  ```
  Provide a documented way to run `stack test` or equivalent smoke checks inside the same image.
- Persist the Stack downloads/package-db/build cache across runs with a Docker named volume or documented local ignored cache directories. Avoid resetting the cache on every build. Do not require external pre-created Docker volumes.
- Bind-mount the source for the development loop and write generated `dist/` to the host-accessible working tree. **Avoid root-owned output files** on Linux by handling UID/GID carefully; test ownership and explain any platform differences. Cache permission handling must work for fresh volumes.
- Use only small, explicit shell scripts if necessary. Never solve ordinary Docker problems with opaque bootstrap automation, host sudo/chown steps, `curl | sh`, Nix, or a bespoke watcher.
- Add `.dockerignore` / `.gitignore` entries for `dist/`, `.stack-work/`, `.stack-root/` or chosen caches, screenshots not intended to ship, and temporary artifacts. Do not accidentally exclude files needed for container builds.
- Document exactly what is Dockerized, how to rebuild, how to inspect toolchain versions, and what happens on a clean checkout. **Do not add a cold GHC/Brigid build to GitHub Actions.**

### 00.2 — Create the reusable visual foundations

- Use the approved design colors: void `#0B0B0D`, aged gold `#C2A46A`, bone `#E7E2D2`, blood `#7A0E14`, verdigris `#51796B`. Add readable supporting/hover/focus surface tokens rather than overusing palette colors.
- Define the typography stack: sharp engraved-feeling display serif, practical readable body face, and monospaced code face; verify licenses/fallbacks and contrast. Use real HTML text, not words rasterized in the hero illustration.
- Create restrained SVG borders, cartouche/button treatments, dividers, ornament primitives, and texture layers. Prefer reusable assets/CSS tokens to screenshots of the mockup.
- Produce a simple, static functional layout in the absence of JavaScript. Motion may be limited to CSS; honor `prefers-reduced-motion`. Avoid WebGL/WASM/canvas unless an indispensable visual element cannot otherwise be achieved, and record justification before adding it.

### 00.3 — Trace the monogram correctly

- Create `design/monogram.svg` as the editable vector **master**, with layers allowing the horizontal swoop to cross visibly **in front of both upright strokes**. Preserve recognizable proportions and expressive sweep of the original purple handwritten mark rather than replacing it with a generic serif `TB` monogram.
- Produce `assets/brand/monogram-simple.svg` (nav and favicon), plus an optional surrounding Art Deco ornament for larger placements. The core letterforms must remain usable without the eclipse or outer frame.
- Check against the original image at full size and favicon dimensions. Include a visual comparison in `design/monogram-review.md`, and note any manual approximations to address later.

### 00.4 — Render the visual proof through Brigid

The one generated page at `/` should contain:

1. A responsive semantic header/nav including the real monogram and visible links/anchors (no dead interactive affordances).
2. A dramatic hero matching the approved second render: name, grounded professional role line, concise *draft* thesis, monumental eclipse, architectural silhouettes, aged metal/black textures, and two functional CTAs (they may target the on-page Selected Work anchor and a real About/contact anchor; do not point to nonexistent future pages).
3. A subdued but elegant transition into Selected Work.
4. **One genuinely finished project card**, e.g. Black or Brigid, with visual, accurate one-line description and a functional accessible link (an on-page detail anchor is acceptable until actual project routes exist).

Do **not** embed the Black compiler on the homepage. If a code sample/compile state is shown, it must not fake a working compiler. One project card is sufficient.

Composition should be visually faithful in **hierarchy and atmosphere**, not a literal pixel clone. Strive for premium editorial quality: spacious, clear content, precise ornament, readable contrast, and a dramatic opening that becomes calmer below.

### 00.5 — Verification, screenshots, and gate report

Run from a **clean checkout** with no host Haskell installation. Record the actual commands, their exit codes, and relevant toolchain versions. At minimum verify:

- Docker image builds; Stack/GHC and Brigid compile successfully inside the container; generated `dist/index.html` exists with nonempty HTML and expected static assets.
- A second unchanged build reuses caches, succeeds, and produces an equivalent HTML artifact (compare hash or normalize expected nondeterministic metadata; do not inject timestamps).
- Preview server serves `http://localhost:8080/` (or clearly documented chosen port) with CSS/images loading and no backend.
- Host can read, edit, delete, and rebuild the generated output without `sudo` (especially Linux).
- Desktop ~1440px, tablet ~768px, mobile ~390px screenshots; include keyboard-focus and reduced-motion captures.
- Keyboard navigability, semantic heading structure, visible focus, responsive no-overflow behavior, no text rendered into background images, essential navigation visible without JavaScript, and appropriate alt/decorative handling.
- Compare the screenshots to the **approved second render**; assess eclipse scale, architecture framing, name hierarchy, layout rhythm, ornament density, mood, and transition into cards. Record concrete mismatches, not simply “looks close.”
- Test at least one failure: build/asset processing fails clearly when a required asset is absent, rather than producing silent broken markup.

Write `DESIGN_GATE.md` with `gate passed | corrections required | blocked`, evidence links, known deviations, and the specific items requiring owner review. **The implementer should not self-approve the visual gate.** Provide screenshots and ask for approval rather than silently beginning Phase 01.

## Expected repository shape (adapt as needed; avoid placeholders)

```text
personal-portfolio/
├── Dockerfile
├── compose.yaml
├── stack.yaml
├── stack.yaml.lock
├── package.yaml              # or a minimal .cabal file
├── app/Main.hs
├── src/Site/Proof.hs          # smallest Brigid proof component
├── assets/
│   ├── brand/
│   ├── styles/
│   └── images/
├── design/
│   ├── references/            # curated, nonproduction references
│   ├── visual-direction.md
│   ├── monogram.svg
│   ├── monogram-review.md
│   └── proof/
│       ├── desktop.png
│       ├── tablet.png
│       ├── mobile.png
│       ├── keyboard-focus.png
│       ├── reduced-motion.png
│       └── comparison.md
├── dist/                      # ignored generated output
├── DESIGN_GATE.md
└── README.md
```

## Phase 00 acceptance gate

- [ ] `docker compose build site-build && docker compose run --rm site-build` works with no host Haskell.
- [ ] Docker environment uses a documented pinned GHC/Stack resolver and pinned **core-only** Brigid dependency; repeated builds benefit from persistent cache.
- [ ] Static generated output belongs to/writable by host user on Linux; preview service serves the page.
- [ ] The generated proof uses **Brigid**, not disposable handwritten HTML or a JS framework.
- [ ] Recognizable original monogram vector; front-crossing swoop retained; usable small-size variant.
- [ ] Hero visually captures the monumental eclipse, architecture, engraved typography, noir/gold contrast, and compositional depth of the **second** render.
- [ ] One polished, real, responsive project card and a restrained Selected Work transition.
- [ ] Basic keyboard, reduced-motion, no-JS, desktop/tablet/mobile checks pass.
- [ ] Visual comparison evidence and `DESIGN_GATE.md` are complete. **Owner approval pending until explicitly given.**
- [ ] No Phase 01 generator/content/Markdown features, Black compiler, backend, or unnecessary dependency work has been introduced.

## Required implementer report

```text
Phase: 00 — Repo + Dockerized Haskell + Visual Proof
Status: corrections required | blocked | ready for owner approval
Git branch/commit:
Changes and files:
Pinned image/GHC/Stack resolver/Brigid commit:
Commands and actual outcomes (including clean build and preview):
Host generated-file ownership test:
Screenshot links (desktop/tablet/mobile/focus/reduced motion):
Visual deviations vs second approved render:
Monogram fidelity findings:
New dependencies and why:
Known limitations:
Next phase prerequisites:
```

**Stop after presenting the gate evidence. No Phase 01 implementation without the owner's review.**

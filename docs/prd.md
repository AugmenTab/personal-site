# Product Requirements Document — Personal Technical Folio

**Status:** Ready for implementation planning  
**Version:** 1.0 — November 14, 2026  
**Owner:** Personal project  
**Working title:** Personal Technical Folio (not a proposed public-facing brand name)

## 1. Product vision

Create a distinctive personal website that communicates professional engineering credibility and creative range through a unified, dark Art Deco noir visual language. It should be compelling on arrival, easy to navigate, and substantial on inspection.

**Core experience:** A cinematic scrolling homepage invites visitors into the work; reusable project pages provide proof, technical depth, and appropriate media; the Black project page eventually includes a genuine, editable compiler playground.

The website must not become a navigable 3D environment, a game, a generic developer template, or a substitute for actual project evidence.

## 2. Users and outcomes

**Primary audiences:** Engineering hiring managers, technical interviewers, potential collaborators, and engineers evaluating the work. **Secondary audiences:** Peers, readers, and people interested in creative technical projects.

Within approximately 30 seconds, a first-time visitor should be able to identify the author, understand the broad areas of work, find a relevant project, and reach contact/resume links. Interested visitors should be able to go deeper without fighting the visual design.

Success means the design is memorable **and** visitors can independently inspect what was built, why, and how.

## 3. Visual direction and authoritative references

- **Homepage reference:** The **second** approved website concept render: monumental eclipse and architectural silhouettes, prominent personal identity, cinematic landing composition, then selected work and a restrained scrolling continuation.
- **Project-page reference:** The **third** website concept render, adapted into a modular, inspectable project dossier rather than copied literally as another homepage.
- **Brand source:** The `01_branding` boards and style guide within `eclipsing-eden-art.zip`. Use *style and ornament*, not the setting's characters, fantasy lore, or race concept art.
- **Logo source:** The user's original handwritten monogram, interpreted through the **first** of the three gold adaptations. Preserve the recognizable swoop crossing **in front of** the vertical strokes. Ornament may surround but must not obscure the original mark.

**Palette, subject to contrast tuning:** Void `#0B0B0D`; Aged Gold `#C2A46A`; Bone `#E7E2D2`; Blood `#7A0E14`; Verdigris `#51796B`. Blood and verdigris are restrained accents. Readability takes priority over strict use of these exact hex values.

Use engraved-feeling display serif typography, highly readable body and code faces, dark tactile texture, thin metallic lines, and selected architectural/sacred-geometric motifs. Maintain one aesthetic throughout the site. Avoid making the portfolio resemble a game lore compendium, a faux terminal, or an occult roleplay interface.

**Motion principle:** Almost everything is still. Animate only to signal arrival, navigation, interaction, or a meaningful system state. Reduced-motion and static fallbacks are required.

## 4. Information architecture

Required routes:

- `/` — scrolling homepage.
- `/work/` — all published projects, filterable or simply indexed initially.
- `/work/{slug}/` — reusable project dossier template.
- `/about/` — concise biography, experience, personal technical interests, and contact information.
- `/writing/` and `/writing/{slug}/` — enable when actual essays/notes exist; do not publish empty filler pages.
- `/404.html` — intentional not-found page with a clear route home.

Global navigation: **Home, Work, Writing (when populated), About, Résumé, Contact**. External GitHub/LinkedIn links should be easy to find. Résumé may link to a PDF once supplied; Contact may initially use `mailto:`.

URLs should be stable, human-readable, and not dependent on JavaScript navigation. Generate canonical metadata, social preview metadata, `sitemap.xml`, and `robots.txt`.

## 5. Homepage requirements

### H1. Arrival / hero

A cinematic first view informed by the second render: personal monogram in navigation, prominent name, grounded role description, concise thesis line, eclipse motif, architectural silhouettes, and subtle layered depth. Primary CTA leads to work; secondary CTA leads to résumé/about. Essential identity and navigation must be visible immediately, without waiting for animation.

### H2. Black featured teaser

Black is the marquee featured project, but **there is no compiler editor embedded on the homepage**. Show a real, verified source example or attractive static technical preview, a brief accurate description, a few differentiators, and a link to Black's project page. If a compiler result is depicted, it must be a real result, not a fabricated successful compilation.

### H3. Selected work

A curated set of approximately 4–6 featured projects. Initial candidates: Black, Brigid, Crest, Lockstep, and the game engine; final selection is editorial, not an architectural blocker. Each card has a title, accurate one-line description, distinctive visual, and unambiguous link. No project is required to have a browser demo.

### H4. Engineering philosophy

One short typographic section about principles of engineering and creativity. Avoid unsupported superlatives or lengthy self-mythologizing. Treat proposed copy as draft until reviewed.

### H5. Writing preview

Show recent published essays/notes if any exist; otherwise hide the section cleanly.

### H6. About / contact footer

Concise human introduction, professional links, contact and résumé access, and a simplified use of the monogram. No mandatory form or backend.

## 6. Project dossier template

Every project page includes:

1. **Project hero:** title, clear subtitle, status, technologies/categories, relevant source/demo links, and a distinctive illustration or media preview.
2. **Primary showcase:** the best evidence for that project (image, video, audio, annotated code, architecture diagram, or interactive element). Supports full-screen viewing where appropriate.
3. **The problem:** what motivated the project and why it matters.
4. **The approach:** important technical decisions and architecture.
5. **The hard parts:** tradeoffs, limitations, failures, or constraints worth discussing.
6. **The evidence:** measurable results, tested functionality, source code, recordings, or demonstrations; do not invent metrics.
7. **Current state:** clearly distinguish working, in-development, and proposed capabilities.
8. **Related work / next project:** navigation that encourages exploration without trapping the reader.

One reusable template and a small set of typed showcase variants must support all projects. The site must not require bespoke interactive code for each card or dossier. Crest, for example, can use REAPER footage and audio comparisons rather than reproducing REAPER in a browser.

## 7. Black playground — independent feature track

**Location:** `/work/black/` only, within an expanded showcase. **Release gate:** may be activated when a real compiler interface is ready; it must never be simulated for visitors.

### P1. Editor and examples

Use an accessible source editor, with editable Black programs, reset capability, and a selector of curated examples. Visitors may write their own programs within the supported language subset. Examples must be continuously checked against the compiler version deployed.

### P2. Compilation and output

Offer compilation independently of program execution. Show two tabs from the **same actual compiler invocation**:

- **Human diagnostics:** readable Elm-quality messages, source locations, explanatory notes and actionable suggestions when available.
- **AI / JSON:** the compiler's canonical structured diagnostics, pretty-printed, copyable, and not semantically rewritten by the website.

Display successes, compilation failures, unresolved proof/contract obligations, and infrastructure failures distinctly. Do not label an unresolved obligation as successful compilation. Only provide Run where a safe execution backend genuinely exists.

### P3. Status ornament

A small geometric element responds meaningfully to compiler state: complete/verdigris for valid, interrupted/blood for invalid, and neutral/gold for compiling or unresolved. Color alone must not communicate state; include accessible text and announcements.

### P4. Compiler runtime boundary

The website must expose a replaceable compiler adapter. The implementation may eventually be browser-local WebAssembly, an isolated server API, or a hybrid, depending on Black's actual capabilities. This choice **does not block the site generator or public portfolio release**.

If public server compilation or execution is enabled, enforce strict payload, CPU, memory, time, concurrency, and filesystem/network access limits. Treat all submitted programs as untrusted. No native program execution on the website host.

## 8. Technical architecture

### T1. Static-first, purpose-built generator

Build a **small Haskell executable** that discovers content, parses metadata/Markdown, renders typed layouts with **Brigid**, validates output, and writes `dist/`. **No Hakyll, Pandoc, or general-purpose framework**. No application server, database, or authentication for the portfolio.

### T2. Content

Keep project metadata in portable, validated records (JSON is the initial default), long-form project descriptions and articles in Markdown, and bespoke homepage copy in clearly maintained content records. Use an existing lightweight CommonMark parser unless a specific limitation justifies local parser code. No generic templating DSL or cross-project Markdown framework.

### T3. HTML boundary

Use Brigid for document structure, site chrome, cards, and project layouts. Markdown output must pass through an explicitly safe rendering boundary. Disallow arbitrary embedded HTML or sanitize it; validate URL schemes. Do not treat untrusted HTML strings as typed-safe Brigid structure.

### T4. Browser presentation

Use ordinary CSS, SVG, optimized images, and small TypeScript modules for progressive enhancements. Prefer SVG for logos/ornaments and layered imagery for the hero; avoid WebGL or WebAssembly unless a specific interaction actually requires it. Core content and navigation must remain functional without JavaScript.

### T5. Build and deployment

Build and test Haskell **locally**, then deploy generated assets to a static CDN/host (Cloudflare static hosting is the initial preference). A single scripted command runs a clean build, validates output, and deploys. Avoid cold-building the Haskell dependency graph in free GitHub Actions runners. Optional CI may run independent, lightweight frontend/asset checks.

Full rebuilds are sufficient initially. No custom incremental build engine. Pin dependency versions and keep Black's build/deployment independent of the site generator.

### T6. Future Black migration

Preserve portable content, stable URLs, plain CSS/SVG, and an explicit renderer boundary so the Haskell generator can eventually be replaced by a Black implementation without redesigning the site. Do not introduce a Black dependency into the initial generator.

## 9. Nonfunctional requirements

**Accessibility:** Semantic landmarks and headings; full keyboard navigation; visible focus; suitable text contrast; alt text for informative imagery; proper labeling and status announcements; responsive layouts; respect `prefers-reduced-motion`; never make parallax or animation a navigation dependency.

**Performance:** Static first paint, no loading splash, no client-side hydration requirement. Optimize hero/media assets, lazy-load below-the-fold images, and load Black editor/compiler assets only on its project page. Use Core Web Vitals as validation goals (e.g., LCP at or below 2.5 s and CLS at or below 0.1 under representative testing), not unmeasured launch claims.

**Reliability and security:** Escape content and metadata, validate links and assets, avoid credentials in generated files, prevent accidental publication of development files, maintain explicit missing-content failures, and use safe embedding for external media. External links and contact endpoints must be reviewed before release.

**SEO and sharing:** Correct titles/descriptions, canonical URLs, social preview images, sitemap, and stable descriptive routes. Content should be readable without JS and discoverable by search engines.

## 10. Validation and acceptance criteria

The initial portfolio release is complete when:

- The homepage visibly follows **render two's** cinematic-first, scrolling composition and the actual Eclipsing Eden-inspired style, not a generic substitute.
- The project dossier follows **render three's** modular presentation and is populated with at least **four real, accurate project pages**.
- The adapted personal monogram preserves the original swoop-over-stems geometry; simplified nav and favicon variants remain recognizable.
- The homepage shows a **Black teaser, not an editor**; its link reaches the Black dossier.
- Projects can present heterogeneous evidence without requiring a custom application per page.
- Work, About, Contact, and résumé navigation are straightforward; Writing appears only when populated.
- Mobile, tablet, desktop, keyboard, and reduced-motion experiences are verified.
- Builds are reproducible from a clean local checkout, generate no broken internal links or missing assets, and deploy via the scripted local release flow.
- Key pages use semantic HTML, remain usable without JavaScript, and have verified metadata and social previews.
- No visitor-facing text or UI falsely implies a planned capability is already operational.

The **Black playground release** has its own acceptance gate: visitors can select valid curated examples or edit their own source, submit to a real compiler, inspect both authentic human and JSON diagnostic representations, and understand all success/error/unresolved states. Safe execution is optional until an isolated runtime exists.

## 11. Explicit exclusions

- Navigable 3D rooms, game-like website navigation, or a bespoke graphics engine.
- Embedded live demos for every project.
- A CMS, database, user accounts, analytics backend, or hosted server for static content.
- Hakyll, Pandoc, general-purpose SSG/framework work, or a custom incremental build system.
- A general Markdown parser/templating DSL intended for Artificer or Grimoire.
- Fake Black compilation output, imaginary functionality, or insecure arbitrary code execution.
- Full reimplementation of the portfolio in Black before it can support the workload.

## 12. Delivery sequence and dependencies

**Phase 0 — Foundation and visual proof:** Confirm references, choose licensed fonts, trace/vectorize the original monogram, implement the palette and key ornaments, and produce a responsive hero + one project-card slice. This is a visual gate: do not proceed with a generic-looking substitute.

**Phase 1 — Generator:** Build the Haskell/Brigid static generator, typed metadata, Markdown rendering boundary, routes, and basic output validation. Generate a homepage and one dossier from real content.

**Phase 2 — Complete portfolio:** Finish homepage sections, reusable project showcases, About, navigation, actual project write-ups, responsive styles, and SEO assets.

**Phase 3 — Polish and launch:** Add restrained interaction, performance optimizations, accessibility passes, browser checks, local deployment script, and documented release process.

**Phase 4 — Black playground (parallel or later):** Finalize compiler adapter, build editor and examples, implement human/JSON diagnostics and geometric states, prove the security boundary, and enable only when real compilation works.

## 13. Open decisions — nonblocking

- Final domain name, hosted email/contact destination, and résumé asset.
- Final approved homepage copy, exact featured-project order, project imagery, and initial published writing.
- Exact font pairing and final SVG treatment for the monogram, to be resolved in the Phase 0 visual proof.
- Specific lightweight Markdown package and metadata schema details, to be finalized in Phase 1.
- Black's eventual compilation location (WASM, isolated API, or hybrid), dependent on working compiler capabilities.

These are content, implementation, or independent feature-release choices—not blockers to starting the portfolio now.

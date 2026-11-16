# ADR 0003 — Project dossiers, symbolic heroes and section layouts (Phase 04)

**Status:** accepted for owner review, 2026-11-15
**Context:** Phase 04 turns the Phase 02 project pages (one prose layout,
see [ADR 0001](0001-content-pipeline.md)) into dossiers: a shared shell, a
project-specific symbolic hero, and a small typed vocabulary of section
layouts.

## Decisions

1. **Prose stays in one Markdown file; presentation is typed JSON.**
   The body's `##` sections remain the dossier's sections, in body order,
   with ids derived from their headings. `project.json` gains `sections`,
   an object from section id to layout. Writers edit one Markdown file;
   structure is validated metadata. Considered and rejected: one Markdown
   file per section (fragments the narrative and duplicates ordering), and
   Markdown directives or fenced attributes (a layout DSL inside content).

2. **Exactly five layouts, as a closed sum type.** `DossierBody` is
   `Overview | WideExhibit | Split | Grid | Resources`; each constructor
   carries only what it presents. The JSON decoder accepts only these
   names and only each layout's own fields. A sixth layout is a code
   change, reviewed like any other, never a content convention.

3. **Unlisted sections default to `overview`.** Existing bodies (Lockdown)
   keep working unchanged, and the common case needs no configuration.

4. **Grids are Markdown, validated structurally.** A grid section is an
   optional introduction and one bullet list of 2 to 9 `**Title.** text`
   items. The loader checks that shape and reports the item that breaks it.
   This keeps prose (with inline code and links) in Markdown rather than
   in JSON strings.

5. **`resources` sections close the dossier.** Once one appears, every
   later section must also be one. This makes the landing strip a rule,
   not a habit.

6. **Artifacts are image, diagram or code.** A `diagram` is an image whose
   detail must stay legible: it keeps a minimum width on phones, scrolls
   inside its frame, and links to the full-size file. A `code` artifact is
   read at build time (UTF-8, at most 32 KiB), rendered as escaped text one
   line per span (so long lines wrap with a hanging indent), and never
   published as a file. Video and audio are not artifacts yet: no
   published project needs them, and an untested media path is not added
   speculatively.

7. **Verified excerpts are tested, not trusted.** The accepted Black
   program must equal the homepage teaser's `blackExample`; the rejected
   one must have the `cast` at the MANIFEST's 8:12; the Brigid excerpt must
   appear verbatim in `src/Site/Pages/Work.hs`.

8. **The hero is optional, explicit about accessibility, and size-limited.**
   `hero` takes `src`, exactly one of `alt` or `"decorative": true`, and a
   crop `focus`. The file must be an image in the project directory and at
   most 1 MiB. A hero page uses a new `Dossier` layout (the art starts
   under the header, like the homepage stage), renders the title, summary,
   tags and links as HTML over the art, fetches the art with
   `fetchpriority="high"`, and does not repeat the card art. Without a hero
   the Phase 02 header and card figure remain.

9. **Hero art is never generated in the build.** It is prepared outside
   the repository, staged in `.local/heroes/`, and promoted by
   `tools/art/promote_hero.py` (scale down, re-encode, no crop) into a
   committed `content/projects/{slug}/hero.webp`.

10. **The sidebar is derived from rendered sections.** `sidebarSections`
    filters the same list the page renders; `sidebar: false` removes an
    entry, never adds one. A test checks every real project's sidebar
    against its sections, and the browser checks follow every link.

## Consequences

- Adding a project, or changing a dossier's layouts, needs no Haskell.
- A section id is derived from its heading, so renaming a heading breaks
  its `sections` entry. The build reports it, with the real ids.
- The hero art is the remaining open deliverable: until it arrives, the
  three published dossiers use the plain header. The banner's composition
  was verified with stand-in art, which was not committed as a hero.

## Amendment — layout remediation (2026-11-15)

Decision 8 placed the hero as a full-width banner above the project
layout, so the sidebar began below it. That contradicts the approved
project render, in which the sidebar starts under the global navigation
beside the project's opening. Decisions 8 and 9 are amended as follows;
the rest stands.

11. **One layout, with or without a hero.** The article is the layout grid:
    `article.project.project-layout` holds the opening (`header.project-hero`
    or `div.project__header`), then `nav.project-nav`, then
    `div.project__body`. On desktop the sidebar spans both rows of the left
    column, beside the opening and the dossier, and is sticky. Below 900px
    the three stack in source order. Adding or removing a hero never moves
    the sidebar (tested: its markup is byte-identical either way).

    *Deviation from the handoff's sketch,* which shows the sidebar as a
    sibling before the article: the sidebar is inside the article, between
    the opening and the body. Placing it before the article would make the
    phone order sidebar → hero, or need CSS reordering (`order` or
    `display: contents`). Both make visual order differ from keyboard and
    reading order, which is worse for accessibility. With this source order,
    one sequence (title, section index, dossier) is correct at every width.
    The cost: on desktop, a hero's external links come before the sidebar
    in tab order.

12. **The hero is an environment, not a banner.** It is confined to the
    main column and is shallow (`clamp(20rem, 46vh, 28rem)`). It has no
    frame: a mask fades its edges into the page. Veils darken it behind the
    text, and a ruled diamond hands over to the first section. The `Dossier`
    layout now differs from `Interior` only by dropping the interior glow.

13. **Focus is a validated two-dimensional point per screen class.**
    `HeroFocus { focusDesktop, focusMobile :: FocusPoint }`, with each axis
    a `FocusPercent` (0–100 in steps of 5, built only by `mkFocusPercent`).
    JSON accepts `{desktop, mobile}`, a single `{x, y}`, or the Phase 04
    keywords (`center`, `top`, `bottom`), which map to (50, 50), (50, 10)
    and (50, 90). Values become fixed classes (`project-hero--x-65` …)
    defined in the stylesheet, so content never supplies CSS text, and
    there are no inline styles, which keeps a future strict CSP possible.
    The step of 5 bounds that class list (84 one-line rules). The mobile
    point applies at 640px and below, where the hero changes shape.

14. **A size budget and a ceiling replace the 1 MiB hard limit.**
    `HeroSizePolicy` (default: 1 MiB budget, 8 MiB ceiling). Over the
    budget is accepted with a warning carried as `contentWarnings` →
    `siteWarnings` and printed by the CLI. Over the ceiling fails the
    build. `promote_hero.py` aims for the budget but never goes below WebP
    quality 80 or downscales for size, and refuses lossy sources.

15. **Heroes are previewed outside `content/`.** `site build --root`
    builds a throwaway copy (`tools/art/hero_preview.py` →
    `.local/hero-preview/`), served by a separate `hero-preview` service.
    Stand-in art never enters the repository's content tree; a test fails
    if a stand-in-named file appears under `content/`.

## Amendment — Phase 05 (2026-11-16)

16. **No card-art figure in the dossier.** A hero-less dossier no longer
    opens its body with the project's `showcase` image. That figure had no
    content role, and the owner's review found it orphaned. `showcase`
    remains the card art only (cards on the homepage and the Work index).
    A hero-less page opens with its header (title, summary, technologies,
    topics, links) and goes straight into the lead and sections; nothing
    stands in for a hero. Typed section artifacts (diagrams, images, code)
    are unaffected. No content migration was needed: the field keeps its
    shape and meaning for cards.

17. **Below 900px the sidebar is a compact disclosure.** The phone
    presentation of decision 11 (a wrapping list beside an oversized
    current-project tab) is replaced by **All projects** and a collapsed
    **On this page** `<details>` holding the section links. The title is
    already in the opening, so the tab is not displayed there. The
    desktop sidebar is unchanged. Both section lists are rendered from the
    same `sidebarSections` value in `projectNav` (decision 10 still holds),
    and CSS displays exactly one of them, so they cannot drift and the
    keyboard and screen readers meet one. A single `<details>` serving both
    widths was rejected: a closed `<details>` hides its content on desktop
    too, and the CSS that would force it open (`::details-content`) is not
    yet broadly supported.

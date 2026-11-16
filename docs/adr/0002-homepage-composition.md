# ADR 0002 — Homepage composition (Phase 03)

**Status:** accepted for owner review, 2026-11-15
**Context:** Phase 03 completes the scrolling homepage on top of the Phase 02
content pipeline ([ADR 0001](0001-content-pipeline.md)).

## Decisions

1. **The homepage selects; it never filters or sorts.**
   `Site.Pages.Home.homeContent :: Content -> HomeContent` takes Black's
   published record, `featuredProjects` minus the teaser's project, and the
   newest `writingPreviewLimit` (3) of `publishedArticles`. Publication and
   order remain the job of `Site.Content.Types`, so a draft can never reach
   the homepage by a second path.

2. **The Black teaser is a named component, not a generic "lead project".**
   Its differentiators and code are specific to Black, so it is keyed on the
   slug `black`. Its status and its link come from the content record: with
   no published Black record the teaser shows "Project page in
   preparation" and links nowhere. Black is still `featured_order: 1`, so
   it leads the Work index; the homepage leaves it out of the Selected Work
   grid to avoid presenting it twice.

3. **Editorial copy is small named Haskell records, each with a
   `CopyStatus`.** These are `introduction`, `blackTeaser`, `philosophy`,
   `About.biography` and `About.contacts`. There is no homepage CMS, DSL or
   template layer. A test pins the current `DraftCopy` status, so approving
   copy is an explicit, reviewable change.

4. **The teaser's code is verified source, shown verbatim.**
   `blackExample` records the program's provenance (repository, commit,
   path, conformance verdict). A small lexer only classifies tokens for
   colour, and a test asserts the rendered text equals the source exactly.
   The teaser contains no controls; tests reject buttons, inputs, editors
   and simulated compiler output.

5. **Conditional sections disappear completely.** Without published
   writing there is no `#writing` section, heading, "All writing" link or
   navigation entry. Without other featured projects there is no Selected
   Work, and the primary call to action points to `/work/`.

6. **Brigid moves to `e0f4d45`**, which escapes all attribute values. The
   Phase 02 mitigations (no straight quotes in attribute-bound content, and
   the build's active-content scan) stay as defence in depth. Removing them
   is a separate owner decision.

## Consequences

- Featuring, reordering or withdrawing a project is a `project.json` edit.
- Adding Writing needs only a published article; the homepage preview, the
  index and the navigation entry follow automatically.
- Swapping the teaser to another project would be a code change, which is
  deliberate: the teaser's copy is editorial, not data.

## Amendment — Phase 05 (2026-11-16)

The closing About and Contact section is replaced by a **Contact** section
(`#contact`): a short invitation and one link per verified destination.
The biography and the tree-and-eclipse emblem moved to the About page
alone. The arrival (hero) is unchanged; its secondary button keeps the
label "About & contact" and now targets `#contact`. See ADR 0004.

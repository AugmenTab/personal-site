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

# ADR 0001 — Content pipeline: JSON metadata, CommonMark, structured Brigid rendering

**Status:** accepted for Phase 02, pending owner review.
**Date:** 2026-11-15

## Context

Phase 02 has three goals:
- move project content out of Haskell into portable files;
- support Markdown narratives;
- keep Brigid's rendering guarantees without trusting content as HTML.

The constraints rule out several tools: no Pandoc, no custom CommonMark
parser, no CMS, and the pinned GHC 9.10.3 and `lts-24.12` toolchain.

## 1. Markdown parser: `commonmark` (commonmark-hs)

**Candidates:**

| Candidate | Assessment |
| --- | --- |
| **`commonmark`** | In `lts-24.12` (0.2.6.1). Spec-compliant CommonMark. Its parser is polymorphic over the output through the `IsInline` and `IsBlock` classes, so we can parse straight into our own tree with source ranges. Raw HTML reaches us as a distinct constructor, which we can reject. Small: about a minute of cold build, since its dependencies were already built for Brigid |
| `cmark` | A C binding. It produces an AST, but adds a C library to the Docker image and gives less control over node construction |
| `mmark` | Strict and opinionated, with its own extension model. It has heavier dependencies, and its availability in this snapshot is not established |
| `markdown` (yesod) | Renders HTML directly, which is the wrong boundary |
| Pandoc | Excluded by the plan |

**Decision:** `commonmark`, with its default (pure CommonMark) syntax spec.
There are no extensions, so no tables.

## 2. Rendering boundary: structured AST → Brigid (no HTML strings)

**Decision.** We implement `IsInline` and `IsBlock` for a raw syntax tree
(`Site.Content.Markdown`). Validation turns it into a small, typed
`Document`, and `Site.Content.Render` converts every node into a Brigid
element. **No HTML string is produced or embedded anywhere.** The trusted
fragment alternative was not needed.

**Consequences:**

- **Brigid's nesting rules apply to content too.** Brigid rejects `<a>`
  inside `<em>`, `<strong>`, `<h3>` and `<h4>`, so the renderer has two
  levels:
  - a phrasing renderer (no links), used inside emphasis and headings;
  - an inline renderer (with links), used in paragraphs and list items.

  The Markdown validator rejects links in emphasis and in headings, with a
  clear message. It does not silently drop them.
- **Formatting inside link text is lost.** Link text is rendered as plain
  text, because Brigid cannot prove text valid inside an `<a>` under an
  arbitrary parent. Images inside links are rejected.
- **Security finding: Brigid does not escape `"` inside attribute values**
  at commit `9344bfb`. `alt` text of `a" onerror="…` rendered a live event
  handler. The adversarial tests found this. Text nodes are escaped
  correctly, as numeric entities. Since Brigid is not patched from this
  repository, two layers protect the site:
  1. Content text that becomes an attribute (summaries, alt text) may not
     contain a straight `"`. URLs, ids, media paths and language classes
     already exclude it by construction.
  2. `Site.Validate.activeContent` fails the build on any tag containing an
     `on…=` attribute or a script-capable element. (Phase 05 allows one
     exact form, an external module script from `/assets/scripts/` with no
     inline code; see ADR 0004, decision 4.)

  This is recommended as an upstream fix in Brigid.

## 3. URL policy

- **Links** may be `https://…` with a host, a root-absolute site path `/…`,
  or a `#fragment`. Site paths and fragments must then resolve: the
  existing link validator checks them against the manifest and the target
  page's ids.
- **Everything else is rejected**, including whitespace, control
  characters, quotes, `<`, `>`, backslashes and backticks.
- **The check runs after decoding.** commonmark decodes entities and
  escapes in destinations, so `&#106;avascript:` arrives as `javascript:`
  and fails the prefix whitelist.
- **`http:` is rejected.** Plain HTTP was not required by any content.
- **Images** may only reference media inside the item's directory.

## 4. Headings and anchors

- **Levels.** The page owns `<h1>`. Markdown may use `##`–`####`, at the top
  level only, starting at `##`, with no skipped levels.
- **Sections.** Each `##` is a section, and the sidebar is generated from
  the same section list that is rendered. So entries and sections cannot
  disagree.
- **Ids.** One function (`headingSlug`) derives every id: letters and
  digits (any script) are lowercased, other runs become single hyphens, and
  an empty result becomes `section`. Ids are assigned in document order,
  de-duplicated with `-2`, `-3` and so on, also against the ids the page
  already uses (`main`, `{slug}-title`).

## 5. Publication policy

- **Two independent fields.** `development_status` (implemented,
  in_development, proposed) describes the work.
  `publication_status` (draft, published) alone controls output.
- **Filtering happens in one place.** `Site.Definition.siteFrom` filters on
  publication status. Drafts are fully validated but produce no page, card,
  navigation entry, link or media file.
- **Writing.** Writing routes and the "Writing" nav entry exist only if a
  published article does.
- **Media is per item.** Media lives with its content item and is published
  only with it, at `/media/projects/{slug}/…`. Content never needs to edit
  `Site.Assets.allAssets`, and draft media cannot leak through indiscriminate
  copying. Brigid's card art moved from `assets/images/card-brigid.svg` to
  `content/projects/brigid/card.svg`. On the homepage this changes only the
  image URL; the capture is pixel-identical.

## 6. New dependencies

All come from `lts-24.12`, with no `stack.yaml` changes:

| Package | Role |
| --- | --- |
| `commonmark` | CommonMark parser |
| `aeson` | JSON |
| `scientific` | JSON numbers |
| `parsec` | Parser source positions |

Only `commonmark` needed building.

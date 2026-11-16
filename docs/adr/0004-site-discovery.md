# ADR 0004 — Discovery, information architecture and the shared shell (Phase 05)

Status: proposed for owner review, 2026-11-16.

## Context

The owner's page-by-page review found that the Work index wasted space and
offered no way to find a project, that About and Contact were one section,
that the mobile project sidebar was badly composed, that hero-less dossiers
opened with an orphaned image, and that the footer was only a name. The
original plan also gave Phase 05 the canonical URLs, metadata and sitemap.
The site must stay static, deterministic and usable without JavaScript.

## Decisions

1. **A controlled taxonomy.** `category` (one per project) and `topics`
   (up to five) are ids from a small vocabulary in `Site.Taxonomy`; labels
   live only there. `technologies` stay free text but reject duplicates
   (ignoring case) and topic or category labels. The free-text category of
   Phase 02 is rejected with the list of valid ids rather than mapped
   silently: three records were migrated by hand, and a silent mapping
   would hide spelling drift. `topics` is optional, so older records load.

2. **Search is generated data plus a small module.** Each Work index item
   carries `data-category` and `data-search` (title, summary, category,
   technologies and topics, lowercased), written by the generator from the
   same record the card renders. `assets/scripts/work-filter.js` (vanilla,
   no framework, nothing fetched or stored) shows and hides the existing
   cards. The semantics are: category AND every query word, case- and
   whitespace-insensitive. There is no separate index file and no backend.

3. **Progressive enhancement.** Without JavaScript the HTML is a complete
   list and the controls are `hidden`. With scripting available, a
   `@media (scripting: enabled)` rule gives the controls their space from
   the first paint, so revealing them causes no layout shift.

4. **One exception to the no-script rule.** The active-content scan
   (ADR 0001) now accepts exactly
   `<script type="module" src="/assets/scripts/NAME.js"></script>`: no
   other attribute, no inline code. The link checker requires the file to
   be a listed asset, so only reviewed code shipped from `assets/` can
   run. Every other page remains script-free (tested).

5. **About and Contact are separate.** About is the profile page (with the
   tree-and-eclipse emblem). Contact is a homepage section, `/#contact`,
   linked from every page. The hero's secondary button keeps its frozen
   label and now targets `#contact`.

6. **Settings in one module.** The origin, name, thesis, copyright years
   and contact destinations live in `Site.Settings` and are validated
   before every check and build. Contacts are typed (`GitHub`,
   `LinkedIn`, `Email`), so the scheme and host are fixed in code. An
   email is shown only once the owner adds one; nothing is guessed. The
   copyright year is a constant, never the build clock.

7. **The résumé is a file, not configuration.** `content/resume.pdf`, if
   present and valid (a regular file inside `content/`, a `%PDF-`
   signature, at most 10 MiB), is published at `/resume.pdf`, and only
   then do the navigation and footer link to it. It is a new
   `MediaOwner`, `SiteMedia`, published at the site root.

8. **Generated text files are manifest entries.** `sitemap.xml` and
   `robots.txt` are `GeneratedSource` entries derived from the site's
   routes and origin. They go through the same collision checks and
   staged promotion as pages, and the build's exact-tree check covers them.

9. **Metadata without fabricated art.** Every page has a canonical URL,
   `og:*` and `twitter:card` `summary`. No preview image is declared until
   approved artwork exists. The 404 document is `noindex` and has no
   canonical URL.

10. **Navigation scales by modifier, not by changing the approved
    header.** With five or six links, a `page--nav-extended` body class
    stacks each side's links on its own row on phones. The four-link
    header that the real site uses today is byte-for-byte unchanged.

## Consequences

- Adding a project still needs no Haskell. Adding a category or topic is
  a one-line code change, which is intended: the vocabulary is reviewed.
- The site now ships one script. Any second script must be an asset under
  `assets/scripts/` in the same form, or the build fails.
- The search scales to dozens of projects without change. For hundreds, a
  generated JSON index might be worth it; this design leaves room for one.

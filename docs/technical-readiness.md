# Technical readiness note (after the post-Phase 05 remediation)

Date: 2026-11-16. Branch `remediation-05u2`, based on `main` at `91205ea`
(Merge Phase 05).

## Toolchain and Brigid

| Item | Value |
| --- | --- |
| Brigid | `AugmenTab/brigid` at `e0f4d45f4b91a1a381c64845861237d06b3b0803` (core library only), via `stack.yaml` `extra-deps` |
| Brigid escaping | Every attribute value is escaped at serialization (`"`, `'`, `&`, `<`, `>` as numeric references); text nodes likewise. This site does no pre-escaping |
| GHC / resolver | GHC 9.10.3, Stack resolver `lts-24.12` (unchanged) |
| Build image | `ghcr.io/flipstone/haskell-tools:debian-ghc-9.10.3-1e1d10c` pinned by digest (`Dockerfile`) |
| New dependency | `time` (a GHC boot package already in the snapshot) for `Data.Time.Calendar.fromGregorianValid` |

## Build and test status

The verified commands and their results are recorded in the remediation
retrospective (kept locally). In summary:

- `docker compose run --rm site-build stack test`: all 226 tests pass (212
  before the remediation; 14 added in `test/RemediationTests.hs`, and three
  existing assertions changed from expecting a quote to be refused to
  expecting it to be escaped).
- `docker compose run --rm site-build stack exec -- site check`: OK, 7 pages
  and 32 files.
- `docker compose run --rm site-build`: writes 7 pages and 32 files. The
  output is byte-identical to `main` before the remediation (`diff -r`) and
  between repeated builds.
- Browser suite (`docker compose --profile tools run --rm screenshots`):
  `failures: []`. Hero band regression: mean 0.00, worst tile 0.00, PASS.

## Validation boundaries (what the build guarantees)

- **Metadata** (`project.json`, `article.json`) is decoded strictly: unknown,
  missing, null and mistyped fields, unknown enum values, and taxonomy
  violations are errors naming the file and field. Every independent problem
  is reported in one run.
- **Attribute-bound text** (summaries, image and hero alt text) accepts any
  ordinary punctuation, including straight quotes. Brigid escapes it.
- **Dates** must be `YYYY-MM-DD` and a real Gregorian day. They are kept as
  written; nothing reads the build clock.
- **Markdown**: raw HTML (inline and block) is rejected; links must be
  `https://`, a root-absolute site path or a `#fragment`, after entity and
  escape decoding; images must be media in the item's own directory, with
  alt text; heading policy is enforced.
- **Filesystem**: traversal, absolute paths and symlinks that escape
  `content/` or `assets/` are rejected; content sources (`.md`, `.json`) are
  never published.
- **Publication**: drafts produce no page, card, media, sitemap entry or
  metadata, but are still validated.
- **Rendered pages**: every page is checked for structure (doctype, `lang`,
  title, `main`, exactly one `h1`), duplicate ids, links and fragments
  against the manifest, and active content (script-capable elements and
  `on…=` attributes, except the one allowed external module script).
- **Output**: the manifest lists exactly the files written; builds are
  staged and promoted atomically, and a failed build leaves the previous
  output byte-identical.

## Known technical limitations

1. **The active-content scan is a string scan, not an HTML parser.** It is
   sound for this site's output because Brigid escapes `<` and `>` in text
   and attributes, so every literal `<`/`>` is a real tag boundary. It fails
   closed: attribute-bound text that itself reads like a handler (for example
   `x" onclick="y`) is escaped correctly but still refused, so the build
   fails and asks for the text to be reworded.
2. `Site.Validate.attributeValues` decodes only `&amp;`, while Brigid writes
   `&#38;`. No internal link contains `&` today; an internal URL with a
   query string would need this decoder extended.
3. Removing screenshots from the working tree does not shrink Git history;
   a fresh clone still downloads every historical capture. Shrinking it
   would need a history rewrite, which is out of scope and needs an
   explicit owner decision.
4. Captures of animated controls can differ by a few pixels between runs
   (screenshot lands mid-transition). `tools/art/evidence_diff.py` reports
   such differences; they are not regressions when the HTML and CSS are
   unchanged.
5. The full-first-view regression (`regression.py` without `--hero-band`)
   reads 3.97 against the Phase 00 baseline because the Black teaser
   changed by design in Phase 03. The hero band is the gate.

## Dependencies for Phase 06

- Visual QA should compare against `design/references/` (renders 02 and 03)
  and the curated record in `design/proof/`. Fresh captures go to
  `design/proof/latest/`; copy only reviewed files into `design/proof/`.
- Owner decisions still open from Phase 05: the hero label "About &
  contact", taxonomy confirmation, the extended phone header, the
  homepage footer without a contact column, and the 1100px Work grid
  threshold.
- The editorial pass (biography, philosophy, project introductions) is
  separate and must not be mixed into technical work.

## Dependencies for Phase 07 and Cloudflare deployment

- An approved production origin (configured: `https://tylerbaum.dev` in
  `Site.Settings`) and the domain itself.
- Real contact destinations beyond GitHub, and a real `content/resume.pdf`,
  if they are to launch.
- Hosting configuration: HTTPS, response headers (a Content-Security-Policy
  allowing `script-src 'self'` suffices for the one module script), cache
  rules, and `404.html` as the not-found page. Assets are not fingerprinted
  yet, so long cache lifetimes need cache-busting first.
- A release script (build, check, deploy) and an exercised rollback, run
  locally; no cold GHC build on hosted CI.

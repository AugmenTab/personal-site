# Post-Phase 07 update 1: release guard and navigation correction

Date: 2026-11-17. Branch `phase-07-update1`, based on `phase-07`
(`241df75`), so the Phase 06 and 07 commits are preserved. Nothing was
deployed.

## 1. Release guard

`scripts/release.sh deploy --confirm SHA` no longer accepts "an ancestor of
`main`". It now requires all of the following:

- **Not detached:** the current branch is `main`
  (`git symbolic-ref --short HEAD`).
- **Exact commit:** the supplied SHA is the checked-out HEAD.
- **In step with the remote:** local `main` equals the last-fetched
  `origin/main`, compared through local refs only (no fetch and no network
  call). With no `origin/main` ref, it prints a note and continues.
- **Clean tree:** unchanged, with no tracked changes and no untracked
  files.

These safeguards are unchanged:

- the confirmation phrase
- credentials
- full revalidation
- package integrity
- the account check

Guardrail tests are now 54/54 (48 before). New and changed cases:

- accepts a clean `main` checkout;
- rejects a detached HEAD at the SHA;
- rejects an older ancestor checked out detached;
- rejects an older ancestor while `main` is checked out;
- rejects a branch other than `main`;
- rejects a SHA that doesn't match HEAD;
- rejects `main` that differs from `origin/main`;
- makes no network Git calls;
- proceeds with a note when there is no `origin/main` ref.

The dirty-tree and untracked-file cases still pass.

## 2. Permanent Writing index

`/writing/` is always generated.

- **No articles** (the real site today): the heading **Writing** and
  **Coming soon.** There is no list, no grid and no sample entries.
  - It uses the interior layout, with a canonical URL and `og:url` of
    `https://tylerbaum.dev/writing/`, a description, and `aria-current` in
    the nav.
  - It is in the sitemap.
- **With articles** (fixture): the existing list renders, newest first, and
  "Coming soon." disappears.
- **Unchanged:** drafts stay unpublished, and the homepage Writing preview
  stays hidden until a real article exists.

## 3. Final navigation

`Home  Work  Writing  [monogram]  About  Resume  Contact`

- **Writing:** always present.
- **Resume:** the label has no accent and the link is announced as "Resume
  (PDF)". It appears only when `content/resume.pdf` exists, and links
  straight to `/resume.pdf`.
- **Footer:** Work, Writing, About, then Resume when it exists.
- **Phone layout:** every page now has five or more links. At 640 px and
  below the existing stacked phone header takes over, because five links
  do not fit one row at 390 px. That is the Phase 05 layout, verified in
  Phase 06. No CSS rule changed, only a comment.

## Verification

| Check | Result |
| --- | --- |
| Haskell tests | **228/228** (226 updated to the new rules, plus 2 new: the empty Writing page, and the full order with every destination) |
| `site check` | OK: 8 pages, 32 files |
| Docker build | 8 pages, 32 files |
| Browser suite (`capture.py`, phases 03–05) | `failures: []` |
| Phase 06 audit (axe, contrast, focus, keyboard, targets, reflow, no-JS) | `failures: []` |
| `nav_check.py`, both states at 1440, 1280, 768, 390 and 320 px | `failures: []` (`nav-check.json`) |
| Release guardrail tests | **54/54** |
| `release.sh dry-run` (local Cloudflare runtime) | PASS. 41 files; `/writing/` served and in the sitemap |
| **Protected hero band** | **FAIL, by design. See below** |

What `nav_check.py` covers in each state:

- **Real site (no articles, no résumé):**
  - the order is Home, Work, Writing, About, Contact;
  - Writing leads to "Coming soon.";
  - there is no Resume link anywhere, and `/resume.pdf` returns 404.
- **Fixture site (article and PDF):**
  - the order is Home, Work, Writing, About, Resume, Contact;
  - Writing lists the article;
  - Resume appears in the nav and footer as "Resume (PDF)";
  - `/resume.pdf` returns 200 as `application/pdf`, starts with `%PDF-`,
    and the 72,361-byte download matches.
- **Every width:**
  - no link overlaps, overflow or off-screen links;
  - every target is at least 24 px;
  - from tablet width up, Home, Work and Writing sit left of the monogram
    and About, Resume and Contact sit right of it.
- **Links:** every sitemap URL and every internal link crawled returns 200.

### Protected homepage hero regression

`regression.py --hero-band` against the approved Phase 00 baseline:

- mean |dL| 0.17 (limit 1.5);
- worst tile 16.06 at x=576, y=0 (limit 12).

`hero-band-diff.png` shows that the only differing pixels are the
**left-hand nav labels**: HOME and WORK move left to make room for the new
WRITING link. The hero art, name, tagline, disciplines and buttons are
identical.

This follows directly from the required order. **The baseline was not
updated.** Re-approving `design/regression/desktop-1440x900.png` with the
new navigation is the owner's decision.

## Screenshots

| File | Shows |
| --- | --- |
| `real-{desktop,tablet,mobile,narrow}-header.png` | Real site header, five links |
| `fixture-{desktop,mobile,narrow}-header.png` | Fixture site header, six links (with Resume) |
| `real-desktop-writing.png`, `real-mobile-writing.png` | The "Coming soon." Writing page |
| `fixture-desktop-writing.png` | The Writing index with the fixture article |
| `hero-band-diff.png` | The hero-band regression diff (nav labels only) |

Not changed:

- homepage, About, philosophy and project copy;
- art and heroes;
- no new features;
- no deployment.

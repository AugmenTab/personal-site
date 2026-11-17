# Phase 07 evidence: release engineering (Cloudflare Workers Static Assets)

Date: 2026-11-17.

- **Commits:** starting commit `9fa8956` (Phase 06); code commit `86db0ba`
  on branch `phase-07`.
- **Runbook:** [`docs/operations/deployment.md`](../../../docs/operations/deployment.md).
- **What was not done:** nothing has been deployed, and no Cloudflare
  account, token, Worker, domain or DNS record was created, read or
  changed.
- **Labels:** all provider results below come from Cloudflare's own local
  runtime (`wrangler dev --local`, workerd) or from Wrangler's offline
  `--dry-run`, and are labelled as such.

## Files

| File | What it shows |
| --- | --- |
| `help.txt` | `scripts/release.sh help` |
| `test.log` | The 226 Haskell tests, run by `release.sh check` |
| `site-check.log` | `site check`: 7 pages and 32 files validated |
| `build.log` | Fresh build into `dist/` |
| `manifest.txt` | `site manifest`, the 39-file publish allowlist |
| `check-dist.log` | dist/ equals the manifest plus the ownership marker |
| `package.log`, `SHA256SUMS`, `release.json` | The 40-file package, per-file hashes, and metadata for commit `86db0ba` (clean tree, GHC 9.10.3, Stack 3.7.1, Wrangler 4.156.2) |
| `wrangler-dry-run.log` | `wrangler deploy --dry-run --autoconfig=false`, accepted |
| `smoke-local.txt` / `.json` | Smoke tests against the local Workers runtime: PASS |
| `emulation.log` | The local runtime's log during the smoke test |
| `verify.log` | Package hashes re-verified after the dry run |
| `guardrail-tests.txt` | 48 positive and negative release-guard tests: all pass |
| `smoke-negative-control-nginx-preview.txt` | The same smoke test against the raw development preview (nginx serving `dist/`): it **fails**, as it should (see below) |

## Results

### Clean build, tests and validation

- 226/226 Haskell tests pass.
- `site check` OK.
- Fresh build: 7 pages and 32 asset, media and generated files.

### Fresh-checkout reproducibility

- The commit was cloned into an ignored folder and built there with
  `docker compose -f <clone>/compose.yaml run --rm site-build`.
  - The clone had its own `.stack-work/` and recompiled all 24 modules.
  - Dependencies came from the shared Stack volume, a warm cache, which
    the plan accepts.
- `diff -r` against the working tree's `dist/` showed **no differences**.
- The build depends on no untracked file.

### Determinism

- An uncommitted and a committed package of the same sources had the same
  package digest: `ab563c0c…4845`.
- The guardrail tests package twice and compare `SHA256SUMS` byte for
  byte.

### Allowlist verification

- `dist/` holds exactly the 39 manifest files plus `.personal-site-output`.
- The package holds exactly those 39 plus `_headers`.
- The marker is excluded, and every copy matches its source hash.

### Wrangler dry run (offline; no credentials)

The configuration is accepted. Wrangler reports "Read 56 files from the
assets directory": the 40 files plus 16 directories. `--dry-run: exiting
now.`

### Local routing and HTTP (Cloudflare's runtime, locally)

- **Pages:** `/`, `/work/`, `/work/black/`, `/work/brigid/`,
  `/work/lockdown/` and `/about/` return 200 with their own titles,
  descriptions and canonical URLs.
- **Files:** `sitemap.xml`, `robots.txt` and all 32 other packaged files
  return 200 with the right content types.
- **Unknown paths:** 404, with the custom page.
- **Redirects:** `/work`, `/about`, `/work/black`, `/index.html` and
  `/work/index.html` each give one 307 to the canonical form. There are no
  loops.
- **Leak probes:** 20 of 20 return 404. These include the marker,
  `_headers`, `content/` JSON and Markdown, `.git`, `.env`,
  `wrangler.toml`, the README and the evidence files.

### Security headers

On every page, asset and 404 response the headers exactly match
`release/_headers`:

- the deny-by-default CSP
- `X-Content-Type-Options`
- `Referrer-Policy`
- `X-Frame-Options`
- `Permissions-Policy`
- `Cross-Origin-Opener-Policy`

Browsers at 1440 px and 390 px recorded no CSP violations and no console
errors.

### Browser checks

- Work search "haskell" narrows 3 cards to 2, and each category chip
  narrows to 1.
- The compact project index opens with 8 links.
- Without JavaScript, all 3 cards show, no controls show, and every
  homepage section is present.

### Cache

`Cache-Control: public, max-age=0, must-revalidate` plus an `ETag`: the
platform default. Nothing is immutable.

### Negative control

Against the development nginx preview, which serves `dist/` directly, the
same smoke test fails on three counts:

- missing security headers
- `/index.html` not redirecting
- **`/.personal-site-output` answering HTTP 200**

The last is exactly the leak that exact-allowlist packaging prevents.

### Problems the dry run found and fixed before anything shipped

1. **Compatibility date.**
   - The plan's suggested `compatibility_date` of 2026-11-16 is newer than
     the pinned runtime supports (2026-11-09), so `wrangler dev` refused
     to start.
   - Fixed: set to 2026-11-09, with a comment.
2. **CA certificates.**
   - The slim Node image has no CA bundle, which workerd needs.
   - Fixed: added `ca-certificates`.
3. **`upgrade-insecure-requests`.**
   - Over plain HTTP, the directive made the browser request every
     same-origin URL over HTTPS, breaking the local test.
   - It does nothing on an HTTPS-only site with relative URLs, so it was
     removed.
4. **`img-src 'self'` blocked the `--diamond` ornament.**
   - The CSP listener caught it: the ornament is an inline SVG data URI in
     the stylesheet.
   - Fixed: `img-src 'self' data:`, images only.

## A. Technical deployment readiness: **PASS (local), with provider steps NOT VERIFIED**

| Requirement | Status | Evidence |
| --- | --- | --- |
| Tested release package | PASS | `package.log`, `SHA256SUMS`, `release.json`, guardrail tests |
| Configuration validates | PASS (offline) | `wrangler-dry-run.log` |
| Routing, 404 and headers in Cloudflare's runtime | PASS (local workerd) | `smoke-local.txt` |
| Smoke tests against a real deployment | NOT VERIFIED | No account or credentials were available. Run `scripts/release.sh smoke --url …` after the first deploy |
| Deploy command | Control flow PASS (fake Wrangler); provider behaviour NOT VERIFIED | `guardrail-tests.txt`. The flags were checked against the pinned Wrangler's `--help` |
| Rollback | Procedure documented; wrapper PASS (fake Wrangler); NOT VERIFIED on Cloudflare | Runbook section 9. **Rollback has not been tested on Cloudflare** |

## B. Public launch readiness: **NOT READY** (owner decisions outstanding)

From the PRD (section 10) and the implementation plan (Phase 07 exit gate):

| Requirement | State |
| --- | --- |
| At least 4 real project dossiers | **3 published** (Black, Brigid, Lockdown). Needs a fourth real project or an approved scope revision. None was invented |
| Final copy reviewed by the owner | **Outstanding.** The homepage introduction, the Black teaser, Engineering Philosophy and the Contact copy are still marked `DraftCopy` in source. The About biography and the project introductions also await review. The "About & Contact" hero CTA wording is reserved for the owner |
| Professional contact destinations | **GitHub only** is configured (`src/Site/Settings.hs`). Email and LinkedIn are omitted cleanly until configured. No address was invented |
| Résumé | **Not supplied.** No link is shown anywhere, which is correct until `content/resume.pdf` exists |
| Writing | None published, so no section is shown, which is allowed |
| Social previews | `og:title`, `og:description`, `og:url`, `og:type` and a `summary` card are present. There is **no `og:image`**: a share image is an owner and design decision. None was invented |
| Hero artwork for Black and Brigid | Still not delivered (README, "Hero artwork"). The dossiers open without heroes by design |
| Production Cloudflare account and domain | **Not configured** (owner action; runbook section 3) |
| Production release authorized | **No** |
| Live smoke tests passed | Not run (nothing is live) |
| Real rollback verified | **No** |
| Safari and Firefox | Not verified (Phase 06 browser matrix) |

**The site has not been launched, and this phase does not claim it has.**

## Phase 07 acceptance gate (technical)

- [x] Release commands exist and are documented (`help.txt`, runbook).
- [x] Clean build succeeds; a fresh checkout reproduces it.
- [x] Haskell tests pass (226).
- [x] Site validation passes.
- [x] Public package contains only intended files (40: the manifest plus
      `_headers`).
- [x] The ownership marker is excluded (package check, guardrail test,
      leak probe).
- [x] Wrangler configuration validates (dry run).
- [x] Static routing and trailing slashes behave correctly (local
      runtime).
- [x] Custom 404 returns HTTP 404.
- [x] Security headers are tested (exact match, plus a browser CSP
      listener).
- [x] Cache strategy is documented and safe for current asset names (no
      immutable).
- [x] Release manifest records the exact source revision (`release.json`
      `commit`; uncommitted trees are labelled `UNCOMMITTED`).
- [x] Dry run does not mutate production. It uses the credential-free
      service and is tested with a fake Wrangler.
- [x] Deployment requires explicit approval: `--confirm <SHA>` plus a
      typed phrase.
- [x] Rollback procedure is documented (wrapper requires `--confirm` plus
      a typed phrase).
- [x] Release guards have positive and negative tests (48).
- [x] No automatic `main` deployment exists (no `.github/` workflows).
- [x] No unapproved copy or artwork changes. Phase 07 changed no content,
      CSS or art.

## Public launch gate

None of these items is checked yet:

- [ ] Final copy reviewed by owner
- [ ] Required published-project count or an approved scope revision
- [ ] Professional contact destinations verified
- [ ] Résumé and Writing publication decisions settled
- [ ] Production Cloudflare account and domain configured
- [ ] Production release explicitly authorized
- [ ] Live smoke tests passed
- [ ] Real rollback capability verified

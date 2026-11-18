# Deployment and release operations

The site is hosted on **Cloudflare Workers Static Assets** as an assets-only
Worker named `tylerbaum`. The Haskell generator is the only thing that
produces the site. Cloudflare serves the files it produced, packaged by
`scripts/release.sh`, and nothing builds on Cloudflare or in CI.

Production publication is always a deliberate, manual act by the owner:

```sh
scripts/release.sh deploy --confirm <full commit SHA>
```

Nothing else publishes: not a push to `main`, not a build, and not a test
or a dry run.

> **Status (Phase 07):** the tooling is complete and tested locally,
> including local Cloudflare emulation. **No Cloudflare account, token,
> Worker, domain or DNS record has been created or changed**, and nothing
> has been deployed. Operations that need a real account are marked
> *untested on Cloudflare* below.

## Contents

1. [Prerequisites](#1-prerequisites)
2. [Cloudflare authentication](#2-cloudflare-authentication)
3. [Account and domain setup](#3-account-and-domain-setup)
4. [Running tests](#4-running-tests)
5. [Packaging](#5-packaging)
6. [Dry run](#6-dry-run)
7. [Manual production release](#7-manual-production-release)
8. [Post-release verification](#8-post-release-verification)
9. [Rollback](#9-rollback)
10. [Recovery from partial failure](#10-recovery-from-partial-failure)
11. [Future manually triggered CI deployment](#11-future-manually-triggered-ci-deployment)
12. [Known provider-specific limitations](#12-known-provider-specific-limitations)

Reference: [Security headers](#security-headers), [Caching](#caching),
[HTTPS and HSTS](#https-and-hsts), [What gets published](#what-gets-published).

---

## 1. Prerequisites

- Docker with Compose v2, and Git. Nothing else is needed on the host.
  - Haskell runs in the `site-build` image.
  - Packaging and smoke tests run in the tools image.
  - Wrangler runs in its own image.
- The images build on first use:

  ```sh
  docker compose build site-build
  docker compose --profile release build release wrangler
  ```

Pinned versions:

| Tool | Version | Pinned in |
| --- | --- | --- |
| Wrangler | 4.156.2 | `release/package.json` and `release/package-lock.json` (integrity hashes) |
| Node (Wrangler only) | 22.12.0, bookworm-slim, by digest | `release/Dockerfile` |
| GHC / Stack | 9.10.3 / 3.7.1 | `Dockerfile` (by digest) |
| Workers compatibility date | 2026-11-09 | `wrangler.toml` |

To upgrade Wrangler:

1. Change both `package.json` and the lockfile. To regenerate the
   lockfile:

   ```sh
   docker run --rm -v "$PWD/release:/r" -w /r node:22.12.0-bookworm-slim npm install --package-lock-only --ignore-scripts
   ```

2. Rebuild the image.
3. Run `scripts/release.sh dry-run`.

The compatibility date must not be later than the newest date the pinned
runtime supports. Otherwise `wrangler dev` refuses to start, and the dry run
fails.

## 2. Cloudflare authentication

Deployment uses an **API token** from the environment. It never uses an
interactive browser login, and it never uses a token stored in a file in
this repository.

1. In the Cloudflare dashboard, go to **My Profile → API Tokens → Create
   Token** and start from **Custom token**.
2. Give it the narrowest permissions that work. As a starting point:
   - **Account → Workers Scripts → Edit**: upload versions, deploy and
     roll back.
   - **Account → Account Settings → Read** and **User → Memberships →
     Read**: lets `wrangler whoami` show the accounts the token can see,
     which the deploy uses to verify the account.
   - **Account resources:** only the account that will own the site.
   - No zone or DNS permissions. Domains are attached in the dashboard by
     hand (section 3), never by the release script.

   *Untested on Cloudflare:* this exact permission set has not been
   exercised. If a command reports a missing permission, add only the one
   it names.
3. Set an expiry date and, if you like, IP filtering.
4. Export the token and account ID in the shell that runs the release:

   ```sh
   export CLOUDFLARE_API_TOKEN=...      # never commit, never paste into files in the repo
   export CLOUDFLARE_ACCOUNT_ID=...     # Account ID from the dashboard sidebar
   ```

How the credentials are handled:

- `scripts/release.sh` checks only that both variables are set. It never
  prints, logs or records their values.
- Only the `wrangler-deploy` Compose service receives them, and only
  `deploy`, `versions` and `rollback` use that service.
- The `wrangler` and `wrangler-dev` services that run dry runs and local
  emulation get no credentials. They see only `wrangler.toml` and the
  package, never the repository, so a stray `.env` cannot reach them.
- `.env`, `.env.*` and `.dev.vars` are ignored by Git. If you keep
  credentials in a local `.env` for Compose, it stays on your machine.

The deploy refuses if `wrangler whoami` with the token does not list
`CLOUDFLARE_ACCOUNT_ID`. That catches a token for the wrong account.

## 3. Account and domain setup

These are owner actions. The release script never performs them.

1. **The Worker.** The first `deploy` creates the `tylerbaum` Worker in the
   account. No dashboard step is needed beforehand.
2. **workers.dev.** By default, Cloudflare also serves a deployed Worker at
   `https://tylerbaum.<your-subdomain>.workers.dev`.
   - That address is useful for the first deploy: smoke-test it before
     attaching the real domain (section 7).
   - Pages declare `https://tylerbaum.dev` as canonical, so the
     workers.dev copy does not compete in search.
   - To turn it off later: Worker → **Settings → Domains & Routes**, then
     disable workers.dev. Do not add `workers_dev` to `wrangler.toml`; the
     release script rejects that file if it changes routing.
3. **The custom domain `tylerbaum.dev`.** This needs `tylerbaum.dev` to be
   a zone in the same Cloudflare account.
   1. Go to Worker `tylerbaum` → **Settings → Domains & Routes → Add →
      Custom Domain** and enter `tylerbaum.dev`.
   2. Cloudflare then creates the DNS record and certificate for the apex.
      - It refuses if a conflicting A, AAAA or CNAME record already exists
        on the apex. Review that record before removing it.
      - According to Cloudflare's documentation, attaching a Worker custom
        domain does not touch MX and TXT records (mail, verification).
        Check them before and after, and do not delete them.
4. **`www`.** Optional, and later. To send `www.tylerbaum.dev` to the apex,
   add a **Redirect Rule** (or a second custom domain plus a rule) in the
   dashboard.
   - Do not create `www` records that conflict with existing DNS or mail
     configuration.
   - It is not part of this repository.
5. **HTTPS** is automatic for custom domains. For HSTS, see
   [HTTPS and HSTS](#https-and-hsts).

The repository deliberately contains no `account_id`, `routes`, custom
domain or `workers_dev` setting. `release.sh` refuses a `wrangler.toml`
that adds any of them, so a deploy can never move DNS or traffic routing as
a side effect.

## 4. Running tests

| What | Command |
| --- | --- |
| Haskell tests | `docker compose run --rm site-build stack test` |
| Content, routes and rendered-page validation | `docker compose run --rm site-build stack exec -- site check` |
| Release guardrail tests: 54 cases with fake `docker`, `git` and `wrangler`, which never reach Docker, Git, the network or Cloudflare | `docker compose --profile release run --rm -T release sh tests/release/run-tests.sh` |
| Browser suites (Phases 03 to 06) | see the README, "Screenshots" and "Accessibility, performance and deterministic captures" |

`scripts/release.sh check` runs the first two, plus:

- a fresh build;
- a dist/ inventory check: dist/ must equal the generator's manifest plus
  its ownership marker;
- publishable-path and leak checks.

It stops at the first failure.

## 5. Packaging

```sh
scripts/release.sh package
```

1. Runs `check`.
2. Asks the generator for its manifest:

   ```sh
   site manifest
   ```

   This prints every output file the site publishes, one per line, and
   nothing else.
3. Rebuilds `.release/public/` from scratch, copying **exactly** those
   files from `dist/` plus `release/_headers`.
   - It fails if dist/ has any extra or missing file.
   - It fails if a manifest path is hidden (such as
     `.personal-site-output`), provider-reserved, a source format (`.md`,
     `.json`, `.hs`, `.toml`, …) or in a source directory.
   - It fails if a text file contains a build-machine path or secret
     marker.
   - It fails if any copy differs from its source.
4. Writes `.release/evidence/`:

   | File | Contents |
   | --- | --- |
   | `SHA256SUMS` | per-file hashes, sorted; deterministic for the same tree |
   | `release.json` | see below |
   | `*.log` | logs of every step |

   `release.json` records:
   - the commit;
   - whether the tree was clean;
   - GHC, Stack and Wrangler versions, and the build image ID;
   - file count, total bytes, the inventory, and each file's size and hash;
   - the package digest (the SHA-256 of `SHA256SUMS`);
   - the validations that passed.

A build from a working tree with uncommitted or untracked changes is
labelled **`UNCOMMITTED`**, never with the HEAD commit, and cannot be
deployed.

`.release/` is ignored by Git, and none of its evidence is published.

`scripts/release.sh verify` re-hashes the package against `SHA256SUMS`. It
fails on any added, removed or changed file.

**The generator's own output step is not atomic.** `site build` renders
into a staging directory and then moves entries into `dist/`, restoring the
previous output if the move fails. It is a careful sequence of moves with
rollback, not one atomic filesystem swap. Packaging always reads a
completed `dist/` after a successful build.

### What gets published

There are 42 files: the generator's 41 plus `_headers`. Since post-Phase 07
update 1, `writing/` is always published, and the owner's résumé is
published at `/resume.pdf`.

| Group | Files |
| --- | --- |
| Pages | 8 HTML pages: `index.html`, `404.html`, `about/`, `work/`, `work/black/`, `work/brigid/`, `work/lockdown/`, `writing/` (a "Coming soon." page until an article is published) |
| Generated | `sitemap.xml`, `robots.txt` |
| Assets | 26 files under `assets/`: brand, fonts and their OFL licences, images, `styles/site.css`, `scripts/work-filter.js` |
| Media | 4 project SVGs under `media/` |
| Résumé | `resume.pdf`, copied from `content/resume.pdf`; linked from the nav and footer, not listed in the sitemap |
| Provider | `_headers`, read by Cloudflare and not served |

These are never published:

- the ownership marker;
- `content/` sources, Markdown, JSON;
- Docker, Stack, Git and `.local/` files;
- evidence, logs and credentials.

## 6. Dry run

```sh
scripts/release.sh dry-run
```

1. Checks `wrangler.toml`:
   - the Worker name;
   - assets directory `./.release/public`;
   - `not_found_handling = "404-page"`;
   - no account, routes, domains, `workers_dev` or script.
2. Runs `package`.
3. Runs `wrangler deploy --dry-run --autoconfig=false` in the
   credential-free container. Wrangler validates the configuration and the
   asset directory, uploads nothing, and prints `--dry-run: exiting now.`
4. Starts `wrangler dev --local`, Cloudflare's own runtime (workerd), on
   the package, and runs the smoke tests (section 8) against it:
   - every page and file;
   - the 404 page and its status;
   - trailing-slash redirects;
   - the exact packaged headers;
   - leak probes;
   - browser checks at desktop and phone widths, including CSP-violation
     and console-error capture, and the no-JavaScript experience.
5. Re-verifies the package hashes.

It needs no credentials and changes nothing on Cloudflare. Evidence is in
`.release/evidence/` (`wrangler-dry-run.log`, `smoke-local.txt` and
`.json`, `emulation.log`).

## 7. Manual production release

Run all of this from a clean checkout of `main`:

```sh
git switch main
git pull                                      # bring main up to date
git status                                    # must be clean: no changes, no untracked files
scripts/release.sh dry-run                    # optional but recommended
export CLOUDFLARE_API_TOKEN=... CLOUDFLARE_ACCOUNT_ID=...
scripts/release.sh deploy --confirm "$(git rev-parse HEAD)"
```

`deploy --confirm SHA` does the following, in order, and refuses at the
first failure:

1. **Preconditions:**
   - `SHA` is a full 40-character commit that exists;
   - the current branch is `main` (a detached HEAD is refused, even at a
     commit that appears in `main`'s history), and `SHA` is its checked-out
     tip, so an older ancestor of `main` cannot be deployed;
   - local `main` equals the last-fetched `origin/main`.
     - The comparison uses local refs only. It makes no network request,
       so run `git fetch` first for an up-to-date comparison.
     - With no `origin/main` ref, the deploy prints a note and continues;
   - no tracked changes and no untracked files;
   - the configuration passes the checks above;
   - both credential variables are set.
2. **Full revalidation.** It runs `package`: tests, `site check`, a fresh
   build, the manifest inventory and staging. The package must record
   exactly `SHA` and a clean tree, and its hashes are verified.
3. **Account.** `wrangler whoami` must list `CLOUDFLARE_ACCOUNT_ID`. The
   current deployments are saved to `deployments-before.json`, which
   provides the known-good version for rollback.
4. **Confirmation.** You type the phrase it prints, such as
   `deploy-tylerbaum-0123456789ab`.
   - Without a terminal, `RELEASE_NONINTERACTIVE_CONFIRM` must hold that
     exact phrase.
5. **Deploy.** It runs:

   ```sh
   wrangler deploy --autoconfig=false --strict --tag <sha12> --message "release <sha> package <digest>"
   ```

   `--strict` refuses to overwrite conflicting remote changes, such as
   edits made in the dashboard.
6. **Record.** It appends a line to `.release/evidence/deployments.log`
   with the timestamp, commit, new version ID, previous version ID and
   package digest.
7. **Smoke tests.** It tests `https://tylerbaum.dev`, or
   `RELEASE_SMOKE_URL` if that is set.
   - For a first deploy before the custom domain is attached, set
     `RELEASE_SMOKE_URL=https://tylerbaum.<subdomain>.workers.dev`.
   - On failure it prints the exact rollback command and exits 1.

*Untested on Cloudflare:* steps 3, 5 and 7 against a real account. Their
control flow is covered by the guardrail tests with a fake Wrangler.

## 8. Post-release verification

```sh
scripts/release.sh smoke --url https://tylerbaum.dev/      # add --no-browser to skip Playwright
```

This works against any URL: the local emulation, workers.dev, or
production. If a package exists locally, the test also checks that every
packaged file is served and that the headers match `release/_headers`
exactly.

**HTTP checks:**

- every sitemap page and every packaged or referenced file returns 200;
- correct content types;
- an unknown URL returns 404 with the custom page;
- `/work`, `/about`, `/index.html` and similar redirect once to the
  canonical form, with no loops;
- security headers are present and CSP has no `unsafe-*`;
- no `immutable` caching;
- 20 leak probes all return 404: the marker, `_headers`, sources, `.git`,
  `.env`, evidence and others.

**HTML checks:**

- titles and meta descriptions;
- canonical and `og:url` are `https://tylerbaum.dev` plus the path;
- internal links and fragments resolve;
- the homepage has `#contact`;
- Work links every published project.

**Browser checks** (Playwright, desktop and 390 px):

- no console errors or CSP violations;
- no horizontal overflow;
- nav to Work works;
- search and every category chip narrow the list;
- the compact project index opens;
- without JavaScript, all project cards show, no inert controls show, and
  every homepage section is present.

Also, by hand:

- a social preview, by pasting the URL into a link-preview tool;
- a quick look in Safari and Firefox (not automated; see the Phase 06
  browser matrix).

## 9. Rollback

Cloudflare keeps previous Worker versions. A rollback makes an earlier
version serve 100% of traffic again. According to Cloudflare's
documentation, static assets belong to the version they were uploaded
with, so a rollback restores that version's files too. This has not been
verified here; see the note at the end of this section.

1. **Identify what is live.** Run `scripts/release.sh versions`, which is
   read-only and runs `wrangler deployments list`. Match the version to its
   commit in `.release/evidence/deployments.log`, or in the version
   message, which starts `release <sha>`, or the tag, which is the first 12
   characters of the SHA.
2. **Identify the previous known-good version.** Use the `previous=`
   column of the last line of `deployments.log`, or the list above.
3. **Record it.** Note both version IDs and their commits in the incident
   notes.
4. **Roll back, deliberately:**

   ```sh
   scripts/release.sh rollback <VERSION_ID> --confirm
   ```

   It refuses without `--confirm`, credentials, a well-formed version ID, a
   matching account and the typed phrase `rollback-tylerbaum-<VERSION_ID>`.
   It then runs:

   ```sh
   wrangler rollback <VERSION_ID> --message ... --yes
   ```

   and appends to `deployments.log`.
5. **Confirm** the previous version is serving: run
   `scripts/release.sh versions` and check the 100% entry.
6. **Re-run the smoke tests.** The wrapper does this automatically, without
   the browser, and `scripts/release.sh smoke --url https://tylerbaum.dev/`
   gives the full set.
7. **Report:** what failed, which version was restored, the smoke result,
   and the fix plan.

Nothing rolls back automatically: a failed post-deploy smoke test only
prints the command.

*Untested on Cloudflare:* the rollback has been exercised only against the
fake Wrangler (guardrail tests). The command syntax was checked against
the pinned Wrangler's `rollback --help`. No disposable test Worker or
account was available, so **rollback has not been tested on Cloudflare**.
Before relying on it, test it on a throwaway Worker or a first workers.dev
deploy: deploy, deploy again, roll back, then smoke-test.

## 10. Recovery from partial failure

| Where it stopped | State | What to do |
| --- | --- | --- |
| Before "Deploy": tests, build, packaging, account check or confirmation | Production untouched | Fix the cause and run `deploy` again |
| During `wrangler deploy` (upload or network error) | Wrangler uploads assets, then creates and deploys a version. If it failed before deploying, the previous version is still live | Check with `scripts/release.sh versions`. If the old version is still at 100%, simply re-run `deploy`. If the new version is live, continue as below |
| After deploy, before the record was written (a crash) | New version live, `deployments.log` incomplete | `scripts/release.sh versions`: the newest version's message names the commit. Add the line to `deployments.log` by hand. Run `smoke` |
| Smoke tests failed after deploy | New version live, possibly broken | The script prints `rollback <previous> --confirm`. Roll back first, then investigate with the evidence in `.release/evidence/` |
| `--strict` refused (remote changes) | Production untouched | Someone changed the Worker outside this repository (the dashboard). Find out what, decide, and do not bypass with a force flag |
| Local `dist/` broken by an interrupted build | Production untouched | The generator refuses to continue after an interrupted promotion. Follow its message, or remove `dist/` and rebuild |

## 11. Future manually triggered CI deployment

**Decision: deferred. There is no workflow in this repository.** Nothing
deploys on push or merge, and that must stay true.

Why:

- **A cold build is expensive.** A cold Haskell build of the dependency
  tree, including Brigid and its generators, takes about 7.5 minutes even
  locally with Docker (README, "Builds").
- **A hosted runner would pay that every time.** It would need either that
  cost on every run or a large Stack-cache upload and download cycle whose
  benefit has not been measured.
- **The local path already works.** It is fully validated and
  reproducible.

If it is added later, it must:

- use `workflow_dispatch` only, with an explicit `commit` input that must
  equal a commit on `main` or an approved release tag;
- run in a protected `production` GitHub environment with required
  reviewers.
  - Check that required-reviewer protection is actually enabled in the
    repository settings. Naming the environment is not enough.
- set `concurrency: production-deploy` with `cancel-in-progress: false`;
- keep the token and account ID as environment secrets;
- run exactly `scripts/release.sh package`, then `deploy --confirm
  ${{ inputs.commit }}`, with `RELEASE_NONINTERACTIVE_CONFIRM` set from the
  input;
- upload `.release/evidence/` as a workflow artifact;
- measure first: one run with a cold cache and one with a restored Stack
  cache, recording time and cache size, before committing to it.

## 12. Known provider-specific limitations

- **Trailing slashes.** `html_handling = "auto-trailing-slash"` answers
  `/work` with a **307** (temporary) redirect to `/work/`, as observed in
  the local runtime.
  - `/404.html`, `/index.html` and similar redirect to their extensionless
    forms.
  - The generator's links already use the canonical slash forms, so
    visitors do not normally hit these redirects.
- **404 handling.** `not_found_handling = "404-page"` serves the nearest
  `404.html` with status 404 for any unknown path. There is no
  single-page-app fallback.
- **`_headers`.** It applies to static asset responses, including the 404
  page. Cloudflare parses it and does not serve it (verified locally: 404).
  Header rules are limited in number and line length by the platform; this
  file uses one rule.
- **Local emulation differs from production:**
  - it runs over plain HTTP, so Chrome ignores
    `Cross-Origin-Opener-Policy` there and logs a warning, which the smoke
    test tolerates only for `http://` URLs;
  - there is no edge cache;
  - there is no compression negotiation identical to the edge.
- **Version skew.** Asset names are not fingerprinted (see
  [Caching](#caching)). During and just after a deploy, a visitor holding
  HTML from the previous version may fetch the new `site.css` or
  `work-filter.js`.
  - Pages revalidate on every load, so this window is one page view.
  - CSS and JS changes should be backwards-compatible with the previous
    HTML for one release, or accepted as a momentary cosmetic glitch.
  - A rollback restores assets with the version, so asset URLs stay valid
    in both directions.
- **workers.dev and preview URLs** remain reachable unless disabled in the
  dashboard (section 3).

---

## Security headers

`release/_headers` is copied into the package and applies to `/*`:

| Header | Value | Why |
| --- | --- | --- |
| `Content-Security-Policy` | `default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'; object-src 'none'` | Exactly what the site uses: same-origin CSS, fonts, images and one module script. `data:` images are allowed because the stylesheet's `--diamond` ornament is an inline SVG data URI; images cannot run script. There is no `unsafe-inline` or `unsafe-eval`. There are no inline scripts, styles or `style=` attributes in any page (checked) |
| `X-Content-Type-Options` | `nosniff` | Types must be declared |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | Outbound links (GitHub) get the origin only |
| `X-Frame-Options` | `DENY` | Legacy companion to `frame-ancestors 'none'` |
| `Permissions-Policy` | camera, microphone, geolocation, payment, USB, sensors and topics all `()` | The site uses none of them |
| `Cross-Origin-Opener-Policy` | `same-origin` | Isolates the browsing context |

Verification:

- In the local Cloudflare runtime, every page, asset and 404 response
  carries exactly these values.
- Browsers at desktop and phone widths recorded no CSP violation and no
  console error.
- `upgrade-insecure-requests` was tried and removed. It does nothing on an
  HTTPS-only site whose URLs are all relative, and it broke the HTTP-only
  local emulation by upgrading every same-origin request.
- The first CSP (`img-src 'self'`) was caught blocking the diamond ornament
  by the smoke test's CSP listener, before anything shipped.

## Caching

The v1 policy is Cloudflare's default for static assets: an `ETag` on every
response, with browsers revalidating, observed locally as
`Cache-Control: public, max-age=0, must-revalidate`. `_headers` sets no
`Cache-Control`.

- **HTML** is never stale across releases.
- **CSS, JavaScript, fonts and images** keep stable names
  (`/assets/styles/site.css` and so on). A long `max-age` or `immutable`
  would let browsers keep an old stylesheet beside new HTML for up to a
  year, so **there is deliberately no immutable or long-lived caching on
  `/assets/*`**. The smoke test fails if `immutable` ever appears.
- **Cost:** one conditional request per asset per page view, answered by
  304 with no body. That is acceptable at this site's size: 42 files,
  about 672 KiB.
- **Later:** fingerprinted asset names (a content hash in the file name,
  with the generator rewriting references and the manifest and tests
  updated together) would make long immutable caching safe. That is a
  generator change for a later phase, not part of v1.

## HTTPS and HSTS

- **HTTPS** is Cloudflare-managed and automatic for the custom domain.
- **HSTS is not enabled yet**, deliberately.
  - `.dev` is already on the browser HSTS preload list as a TLD, so
    browsers will only ever use HTTPS for `tylerbaum.dev` regardless.
  - A site-level `Strict-Transport-Security` header adds little for the
    apex, and `includeSubDomains` would bind every future subdomain to
    HTTPS.
  - Decide after the domain is live and HTTPS is confirmed. If enabled, add
    `Strict-Transport-Security: max-age=31536000` (no `preload`, and
    `includeSubDomains` only after reviewing subdomains) to `_headers`,
    and run a dry run.
- **Do not submit to the HSTS preload list.**

#!/bin/sh
# Release guardrail tests (Phase 07). Run inside the tools container:
#
#   docker compose --profile release run --rm -T release sh tests/release/run-tests.sh
#
# Each test copies scripts/release.sh, wrangler.toml, release/_headers and
# tools/release/package.py into a fresh sandbox, puts fake `docker`, `git`
# and `wrangler` first on PATH (tests/release/fakes), and runs the real
# script. Packaging (package.py) runs for real; the build, Git, Wrangler and
# smoke tests are simulated. Nothing here can reach Docker, Git, the network
# or Cloudflare.
set -u

REPO=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
FAKE_BIN="$REPO/tests/release/fakes"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
PASSED=0
FAILED=0
SHA=0123456789abcdef0123456789abcdef01234567
OTHER=89abcdef0123456789abcdef0123456789abcdef
ACCOUNT=0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f

# A tiny generator output: two pages, one stylesheet, the ownership marker.
FIXTURE="$WORK/fixture"
mkdir -p "$FIXTURE/dist/assets/styles"
printf '<!doctype html><title>Home</title>\n' >"$FIXTURE/dist/index.html"
printf '<!doctype html><title>Page not found</title>\n' >"$FIXTURE/dist/404.html"
printf 'body { color: #fff; }\n' >"$FIXTURE/dist/assets/styles/site.css"
printf 'personal-site-output v1\n' >"$FIXTURE/dist/.personal-site-output"
printf '404.html\nassets/styles/site.css\nindex.html\n' >"$FIXTURE/manifest.txt"

sandbox() {
  N=$((N + 1))
  BOX="$WORK/box$N"
  mkdir -p "$BOX/scripts" "$BOX/release" "$BOX/tools/release"
  cp "$REPO/scripts/release.sh" "$BOX/scripts/"
  cp "$REPO/wrangler.toml" "$BOX/"
  cp "$REPO/release/_headers" "$BOX/release/"
  cp "$REPO/tools/release/package.py" "$BOX/tools/release/"
  LOG="$BOX/calls.log"
  OUT="$BOX/out.txt"
  : >"$LOG"
}
N=0

# run NAME=VALUE... -- ARGS...: run release.sh in the sandbox; sets RC.
# Assignments are exported inside a subshell, so they never leak between
# tests and values may contain spaces.
run() {
  RC=0
  (
    cd "$BOX" || exit 99
    export PATH="$FAKE_BIN:$PATH" FAKE_BIN="$FAKE_BIN" FAKE_LOG="$LOG" FAKE_FIXTURE="$FIXTURE"
    export FAKE_HEAD="$SHA" FAKE_KNOWN="$SHA $OTHER" FAKE_ON_MAIN=1
    export CLOUDFLARE_API_TOKEN="" CLOUDFLARE_ACCOUNT_ID="" RELEASE_NONINTERACTIVE_CONFIRM=""
    while [ "$1" != "--" ]; do
      export "$1"
      shift
    done
    shift
    sh scripts/release.sh "$@" </dev/null >"$OUT" 2>&1
  ) || RC=$?
}

CASE=""
ok() {
  PASSED=$((PASSED + 1))
  printf 'PASS  %s\n' "$CASE"
}
bad() {
  FAILED=$((FAILED + 1))
  printf 'FAIL  %s: %s\n' "$CASE" "$1"
  sed 's/^/        | /' "$OUT" | tail -n 15
}
expect_rc() { [ "$RC" -eq "$1" ] || { bad "exit $RC, expected $1"; return 1; }; }
expect_fail() { [ "$RC" -ne 0 ] || { bad "exit 0, expected a failure"; return 1; }; }
expect_out() { grep -q -- "$1" "$OUT" || { bad "output lacks: $1"; return 1; }; }
expect_no_call() { ! grep -q -- "$1" "$LOG" || { bad "unexpected call: $(grep -- "$1" "$LOG" | head -n 1)"; return 1; }; }
expect_call() { grep -q -- "$1" "$LOG" || { bad "missing call: $1"; return 1; }; }
expect_no_package() { [ ! -e "$BOX/.release/evidence/SHA256SUMS" ] || { bad "a package was produced"; return 1; }; }

CREDS="CLOUDFLARE_API_TOKEN=test-token-not-real CLOUDFLARE_ACCOUNT_ID=$ACCOUNT FAKE_WHOAMI_ACCOUNT=$ACCOUNT"
CONFIRM="RELEASE_NONINTERACTIVE_CONFIRM=deploy-tylerbaum-$(printf '%s' "$SHA" | cut -c 1-12)"

echo "Release guardrail tests"
echo

# ---- command surface -------------------------------------------------------
CASE="help prints usage and exits 0"
sandbox; run -- help
expect_rc 0 && expect_out "deploy --confirm SHA" && ok

CASE="no command fails closed (exit 2) and calls nothing"
sandbox; run --
expect_rc 2 && expect_no_call "docker" && ok

CASE="an unknown command fails closed and never reaches Wrangler"
sandbox; run -- publish
expect_rc 2 && expect_out "unknown command" && expect_no_call "wrangler" && ok

CASE="'deploy' is not an alias for build: deploy without --confirm refuses before any work"
sandbox; run -- deploy
expect_rc 2 && expect_out "needs: deploy --confirm" && expect_no_call "docker" && ok

CASE="deploy --confirm without a SHA refuses"
sandbox; run -- deploy --confirm
expect_rc 2 && expect_no_call "docker" && ok

CASE="deploy SHA without --confirm refuses"
sandbox; run -- deploy "$SHA"
expect_rc 2 && expect_no_call "docker" && ok

CASE="deploy with an abbreviated SHA refuses"
sandbox; run $CREDS -- deploy --confirm 0123456
expect_rc 2 && expect_out "40-character" && ok

CASE="smoke needs --url"
sandbox; run -- smoke
expect_rc 2 && expect_out "smoke needs --url" && ok

# ---- positive packaging ---------------------------------------------------------
CASE="a clean repository produces a release package with exactly the allowlist"
sandbox; run -- package
if expect_rc 0; then
  listing=$(cd "$BOX/.release/public" && find . -type f | sort | tr '\n' ' ')
  if [ "$listing" = "./404.html ./_headers ./assets/styles/site.css ./index.html " ]; then ok; else bad "public files: $listing"; fi
fi

CASE="the ownership marker never enters the public package"
if [ ! -e "$BOX/.release/public/.personal-site-output" ] && [ -e "$BOX/dist/.personal-site-output" ]; then ok; else bad "marker in package or missing from dist"; fi

CASE="the file manifest (SHA256SUMS) matches the public package"
(cd "$BOX/.release/public" && sha256sum -c --quiet ../evidence/SHA256SUMS) >"$OUT" 2>&1 && ok || bad "sha256sum -c failed"

CASE="release metadata records the exact source commit, a clean tree and tool versions"
meta="$BOX/.release/evidence/release.json"
grep -q "\"commit\": \"$SHA\"" "$meta" && grep -q '"sourceTreeClean": "true"' "$meta" &&
  grep -q '"wrangler": ".*4.156.2"' "$meta" && grep -q '"fileCount": 4' "$meta" && ok || bad "$(cat "$meta")"

CASE="release metadata contains no credentials or machine paths"
run $CREDS -- package
if grep -q "test-token-not-real\|/Users/\|/home/" "$BOX/.release/evidence/release.json"; then bad "leak in release.json"; else ok; fi

CASE="hashes are deterministic: packaging twice gives identical SHA256SUMS"
cp "$BOX/.release/evidence/SHA256SUMS" "$WORK/sums1"
run -- package
cmp -s "$WORK/sums1" "$BOX/.release/evidence/SHA256SUMS" && ok || bad "SHA256SUMS changed between runs"

CASE="verify accepts the untouched package"
run -- verify
expect_rc 0 && expect_out "Package verified" && ok

# ---- negative packaging -----------------------------------------------------------
CASE="a failed Haskell test prevents packaging"
sandbox; run FAKE_TEST_FAIL=1 -- package
expect_fail && expect_out "test failed" && expect_no_package && ok

CASE="a failed site check prevents packaging"
sandbox; run FAKE_CHECK_FAIL=1 -- package
expect_fail && expect_out "site-check failed" && expect_no_package && ok

CASE="a failed build prevents packaging"
sandbox; run FAKE_BUILD_FAIL=1 -- package
expect_fail && expect_no_package && ok

CASE="a file in dist/ that is not in the manifest is rejected"
sandbox
mkdir -p "$WORK/fx2" && cp -R "$FIXTURE/dist" "$WORK/fx2/dist" && cp "$FIXTURE/manifest.txt" "$WORK/fx2/"
printf 'secret\n' >"$WORK/fx2/dist/notes.txt"
run FAKE_FIXTURE="$WORK/fx2" -- package
expect_fail && expect_out "unexpected notes.txt" && expect_no_package && ok

CASE="a manifest that lists the ownership marker is rejected"
sandbox
printf '.personal-site-output\n404.html\nassets/styles/site.css\nindex.html\n' >"$WORK/m-marker.txt"
run FAKE_MANIFEST="$WORK/m-marker.txt" -- package
expect_fail && expect_out "hidden path component" && expect_no_package && ok

CASE="a manifest that lists a source file (Markdown/JSON) is rejected"
sandbox
mkdir -p "$WORK/fx3/dist/content/projects/black" && cp -R "$FIXTURE/dist/." "$WORK/fx3/dist/"
printf '{}\n' >"$WORK/fx3/dist/content/projects/black/project.json"
printf '404.html\nassets/styles/site.css\ncontent/projects/black/project.json\nindex.html\n' >"$WORK/fx3/manifest.txt"
run FAKE_FIXTURE="$WORK/fx3" -- package
expect_fail && expect_out "forbidden file type .json" && expect_no_package && ok

CASE="a build-machine path leaking into a page is rejected"
sandbox
mkdir -p "$WORK/fx4" && cp -R "$FIXTURE/dist" "$WORK/fx4/dist" && cp "$FIXTURE/manifest.txt" "$WORK/fx4/"
printf '<!doctype html><title>Home</title><!-- /Users/someone/site -->\n' >"$WORK/fx4/dist/index.html"
run FAKE_FIXTURE="$WORK/fx4" -- package
expect_fail && expect_out "contains '/Users/'" && expect_no_package && ok

CASE="an unexpected file added to the public staging directory is rejected by verify"
sandbox; run -- package
printf 'x\n' >"$BOX/.release/public/extra.html"
run -- verify
expect_fail && expect_out "unexpected extra.html" && ok

CASE="a modified packaged file is rejected by verify"
sandbox; run -- package
printf 'tampered\n' >>"$BOX/.release/public/index.html"
run -- verify
expect_fail && expect_out "content changed since packaging" && ok

CASE="a dirty tree is packaged as UNCOMMITTED, never labelled with the commit"
sandbox; run "FAKE_DIRTY= M src/Site/Build.hs" -- package
expect_rc 0 && grep -q '"commit": "UNCOMMITTED"' "$BOX/.release/evidence/release.json" && ok || bad "label: $(grep '"commit"' "$BOX/.release/evidence/release.json")"

# ---- dry run ----------------------------------------------------------------------
CASE="a dry run never deploys: only 'deploy --dry-run' on the credential-free service"
sandbox; run $CREDS -- dry-run
if expect_rc 0 && expect_out "Nothing was published" && expect_call "wrangler: wrangler deploy --dry-run" &&
  expect_no_call "wrangler-deploy" && expect_no_call "rollback"; then
  if grep "wrangler: wrangler deploy" "$LOG" | grep -vq -- "--dry-run"; then bad "a non-dry-run deploy was attempted"; else ok; fi
fi

CASE="a dry run with failing local smoke tests fails"
sandbox; run FAKE_SMOKE_FAIL=1 -- dry-run
expect_fail && expect_out "local smoke tests failed" && expect_no_call "wrangler-deploy" && ok

CASE="a wrong Worker name in wrangler.toml is rejected"
sandbox; sed -i 's/^name = "tylerbaum"$/name = "someone-else"/' "$BOX/wrangler.toml"
run -- dry-run
expect_fail && expect_out "does not name the Worker" && expect_no_call "wrangler" && ok

CASE="an account_id, route or domain committed in wrangler.toml is rejected"
sandbox; printf 'routes = ["tylerbaum.dev/*"]\n' >>"$BOX/wrangler.toml"
run $CREDS $CONFIRM -- deploy --confirm "$SHA"
expect_fail && expect_out "must not set account_id" && expect_no_call "wrangler-deploy" && ok

# ---- deploy guards --------------------------------------------------------------
CASE="a dirty tracked tree prevents a production release"
sandbox; run $CREDS $CONFIRM "FAKE_DIRTY= M assets/styles/site.css" -- deploy --confirm "$SHA"
expect_rc 2 && expect_out "uncommitted changes" && expect_no_call "wrangler" && ok

CASE="untracked files prevent a production release"
sandbox; run $CREDS $CONFIRM "FAKE_UNTRACKED=?? content/projects/new/project.json" -- deploy --confirm "$SHA"
expect_rc 2 && expect_out "untracked files" && expect_no_call "wrangler" && ok

CASE="an unknown release commit is rejected"
sandbox; run $CREDS $CONFIRM -- deploy --confirm fedcba9876543210fedcba9876543210fedcba98
expect_rc 2 && expect_out "unknown release commit" && expect_no_call "wrangler" && ok

CASE="a known commit that is not checked out is rejected"
sandbox; run $CREDS -- deploy --confirm "$OTHER"
expect_rc 2 && expect_out "is not checked out" && expect_no_call "wrangler" && ok

CASE="a commit that is not on main is rejected"
sandbox; run $CREDS $CONFIRM FAKE_ON_MAIN= -- deploy --confirm "$SHA"
expect_rc 2 && expect_out "not on the main branch" && expect_no_call "wrangler" && ok

CASE="missing credentials prevent production deployment"
sandbox; run $CONFIRM -- deploy --confirm "$SHA"
expect_rc 2 && expect_out "CLOUDFLARE_API_TOKEN is not set" && expect_no_call "wrangler" && ok

CASE="a missing account ID prevents production deployment"
sandbox; run CLOUDFLARE_API_TOKEN=test-token-not-real $CONFIRM -- deploy --confirm "$SHA"
expect_rc 2 && expect_out "CLOUDFLARE_ACCOUNT_ID is not set" && expect_no_call "wrangler" && ok

CASE="a token that cannot see the intended account is rejected before deploying"
sandbox; run CLOUDFLARE_API_TOKEN=test-token-not-real CLOUDFLARE_ACCOUNT_ID=$ACCOUNT FAKE_WHOAMI_ACCOUNT=ffffffffffffffffffffffffffffffff $CONFIRM -- deploy --confirm "$SHA"
expect_rc 2 && expect_out "cannot see account" && expect_no_call "wrangler-deploy: wrangler deploy --" && ok

CASE="without the typed confirmation phrase, deploy refuses after validation"
sandbox; run $CREDS -- deploy --confirm "$SHA"
expect_rc 2 && expect_out "RELEASE_NONINTERACTIVE_CONFIRM" && expect_no_call "wrangler-deploy: wrangler deploy --" && ok

CASE="a wrong confirmation phrase refuses"
sandbox; run $CREDS RELEASE_NONINTERACTIVE_CONFIRM=yes -- deploy --confirm "$SHA"
expect_rc 2 && expect_no_call "wrangler-deploy: wrangler deploy --" && ok

CASE="the credential is never printed or written to evidence"
if grep -rq "test-token-not-real" "$OUT" "$BOX/.release" 2>/dev/null; then bad "token found in output or evidence"; else ok; fi

CASE="a confirmed deploy publishes once, tags the commit and records the version"
sandbox; run $CREDS $CONFIRM -- deploy --confirm "$SHA"
if expect_rc 0 && expect_out "is live and passed the smoke tests" &&
  expect_call "wrangler-deploy: wrangler deploy --autoconfig=false --strict --tag 0123456789ab"; then
  n=$(grep -c "wrangler-deploy: wrangler deploy --" "$LOG")
  record=$(cat "$BOX/.release/evidence/deployments.log" 2>/dev/null)
  case $record in
    *"commit=$SHA"*"version=11111111-1111-4111-8111-111111111111"*"previous=22222222-2222-4222-8222-222222222222"*)
      if [ "$n" -eq 1 ]; then ok; else bad "deploy calls: $n"; fi ;;
    *) bad "deployments.log: $record" ;;
  esac
  CASE="the credential is never printed or written to evidence (successful deploy)"
  if grep -rq "test-token-not-real" "$OUT" "$BOX/.release" "$LOG" 2>/dev/null; then bad "token found"; else ok; fi
fi

CASE="post-deployment smoke failures are reported with rollback instructions"
sandbox; run $CREDS $CONFIRM FAKE_SMOKE_FAIL=1 -- deploy --confirm "$SHA"
expect_rc 1 && expect_out "POST-DEPLOYMENT SMOKE TESTS FAILED" &&
  expect_out "rollback 22222222-2222-4222-8222-222222222222 --confirm" && expect_no_call "wrangler rollback" && ok

# ---- rollback guards ----------------------------------------------------------------
CASE="rollback requires explicit intent (--confirm)"
sandbox; run $CREDS -- rollback 22222222-2222-4222-8222-222222222222
expect_rc 2 && expect_out "needs: rollback VERSION_ID --confirm" && expect_no_call "wrangler" && ok

CASE="rollback with a malformed version ID refuses"
sandbox; run $CREDS -- rollback latest --confirm
expect_rc 2 && expect_no_call "wrangler" && ok

CASE="rollback without credentials refuses"
sandbox; run -- rollback 22222222-2222-4222-8222-222222222222 --confirm
expect_rc 2 && expect_out "CLOUDFLARE_API_TOKEN is not set" && expect_no_call "wrangler" && ok

CASE="rollback without the typed confirmation refuses"
sandbox; run $CREDS -- rollback 22222222-2222-4222-8222-222222222222 --confirm
expect_rc 2 && expect_no_call "wrangler rollback" && ok

CASE="a confirmed rollback calls Wrangler once and smoke-tests"
sandbox; run $CREDS RELEASE_NONINTERACTIVE_CONFIRM=rollback-tylerbaum-22222222-2222-4222-8222-222222222222 -- rollback 22222222-2222-4222-8222-222222222222 --confirm
expect_rc 0 && expect_call "wrangler-deploy: wrangler rollback 22222222-2222-4222-8222-222222222222" &&
  expect_out "is live again" && ok

echo
echo "$PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

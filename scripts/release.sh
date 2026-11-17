#!/bin/sh
# Release entry point (Phase 07). Full guide: docs/operations/deployment.md.
#
# Every command except `deploy --confirm` and `rollback ... --confirm` is
# non-publishing. Unknown commands and missing confirmations fail closed.
# All tooling runs in Docker (compose.yaml, profile "release"); the host
# needs only Docker and Git.
set -eu

WORKER_NAME="tylerbaum"
CANONICAL_ORIGIN="https://tylerbaum.dev"
RELEASE_BRANCH="main"
EVIDENCE=".release/evidence"
MANIFEST="$EVIDENCE/manifest.txt"

usage() {
  cat <<'EOF'
usage: scripts/release.sh COMMAND [ARGS]

Non-publishing commands
  check                 tools, Git state, Haskell tests, site check, a fresh
                        build, and the dist/ inventory against the generator's
                        manifest (prohibited files, marker, leaks)
  package               check, then stage exactly the manifest's files plus
                        release/_headers into .release/public, with
                        SHA256SUMS and release.json in .release/evidence
  verify                re-hash .release/public against the packaged SHA256SUMS
  dry-run               package, `wrangler deploy --dry-run` (no credentials),
                        then serve the package with local Cloudflare emulation
                        (wrangler dev) and run the smoke tests against it
  smoke --url URL       HTTP, HTML and browser smoke tests against any URL
        [--no-browser]
  versions              list the Worker's recent deployments (needs credentials;
                        read-only)

Publishing commands (need CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID)
  deploy --confirm SHA  revalidate, repackage and publish commit SHA (the full
                        40-character HEAD of a clean main checkout), record the
                        Cloudflare version, then smoke-test production
  rollback VERSION_ID --confirm
                        make an earlier Worker version live again, then smoke-test

Both publishing commands then ask the operator to type a phrase naming the
Worker and the commit or version (for example deploy-tylerbaum-0123456789ab).
With no terminal, set RELEASE_NONINTERACTIVE_CONFIRM to that exact phrase.

  help                  this text
EOF
}

say() { printf '%s\n' "$*"; }
step() { printf '\n==> %s\n' "$*"; }
die() {
  printf 'release: error: %s\n' "$*" >&2
  exit 1
}
refuse() {
  printf 'release: refused: %s\n' "$*" >&2
  exit 2
}

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

compose() { docker compose --profile release "$@"; }

# Run a command, keeping its full output in the evidence directory and
# showing the tail (all of it on failure).
run_logged() {
  name=$1
  shift
  log="$EVIDENCE/$name.log"
  status=0
  "$@" >"$log" 2>&1 || status=$?
  if [ "$status" -ne 0 ]; then
    tail -n 60 "$log" >&2
    die "$name failed (exit $status); full log: $log"
  fi
  tail -n 4 "$log"
}

# ---- preconditions -----------------------------------------------------

require_tools() {
  command -v docker >/dev/null 2>&1 || die "docker is not installed or not on PATH"
  command -v git >/dev/null 2>&1 || die "git is not installed or not on PATH"
  docker compose version >/dev/null 2>&1 || die "docker compose is not available"
}

head_commit() { git rev-parse --verify HEAD; }

tracked_changes() { git status --porcelain --untracked-files=no; }

untracked_files() { git status --porcelain | grep '^??' || true; }

git_snapshot() { git status --porcelain; }

# The Cloudflare configuration must name this Worker, serve the packaged
# directory, and carry no account, routes or domains (those are owner
# actions in the dashboard, never side effects of a deploy).
check_config() {
  [ -f wrangler.toml ] || die "wrangler.toml is missing"
  grep -Eq "^name = \"$WORKER_NAME\"$" wrangler.toml ||
    die "wrangler.toml does not name the Worker \"$WORKER_NAME\""
  grep -Eq '^directory = "\./\.release/public"$' wrangler.toml ||
    die "wrangler.toml [assets] directory must be \"./.release/public\""
  grep -Eq '^not_found_handling = "404-page"$' wrangler.toml ||
    die "wrangler.toml must use not_found_handling = \"404-page\""
  if grep -Eq '^[[:space:]]*(account_id|routes|route|custom_domain|workers_dev|main)[[:space:]]*=' wrangler.toml; then
    die "wrangler.toml must not set account_id, routes, custom domains, workers_dev or main (see the deployment guide)"
  fi
}

require_credentials() {
  # Presence only: values are never printed, logged or written anywhere.
  [ -n "${CLOUDFLARE_API_TOKEN:-}" ] || refuse "CLOUDFLARE_API_TOKEN is not set (docs/operations/deployment.md, \"Cloudflare authentication\")"
  [ -n "${CLOUDFLARE_ACCOUNT_ID:-}" ] || refuse "CLOUDFLARE_ACCOUNT_ID is not set (docs/operations/deployment.md, \"Cloudflare authentication\")"
}

# Account check: the token must see the intended account.
verify_account() {
  whoami_out=$(compose run --rm -T wrangler-deploy wrangler whoami 2>&1) ||
    refuse "wrangler whoami failed: the token is invalid or lacks permission"
  printf '%s\n' "$whoami_out" | grep -q -- "$CLOUDFLARE_ACCOUNT_ID" ||
    refuse "the API token cannot see account CLOUDFLARE_ACCOUNT_ID; refusing to deploy to an unintended account"
  say "Cloudflare account verified (the token can see the configured account)."
}

# Typed confirmation, or the exact phrase in RELEASE_NONINTERACTIVE_CONFIRM.
confirm_phrase() {
  phrase=$1
  prompt=$2
  if [ -t 0 ]; then
    printf '%s\nType "%s" to continue: ' "$prompt" "$phrase"
    read -r answer || answer=""
    [ "$answer" = "$phrase" ] || refuse "confirmation did not match; nothing was changed"
  else
    [ "${RELEASE_NONINTERACTIVE_CONFIRM:-}" = "$phrase" ] ||
      refuse "no terminal for confirmation; set RELEASE_NONINTERACTIVE_CONFIRM=\"$phrase\" to proceed"
  fi
}

# ---- check / package ---------------------------------------------------

SOURCE_COMMIT=""
SOURCE_CLEAN=""

cmd_check() {
  step "Tools"
  require_tools
  mkdir -p "$EVIDENCE" .release/public
  say "docker, docker compose and git are available."

  step "Git state"
  SOURCE_COMMIT=$(head_commit) || die "not a Git checkout with a commit"
  before=$(git_snapshot)
  if [ -n "$(tracked_changes)" ] || [ -n "$(untracked_files)" ]; then
    SOURCE_CLEAN=false
    say "WARNING: the working tree has uncommitted or untracked changes; this build"
    say "will be labelled as UNCOMMITTED, not as $SOURCE_COMMIT, and cannot be deployed."
    git status --short
  else
    SOURCE_CLEAN=true
    say "Clean tree at $SOURCE_COMMIT."
  fi

  step "Haskell tests"
  run_logged test compose run --rm -T site-build stack test
  step "site check"
  run_logged site-check compose run --rm -T site-build stack exec -- site check
  step "Fresh build into dist/"
  run_logged build compose run --rm -T site-build
  step "Generator manifest"
  status=0
  compose run --rm -T site-build stack exec -- site manifest >"$MANIFEST" 2>"$EVIDENCE/manifest.stderr" || status=$?
  [ "$status" -eq 0 ] || {
    cat "$EVIDENCE/manifest.stderr" >&2
    die "site manifest failed"
  }
  say "$(wc -l <"$MANIFEST" | tr -d ' ') files in the manifest ($MANIFEST)."
  step "dist/ inventory, prohibited files and leaks"
  run_logged check-dist compose run --rm -T release python3 tools/release/package.py check-dist --manifest "$MANIFEST"

  after=$(git_snapshot)
  [ "$before" = "$after" ] || die "the working tree changed during the check; run it again"

  step "Source"
  if [ "$SOURCE_CLEAN" = true ]; then
    say "Release candidate: commit $SOURCE_COMMIT (clean tree)."
  else
    say "Release candidate: UNCOMMITTED changes on top of $SOURCE_COMMIT (not deployable)."
  fi
}

tool_versions() {
  GHC_VERSION=$(compose run --rm -T site-build stack exec -- ghc --numeric-version 2>/dev/null | tail -n 1) || GHC_VERSION=unknown
  STACK_VERSION=$(compose run --rm -T site-build stack --numeric-version 2>/dev/null | tail -n 1) || STACK_VERSION=unknown
  WRANGLER_VERSION=$(compose run --rm -T wrangler wrangler --version 2>/dev/null | tail -n 1) || WRANGLER_VERSION=unknown
  BUILD_IMAGE=$(docker image inspect --format '{{.Id}}' personal-site-build:local 2>/dev/null) || BUILD_IMAGE=unknown
}

cmd_package() {
  cmd_check
  step "Toolchain versions"
  tool_versions
  say "GHC $GHC_VERSION, Stack $STACK_VERSION, Wrangler $WRANGLER_VERSION"
  if [ "$SOURCE_CLEAN" = true ]; then
    label=$SOURCE_COMMIT
  else
    label="UNCOMMITTED"
  fi
  step "Staging .release/public (exact allowlist)"
  run_logged package compose run --rm -T release python3 tools/release/package.py stage \
    --manifest "$MANIFEST" \
    --meta "commit=$label" \
    --meta "sourceCommit=$SOURCE_COMMIT" \
    --meta "sourceTreeClean=$SOURCE_CLEAN" \
    --meta "worker=$WORKER_NAME" \
    --meta "canonicalOrigin=$CANONICAL_ORIGIN" \
    --meta "ghc=$GHC_VERSION" \
    --meta "stack=$STACK_VERSION" \
    --meta "wrangler=$WRANGLER_VERSION" \
    --meta "buildImage=$BUILD_IMAGE"
  say "Packaged, not published. Evidence: $EVIDENCE/ (SHA256SUMS, release.json, logs)."
}

cmd_verify() {
  run_logged verify compose run --rm -T release python3 tools/release/package.py verify
}

# ---- dry run -------------------------------------------------------------

stop_emulation() {
  compose stop wrangler-dev >/dev/null 2>&1 || true
  compose rm -f wrangler-dev >/dev/null 2>&1 || true
}

cmd_dry_run() {
  check_config
  cmd_package
  step "Wrangler configuration and deploy dry run (no credentials, nothing uploaded)"
  run_logged wrangler-dry-run compose run --rm -T wrangler wrangler deploy --dry-run --autoconfig=false
  grep -q -- "--dry-run: exiting now" "$EVIDENCE/wrangler-dry-run.log" ||
    die "Wrangler did not confirm a dry run; see $EVIDENCE/wrangler-dry-run.log"

  step "Local Cloudflare emulation (wrangler dev) and smoke tests"
  trap stop_emulation EXIT INT TERM
  stop_emulation
  run_logged emulation-start compose up -d wrangler-dev
  status=0
  compose run --rm -T release python3 tools/release/smoke.py \
    --url http://wrangler-dev:8787/ --wait 120 \
    --manifest "$MANIFEST" --headers release/_headers \
    --out "$EVIDENCE/smoke-local" || status=$?
  compose logs --no-color wrangler-dev >"$EVIDENCE/emulation.log" 2>&1 || true
  stop_emulation
  trap - EXIT INT TERM
  [ "$status" -eq 0 ] || die "local smoke tests failed; see $EVIDENCE/smoke-local.txt"

  step "Package unchanged by the dry run"
  cmd_verify
  say ""
  say "Dry run complete. Nothing was published and no Cloudflare state was read or changed."
}

# ---- smoke ---------------------------------------------------------------

cmd_smoke() {
  url=""
  browser=""
  while [ $# -gt 0 ]; do
    case $1 in
      --url)
        [ $# -ge 2 ] || refuse "--url needs a value"
        url=$2
        shift 2
        ;;
      --no-browser)
        browser="--no-browser"
        shift
        ;;
      *) refuse "unknown smoke option: $1" ;;
    esac
  done
  [ -n "$url" ] || refuse "smoke needs --url URL"
  run_smoke "$url" "smoke" $browser
}

run_smoke() {
  url=$1
  out=$2
  shift 2
  mkdir -p "$EVIDENCE"
  set -- --url "$url" --out "$EVIDENCE/$out" "$@"
  if [ -f "$MANIFEST" ] && [ -f "$EVIDENCE/SHA256SUMS" ]; then
    set -- "$@" --manifest "$MANIFEST" --headers release/_headers
  fi
  compose run --rm -T release python3 tools/release/smoke.py "$@"
}

# ---- deploy ----------------------------------------------------------------

cmd_deploy() {
  [ $# -eq 2 ] && [ "$1" = "--confirm" ] ||
    refuse "deploy publishes to production and needs: deploy --confirm <full commit SHA>"
  sha=$2
  printf '%s' "$sha" | grep -Eq '^[0-9a-f]{40}$' ||
    refuse "\"$sha\" is not a full 40-character commit SHA"

  step "Release preconditions"
  require_tools
  git cat-file -e "$sha^{commit}" 2>/dev/null || refuse "unknown release commit $sha"
  head=$(head_commit)
  [ "$head" = "$sha" ] || refuse "commit $sha is not checked out (HEAD is $head)"
  git merge-base --is-ancestor "$sha" "$RELEASE_BRANCH" 2>/dev/null ||
    refuse "commit $sha is not on the $RELEASE_BRANCH branch"
  [ -z "$(tracked_changes)" ] || refuse "tracked files have uncommitted changes"
  [ -z "$(untracked_files)" ] || refuse "untracked files are present; commit, remove or ignore them first"
  check_config
  require_credentials
  say "Commit $sha is HEAD of a clean $RELEASE_BRANCH checkout; credentials are present."

  cmd_package
  [ "$SOURCE_CLEAN" = true ] && [ "$SOURCE_COMMIT" = "$sha" ] ||
    refuse "the package was not built from a clean checkout of $sha"
  step "Exact artifact"
  cmd_verify
  grep -q "\"commit\": \"$sha\"" "$EVIDENCE/release.json" ||
    refuse "release.json does not record commit $sha"
  digest=$(grep -o '"digest": "[0-9a-f]*"' "$EVIDENCE/release.json" | head -n 1 | cut -d '"' -f 4)

  step "Cloudflare account"
  verify_account
  compose run --rm -T wrangler-deploy wrangler deployments list --json \
    >"$EVIDENCE/deployments-before.json" 2>"$EVIDENCE/deployments-before.stderr" ||
    say "(no previous deployments could be listed; this may be the first deploy)"
  previous=$(grep -oE '"version_id": *"[0-9a-f-]{36}"' "$EVIDENCE/deployments-before.json" 2>/dev/null | head -n 1 | grep -oE '[0-9a-f-]{36}' || true)

  step "Confirmation"
  short=$(printf '%s' "$sha" | cut -c 1-12)
  confirm_phrase "deploy-$WORKER_NAME-$short" \
    "About to publish commit $sha (package $digest) to the Worker \"$WORKER_NAME\"."

  step "Deploy"
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  run_logged "deploy-$stamp" compose run --rm -T wrangler-deploy wrangler deploy \
    --autoconfig=false --strict --tag "$short" --message "release $sha package $digest"
  version=$(grep -oE 'Current Version ID: [0-9a-f-]{36}' "$EVIDENCE/deploy-$stamp.log" | head -n 1 | grep -oE '[0-9a-f-]{36}' || true)
  [ -n "$version" ] || say "WARNING: Wrangler did not report a version ID; check \`scripts/release.sh versions\`."
  printf '%s\tcommit=%s\tversion=%s\tprevious=%s\tdigest=%s\n' \
    "$stamp" "$sha" "${version:-unknown}" "${previous:-none}" "$digest" >>"$EVIDENCE/deployments.log"
  say "Deployed commit $sha as Worker version ${version:-unknown} (recorded in $EVIDENCE/deployments.log)."

  step "Post-deployment smoke tests"
  target=${RELEASE_SMOKE_URL:-$CANONICAL_ORIGIN}
  if ! run_smoke "$target" "smoke-$stamp"; then
    printf '\n' >&2
    printf 'release: POST-DEPLOYMENT SMOKE TESTS FAILED against %s\n' "$target" >&2
    printf 'The new version (%s) is live. To restore the previous version:\n' "${version:-unknown}" >&2
    if [ -n "$previous" ]; then
      printf '  scripts/release.sh rollback %s --confirm\n' "$previous" >&2
    else
      printf '  scripts/release.sh versions        # find the previous known-good version\n' >&2
      printf '  scripts/release.sh rollback VERSION_ID --confirm\n' >&2
    fi
    printf 'See docs/operations/deployment.md, "Rollback".\n' >&2
    exit 1
  fi
  say ""
  say "Release $sha is live and passed the smoke tests."
}

# ---- versions / rollback ---------------------------------------------------

cmd_versions() {
  [ $# -eq 0 ] || refuse "versions takes no arguments"
  require_tools
  check_config
  require_credentials
  mkdir -p .release/public
  compose run --rm -T wrangler-deploy wrangler deployments list
}

cmd_rollback() {
  [ $# -eq 2 ] && [ "$2" = "--confirm" ] ||
    refuse "rollback changes production and needs: rollback VERSION_ID --confirm (list versions with: scripts/release.sh versions)"
  version=$1
  printf '%s' "$version" | grep -Eq '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' ||
    refuse "\"$version\" is not a Worker version ID"
  require_tools
  check_config
  require_credentials
  mkdir -p "$EVIDENCE" .release/public
  verify_account
  confirm_phrase "rollback-$WORKER_NAME-$version" \
    "About to make Worker version $version of \"$WORKER_NAME\" live again."
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  run_logged "rollback-$stamp" compose run --rm -T wrangler-deploy wrangler rollback "$version" \
    --message "operator rollback via scripts/release.sh" --yes
  printf '%s\trollback\tversion=%s\n' "$stamp" "$version" >>"$EVIDENCE/deployments.log"
  step "Post-rollback smoke tests"
  target=${RELEASE_SMOKE_URL:-$CANONICAL_ORIGIN}
  run_smoke "$target" "smoke-rollback-$stamp" --no-browser ||
    die "smoke tests failed after the rollback; investigate before anything else"
  say "Version $version is live again and passed the smoke tests."
}

# ---- dispatch --------------------------------------------------------------

[ $# -ge 1 ] || {
  usage >&2
  exit 2
}
command=$1
shift
case $command in
  help | -h | --help) usage ;;
  check) [ $# -eq 0 ] || refuse "check takes no arguments"; cmd_check ;;
  package) [ $# -eq 0 ] || refuse "package takes no arguments"; cmd_package ;;
  verify) [ $# -eq 0 ] || refuse "verify takes no arguments"; mkdir -p "$EVIDENCE"; cmd_verify ;;
  dry-run) [ $# -eq 0 ] || refuse "dry-run takes no arguments"; cmd_dry_run ;;
  smoke) cmd_smoke "$@" ;;
  deploy) cmd_deploy "$@" ;;
  versions) cmd_versions "$@" ;;
  rollback) cmd_rollback "$@" ;;
  *)
    usage >&2
    refuse "unknown command: $command"
    ;;
esac

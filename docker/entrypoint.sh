#!/bin/sh
# Container entrypoint for the site-build service.
#
# The source tree is bind-mounted at /work. To keep generated files (dist/,
# .stack-work/) owned by the host user on Linux, we run the requested command
# as whichever UID/GID owns /work, instead of as root. On Docker Desktop
# (macOS/Windows) file ownership is translated by the VM, so this is harmless.
set -eu

if [ "$(id -u)" != "0" ]; then
  # Already started as a non-root user (e.g. `docker compose run --user ...`).
  exec "$@"
fi

uid=$(stat -c %u /work)
gid=$(stat -c %g /work)

# A freshly created named volume is root-owned; hand it to the build user.
# Only the top-level directory is changed: everything inside is created by
# that same user afterwards.
mkdir -p "$STACK_ROOT"
if [ "$(stat -c %u "$STACK_ROOT")" != "$uid" ]; then
  chown "$uid:$gid" "$STACK_ROOT"
fi

# The host UID usually has no passwd entry or home directory in the image.
export HOME=/tmp/site-home
mkdir -p "$HOME"
chown "$uid:$gid" "$HOME"

if [ "$uid" = "0" ]; then
  exec "$@"
fi

exec setpriv --reuid="$uid" --regid="$gid" --clear-groups "$@"

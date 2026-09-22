#!/bin/sh
# =============================================================================
# src/agentic/codebase-memory/entrypoint.sh
# Fix the index store's ownership, then drop the root we started with.
#
# The store lives on a Docker named volume (see docker-compose.yml). Its owner
# cannot be baked into the image — the host uid is only known at run time — and
# codebase-memory-mcp validates that it OWNS its cache dir before it will start.
# So the container starts as root just long enough to chown the volume, then
# drops to the host uid. `user:` in compose cannot be used: it would remove the
# privilege this chown needs.
#
# Root is confined to the container: the repo mount is read-only and the volume
# is the only writable target. setpriv is util-linux, already in the base image.
# GATE: Must work on Ubuntu, Fedora, and macOS (the *container* is always Linux).
# =============================================================================

set -eu

if [ "$(id -u)" = "0" ]; then
  DEV_UID="${DEV_UID:-1000}"
  DEV_GID="${DEV_GID:-1000}"
  chown -R "${DEV_UID}:${DEV_GID}" /srv/cbm
  exec setpriv --reuid "${DEV_UID}" --regid "${DEV_GID}" --clear-groups "$@"
fi

exec "$@"

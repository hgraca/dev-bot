#!/usr/bin/env bash
# src/_shared/tests/lib/pins.bash
# Where a module's pin lives, for tests.
#
# A module ships its pin as the committed versions.env.dist; the live
# versions.env beside it is machine-local (gitignored, bumped by `devbot
# update`). Tests read the live copy when the machine has one, so they assert
# against what install.sh and update.sh actually resolve.

# Echo the effective pin file for $1 (the module directory).
pins_file() {
  local dir="${1:-}"
  if [[ -f "${dir}/versions.env" ]]; then
    printf '%s\n' "${dir}/versions.env"
  else
    printf '%s\n' "${dir}/versions.env.dist"
  fi
}

---
date: 2026-11-27
keywords: ["shell", "bash", "mapfile", "bats", "makefile"]
trigger-on: ["makefile-bash-array-collection", "bats-target-list"]
---

## macOS /bin/bash 3.2 has no mapfile, so an array-collection recipe silently runs nothing

`make test-bats` in dev-bot collects its targets with `mapfile -t targets < <(...)`; under macOS `/bin/bash` (3.2) that line fails with `mapfile: command not found`, the array stays empty, and the recipe then runs `bats -T "${targets[@]}"` with no arguments — bats prints its usage banner and exits 1. The output reads like a broken bats flag rather than a missing builtin, so the CI-time recipe looks healthy and only the local macOS run is wrong. Replace `mapfile -t arr < <(cmd)` with `while IFS= read -r line; do arr+=("$line"); done < <(cmd)` in anything that must run on bash 3.2, or require bash 4+ explicitly.

#!/usr/bin/env bash
# =============================================================================
# bin/test-slices.sh
# Print the BATS files that belong to one slice of the CI test split.
#
# The `test-slice` job in .github/workflows/ci.yml runs the BATS suite as a
# build matrix, each job taking one slice via `make test-bats-slice SLICE=n`.
# The partition is computed here, never listed, so a new test file is picked up
# without registering it anywhere.
#
# Usage: bin/test-slices.sh <slice> [slices]
#   slice   1-based slice number to print
#   slices  number of slices to split into (default 3)
#
# Paths are printed one per line, spaces and all, so a filename containing a
# newline is not supported — as with the rest of the line-oriented tooling here.
#
# bin/tests/ci_slices_tests.bats guards the result: every BATS file in exactly
# one slice, and no slice much bigger than the others.
# =============================================================================

set -euo pipefail

readonly SLICES_DEFAULT=3

# A file's runtime is not proportional to its case count: a case that inits a
# harness, runs docker or shells out to the devbot CLI costs an order of
# magnitude more than a pure assertion. Weight a file by its cases plus one per
# 4 KB of test code — the size stands in for the shell-outs a large file
# accumulates — and the constant was tuned against CI timings so the three jobs
# finish together.
readonly BYTES_PER_WEIGHT_UNIT=4096

usage_error() {
  echo "ERROR: $*" >&2
  exit 2
}

slice="${1:-}"
slices="${2:-${SLICES_DEFAULT}}"

case "${slices}" in
  '' | *[!0-9]*)
    usage_error "slices must be a positive number (got '${slices}')"
    ;;
esac
case "${slice}" in
  '' | *[!0-9]*)
    usage_error "slice must be a number from 1 to ${slices} (got '${slice}')"
    ;;
esac
if [ "${slices}" -lt 1 ] || [ "${slice}" -lt 1 ] || [ "${slice}" -gt "${slices}" ]; then
  usage_error "slice must be a number from 1 to ${slices} (got '${slice}')"
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${root}"

# The same roots `make test` runs, resolved through git so an untracked scratch
# file is never handed to bats. Every path starts with bin/ or src/, so none can
# be mistaken for a bats option.
mapfile -t files < <(git -c core.quotePath=false ls-files 'bin/*.bats' 'src/*.bats')
if [ "${#files[@]}" -eq 0 ]; then
  usage_error "git ls-files found no .bats files — not a repo checkout?"
fi

# Weight and path, tab-separated. LC_ALL=C pins the tie-break so every slice is
# computed identically whatever the runner's locale.
weighted=()
for file in "${files[@]}"; do
  cases="$(grep -c -e '^[[:blank:]]*@test' -- "${file}" || true)"
  weighted+=("$((cases + $(wc -c < "${file}") / BYTES_PER_WEIGHT_UNIT))"$'\t'"${file}")
done
mapfile -t ranked < <(printf '%s\n' "${weighted[@]}" | LC_ALL=C sort -t $'\t' -k1,1nr -k2,2)

# Heaviest first into the least-loaded slice — the longest-processing-time
# heuristic, which is why the jobs finish within seconds of each other.
load=()
for ((i = 0; i < slices; i++)); do load[i]=0; done
for record in "${ranked[@]}"; do
  weight="${record%%$'\t'*}"
  path="${record#*$'\t'}"
  target=0
  for ((i = 1; i < slices; i++)); do
    if ((load[i] < load[target])); then target=$i; fi
  done
  load[target]=$((load[target] + weight))
  if ((target == slice - 1)); then printf '%s\n' "${path}"; fi
done

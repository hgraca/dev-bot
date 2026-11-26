#!/usr/bin/env bash
# ---
# description: Fail the Pages deploy when the site is not built from the Actions artifact
# ---
#
# Legacy source serves docs/, not the artifact.
# Build-time only, run by the Pages workflow.
set -euo pipefail

repo="${1:?usage: assert-pages-build-type.sh <owner/repo>}"

if ! build_type="$(gh api "repos/${repo}/pages" --jq '.build_type // ""' 2>&1)"; then
  echo "FATAL: cannot read the Pages settings for ${repo}: ${build_type}" >&2
  echo "FATAL: check the Pages source before deploying." >&2
  exit 1
fi

case "${build_type}" in
workflow)
  echo "Pages publishes the Actions artifact (build_type=workflow)."
  ;;
legacy)
  echo "ERROR: Pages serves branch docs/ (build_type=legacy): the artifact is" >&2
  echo "ERROR: unused, so generated pages and install.sh 404." >&2
  echo "ERROR: fix with: gh api -X PUT repos/${repo}/pages -f build_type=workflow" >&2
  exit 1
  ;;
*)
  echo "ERROR: Pages build_type is '${build_type}', not 'workflow': cannot" >&2
  echo "ERROR: confirm the artifact is served. Set the Pages source to" >&2
  echo "ERROR: GitHub Actions: gh api -X PUT repos/${repo}/pages -f build_type=workflow" >&2
  exit 1
  ;;
esac

#!/usr/bin/env bash
# src/agentic/k8s/functions.sh
# Thin wrapper: sources the root shared library.
set -euo pipefail
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export MODULE_DIR
source "$MODULE_DIR/../../_shared/functions.sh"

# The name the project goes by: the declared `project_name`, or the directory
# basename when it declares none. `devbot init` defaults the config to the same
# basename, so a project that never set the key still gets a stable name. The
# k8s module also matches it against cluster names to pick a default context, so
# it is read raw here — quoting and folding belong to the slug below.
#
# Reads PROJECT_DIR, PROJECT_CONFIG and READER from the caller.
_project_name() {
  local name
  name="$(python3 "${READER}" "${PROJECT_CONFIG}" project_name 2>/dev/null || true)"
  if [[ -z "${name}" || "${name}" == "null" ]]; then
    name="$(basename "${PROJECT_DIR}")"
  fi
  printf '%s' "${name}"
}

# The generated kubeconfig's filename, shared by init.sh (which writes it) and
# kube.sh (which resolves it). Reads PROJECT_DIR, PROJECT_CONFIG and READER from
# the caller — both set those before calling.
#
# The project name becomes a filename, so anything outside the kubeconfig-safe
# alphabet is folded to '-' rather than rejected: the slug labels a generated
# file, it is not an identity the user chose for kubectl.
#
# The name alone is not unique — `devbot init` defaults `project_name` to the
# directory basename, so `/work/a/demo` and `/work/b/demo` would share a slug and
# the second init would silently overwrite the first project's kubeconfig. The
# absolute path, hashed, restores the isolation the per-project render exists
# for; it stays stable unless the project moves.
_project_slug() {
  local name hash
  name="$(_project_name)"
  # python3 is already a hard dependency (read_jsonc) and is the portable way to
  # hash: macOS has no `sha256sum`, and a silently empty hash would put every
  # same-named project back on one shared file.
  hash="$(printf '%s' "${PROJECT_DIR}" \
    | python3 -c 'import hashlib, sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest()[:8])')"
  printf '%s-%s' "${name//[^A-Za-z0-9._-]/-}" "${hash}"
}

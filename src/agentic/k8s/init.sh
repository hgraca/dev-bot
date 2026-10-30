#!/usr/bin/env bash
# =============================================================================
# src/agentic/k8s/init.sh
# Generate the kubectl access this project's agents use.
#
# Reads the `kubectl` node of the global config and writes two files outside the
# repo: a kubeconfig, and an exec credential wrapper kubectl runs for every
# token. No credential is read here and none is written anywhere — the wrapper
# receives the configured ${VAR} reference verbatim, so the shell resolves it at
# call time. Resolving it at init would put the secret in a file on disk, which
# is exactly what the reference exists to prevent.
#
# The global node's `clusters` is a catalogue: the project opts in by naming
# clusters in `.devbot.project.jsonc` → `kubectl`, the way `datasources` and
# `aws_connections` work. Nothing is rendered without that opt-in, and each
# project gets its own `~/.kube/devbot/<project>.yaml` — one project's selection
# cannot widen another's.
#
# That guarantee is only as good as the input, so credential_env values must BE
# references: a literal is refused rather than quietly copied into the wrapper.
#
# Usage:
#   init.sh                    # init in current directory
#   init.sh /path/to/project   # init in specified project
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "${MODULE_DIR}/../../.." && pwd)}"
export DEV_BOT_ROOT

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

PROJECT_DIR="$(cd "${1:-$(pwd)}" && pwd)"
PROJECT_CONFIG="${PROJECT_DIR}/.devbot.project.jsonc"
READER="${MODULE_DIR}/../../_shared/read_jsonc.py"

# `kubectl.clusters` in the global config is the catalogue; each project names
# the clusters it may use. The render therefore belongs to the project, not the
# machine: one kubeconfig per project, so initialising one project never changes
# what another one sees. The exec wrapper stays shared — it is addressed by
# region and cluster name on every call, so it carries nothing project-specific.
WORK_DIR="${HOME}/.kube/devbot"
WRAPPER_PATH="${WORK_DIR}/exec-credential.sh"
KUBECONFIG_PATH=""
ENV_PATH=""
# Written by the pre-selection implementation, when every project shared one
# kubeconfig. Removed after a scoped render succeeds — see _migrate_legacy.
LEGACY_KUBECONFIG="${HOME}/.kube/devbot.yaml"
LEGACY_ENV="${HOME}/.kube/devbot.env"

# A whole-value reference: everything else is a literal or a shell fragment and
# has no business in a generated file.
REF_RE='^\$\{[A-Za-z_][A-Za-z0-9_]*\}$'
# Profile and cluster names end up in shell and kubeconfig syntax respectively.
NAME_RE='^[A-Za-z0-9._-]+$'

_ref_name() {
  local ref="${1#\$\{}"
  printf '%s' "${ref%\}}"
}

# The value, in this process only — never into a generated file.
_ref_value() {
  local name
  name="$(_ref_name "$1")"
  printf '%s' "${!name:-}"
}

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
  name="$(python3 "${READER}" "${PROJECT_CONFIG}" project_name 2>/dev/null || true)"
  if [[ -z "${name}" || "${name}" == "null" ]]; then
    name="$(basename "${PROJECT_DIR}")"
  fi
  # python3 is already a hard dependency (read_jsonc) and is the portable way to
  # hash: macOS has no `sha256sum`, and a silently empty hash would put every
  # same-named project back on one shared file.
  hash="$(printf '%s' "${PROJECT_DIR}" \
    | python3 -c 'import hashlib, sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest()[:8])')"
  printf '%s-%s' "${name//[^A-Za-z0-9._-]/-}" "${hash}"
}

_credential_pairs() {
  echo "${1}" | jq -r '.credential_env // {} | to_entries[] | "\(.key)\t\(.value)"'
}

# Refuse any mapping that would put something other than a reference in the
# wrapper. Shell metacharacters in a literal are the sharpest edge here: they
# would become executable syntax the moment kubectl ran the generated file.
_validate() {
  local spec="$1" profile="$2" key ref

  if ! [[ "${profile}" =~ ${NAME_RE} ]]; then
    _warn "kubectl — profile '${profile}' is not a valid profile name; skipping"
    return 1
  fi

  while IFS=$'\t' read -r key ref; do
    [[ -n "${key}" ]] || continue
    if ! [[ "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      _warn "kubectl — '${key}' is not a valid environment variable name; skipping"
      return 1
    fi
    if ! [[ "${ref}" =~ ${REF_RE} ]]; then
      _warn "kubectl — ${key} must be a \${VAR} reference, not a literal — a literal would be written to the wrapper; skipping"
      return 1
    fi
    if [[ -z "$(_ref_value "${ref}")" ]]; then
      _warn "kubectl — ${key} references ${ref}, which is not set; skipping"
      return 1
    fi
  done < <(_credential_pairs "${spec}")

  return 0
}

# Environment credentials take precedence over static credentials in a profile.
# That is what makes credential_source = Environment work, and also what makes a
# profile with plain access keys resolve to the *source* identity instead of the
# cluster-access role — the agent would silently run with whatever the mapped
# key can do. Verify the resolved identity is a role session and refuse
# otherwise, rather than discovering it from a CloudTrail entry later.
_verify_identity() {
  local spec="$1" profile="$2" arn
  arn="$(_with_credentials "${spec}" "${profile}" sts get-caller-identity --query Arn --output text 2>/dev/null || true)"

  if [[ -z "${arn}" ]]; then
    _warn "kubectl — cannot resolve an identity for profile '${profile}'; skipping"
    return 1
  fi

  case "${arn}" in
    arn:aws:sts::*:assumed-role/*)
      _ok "kubectl — identity ${arn}"
      return 0
      ;;
    *)
      _warn "kubectl — profile '${profile}' resolves to ${arn}, not a role session: the credentialed environment is overriding it and the agent would run as that identity; skipping"
      return 1
      ;;
  esac
}

_write_wrapper() {
  local spec="$1" profile="$2" key ref
  mkdir -p "$(dirname "${WRAPPER_PATH}")"

  {
    printf '#!/bin/sh\n'
    printf '# Generated by dev-bot src/agentic/k8s/init.sh — do not edit.\n'
    printf '# Usage: exec-credential.sh <region> <cluster-name>\n'
    printf '#\n'
    printf '# Copies the configured credential variables onto the standard AWS names\n'
    printf '# for this process only. The values are resolved by the shell at call time,\n'
    printf '# so no secret is stored in this file.\n'
    printf '#\n'
    printf '# POSIX only: this runs under /bin/sh (dash on Debian/Ubuntu, Fedora).\n'
    printf '# Do not add [[ ]], arrays or process substitution here.\n'
    printf 'set -eu\n'
    while IFS=$'\t' read -r key ref; do
      [[ -n "${key}" ]] || continue
      printf '%s="%s" \\\n' "${key}" "${ref}"
    done < <(_credential_pairs "${spec}")
    printf '  exec aws --region "$1" --profile "%s" eks get-token --cluster-name "$2"\n' "${profile}"
  } > "${WRAPPER_PATH}"

  chmod 700 "${WRAPPER_PATH}"
}

# Run the AWS CLI with the mapped credentials in its environment. Assignments
# are exported inside a subshell rather than passed to `env`, whose arguments
# are world-readable through /proc while it runs.
_with_credentials() {
  local spec="$1" profile="$2" key ref
  shift 2

  (
    while IFS=$'\t' read -r key ref; do
      [[ -n "${key}" ]] || continue
      export "${key}=$(_ref_value "${ref}")"
    done < <(_credential_pairs "${spec}")
    aws --profile "${profile}" "$@"
  )
}

# Cluster names recorded in a kubeconfig this module generated: each user's exec
# args are "<region>", "<cluster>". Reading them back is how the all-failed path
# decides whether the file on disk still sits inside the project's selection.
_existing_clusters() {
  [[ -f "${KUBECONFIG_PATH}" ]] || return 0
  grep -o 'args: \["[^"]*", "[^"]*"\]' "${KUBECONFIG_PATH}" 2>/dev/null \
    | sed 's/.*", "\([^"]*\)"\]$/\1/' || true
}

# Only this project's own files are pruned. The wrapper is shared by every
# project on the machine, so deleting it here would break the others; it holds
# references, never values, and is harmless while unused.
_prune_generated() {
  local removed=0
  if [[ -e "${KUBECONFIG_PATH}" ]]; then
    rm -f "${KUBECONFIG_PATH}" && removed=1
  fi
  if [[ -e "${ENV_PATH}" ]]; then
    rm -f "${ENV_PATH}" && removed=1
  fi
  [[ "${removed}" -eq 1 ]]
}

# The machine-wide files of the previous implementation are the one artefact that
# can outlive this change: a shell that already sourced the old env file keeps
# pointing at a kubeconfig listing every cluster, so the per-project boundary is
# not enforced for it. Remove them once a scoped render succeeds — but only when
# the kubeconfig references our own wrapper, because a human's kubeconfig is
# never ours to delete.
_migrate_legacy() {
  if [[ ! -f "${LEGACY_KUBECONFIG}" ]]; then
    return 0
  fi
  grep -qF "${WRAPPER_PATH}" "${LEGACY_KUBECONFIG}" || return 0
  rm -f "${LEGACY_KUBECONFIG}" "${LEGACY_ENV}"
  _ok "kubectl — removed the legacy machine-wide kubeconfig and env"
}

main() {
  # Upgrade path, run before any return below: the machine-wide files of the
  # pre-selection implementation are shared, and a shell that already sourced
  # the old env file keeps pointing at them — so they must not survive an init
  # that bails out early either.
  _migrate_legacy

  local config spec slug selection
  config="$(_devbot_global_config)"
  spec="$(python3 "${READER}" "${config}" kubectl 2>/dev/null || true)"

  if [[ -z "${spec}" || "${spec}" == "null" ]]; then
    _skip "kubectl — no 'kubectl' node in the global config"
    return 0
  fi

  # Distinguish "not configured" from "configured with nothing": only the latter
  # prunes, so shipping the empty default never deletes a kubeconfig an agent
  # was already using.
  if [[ "$(echo "${spec}" | jq -r 'has("clusters")')" != "true" ]]; then
    _skip "kubectl — no clusters configured"
    return 0
  fi

  slug="$(_project_slug)"
  KUBECONFIG_PATH="${WORK_DIR}/${slug}.yaml"
  ENV_PATH="${WORK_DIR}/${slug}.env"

  _header_3 "kubectl init — ${slug}"

  if [[ "$(echo "${spec}" | jq -r '.clusters | length')" -eq 0 ]]; then
    if _prune_generated; then
      _ok "kubectl — no clusters configured; removed the generated kubeconfig for ${slug}"
    else
      _skip "kubectl — no clusters configured and nothing to prune"
    fi
    return 0
  fi

  selection="$(python3 "${READER}" "${PROJECT_CONFIG}" kubectl 2>/dev/null || true)"
  if [[ -z "${selection}" || "${selection}" == "null" ]]; then
    _skip "kubectl — no 'kubectl' selection in the project config; opt in with cluster names"
    return 0
  fi
  if [[ "$(echo "${selection}" | jq -r 'type')" != "array" ]]; then
    _warn "kubectl — the project's 'kubectl' must be an array of cluster names; skipping"
    return 0
  fi
  if [[ "$(echo "${selection}" | jq -r 'length')" -eq 0 ]]; then
    if _prune_generated; then
      _ok "kubectl — no clusters selected; removed the generated kubeconfig for ${slug}"
    else
      _skip "kubectl — no clusters selected and nothing to prune"
    fi
    return 0
  fi

  # Catalogue membership and the selection's size are decided before anything
  # environment-dependent: a selection that names no catalogue entry has to
  # revoke access even when AWS is unreachable or the credentials are stale,
  # otherwise a broken environment silently keeps the previous kubeconfig alive.
  local unknown
  while IFS= read -r unknown; do
    _warn "kubectl — cluster '${unknown}' is not in the global kubectl catalogue; leaving it out"
  done < <(echo "${spec}" | jq -r --argjson sel "${selection}" \
    '[.clusters[].name] as $have | $sel[] as $n | select(($have | index($n)) == null) | $n')

  local permitted
  permitted="$(echo "${spec}" | jq -c --argjson sel "${selection}" \
    '.clusters as $c
     | ($sel | reduce .[] as $x ([]; if index($x) then . else . + [$x] end)) as $s
     | [$s[] as $n | ($c[] | select(.name == $n)) | .name]')"

  # A selection that matches nothing is not a cluster that is temporarily
  # unavailable: it is a project whose access was removed, or renamed, or whose
  # catalogue entry went away. Keeping the previous file would leave the old
  # selection's credentials live, so prune it here — the "describe failed" case
  # below is the one that may keep what is on disk.
  if [[ "$(echo "${permitted}" | jq -r 'length')" -eq 0 ]]; then
    if _prune_generated; then
      _ok "kubectl — no selected cluster is in the global catalogue; removed the generated kubeconfig for ${slug}"
    else
      _skip "kubectl — no selected cluster is in the global catalogue and nothing to prune"
    fi
    return 0
  fi

  # Revoke anything wider than the permitted set *before* the environment is
  # touched. Every return below this point may leave the file on disk, so it
  # must already be within the selection — otherwise a missing AWS CLI, an
  # expired credential or a non-role profile would preserve access the project
  # has since dropped. The comparison is against the catalogue intersection, not
  # the raw selection: a name the catalogue no longer declares is not permitted
  # merely because the project still lists it.
  local stale=0 existing
  while IFS= read -r existing; do
    [[ -n "${existing}" ]] || continue
    if ! echo "${permitted}" | jq -e --arg c "${existing}" 'index($c) != null' >/dev/null; then
      stale=1
      break
    fi
  done < <(_existing_clusters)

  if [[ "${stale}" -eq 1 ]]; then
    if _prune_generated; then
      _ok "kubectl — the existing kubeconfig reached outside the selection; removed it"
    fi
  fi

  local profile
  profile="$(echo "${spec}" | jq -r '.profile // "devbot-agent"')"

  if ! command -v aws >/dev/null 2>&1; then
    _warn "kubectl — aws CLI not found; cannot resolve cluster endpoints"
    return 0
  fi
  if ! aws configure list-profiles 2>/dev/null | grep -Fxq "${profile}"; then
    _warn "kubectl — AWS profile '${profile}' is not configured; skipping"
    return 0
  fi
  _validate "${spec}" "${profile}" || return 0
  _verify_identity "${spec}" "${profile}" || return 0

  # Only clusters that answered get a user and a context. Emitting the rest
  # would produce a context whose cluster entry does not exist, and the
  # current-context could land on it.
  local -a names=() regions=() contexts=()
  local name region context endpoint ca block clusters_yaml=""

  while IFS=$'\t' read -r name region context; do
    [[ -n "${name}" ]] || continue
    if ! [[ "${name}" =~ ${NAME_RE} ]]; then
      _warn "kubectl — cluster name '${name}' is not valid; leaving it out"
      continue
    fi
    # The context is emitted as a YAML plain scalar: "team: prod" would be
    # parsed as a mapping and corrupt the file, so only simple names pass.
    if ! [[ "${context}" =~ ${NAME_RE} ]]; then
      _warn "kubectl — context '${context}' is not a valid kubeconfig name; using '${name}'"
      context="${name}"
    fi
    if ! endpoint=$(_with_credentials "${spec}" "${profile}" --region "${region}" \
      eks describe-cluster --name "${name}" --query 'cluster.endpoint' --output text 2>/dev/null); then
      _warn "kubectl — cannot describe cluster ${name} in ${region}; leaving it out"
      continue
    fi
    if ! ca=$(_with_credentials "${spec}" "${profile}" --region "${region}" \
      eks describe-cluster --name "${name}" --query 'cluster.certificateAuthority.data' --output text 2>/dev/null); then
      _warn "kubectl — no certificate authority for ${name}; leaving it out"
      continue
    fi
    names+=("${name}")
    regions+=("${region}")
    contexts+=("${context}")
    printf -v block '  - name: %s\n    cluster:\n      server: %s\n      certificate-authority-data: %s\n' \
      "${name}" "${endpoint}" "${ca}"
    clusters_yaml+="${block}"
  # Selection order becomes cluster order, so the first name the project lists
  # is the generated current-context. Duplicates are folded; an unknown name
  # simply matches nothing (reported above).
  done < <(echo "${spec}" | jq -r --argjson perm "${permitted}" \
    '.clusters as $c
     | $perm[] as $n
     | ($c[] | select(.name == $n))
     | "\(.name)\t\(.region)\t\(.context // .name)"')

  if [[ ${#names[@]} -eq 0 ]]; then
    # Nothing rendered. Anything wider than the selection was already revoked
    # above, so what is left is safe to keep through a transient failure.
    _warn "kubectl — no cluster could be described; leaving the existing kubeconfig untouched"
    return 0
  fi

  _write_wrapper "${spec}" "${profile}"
  _ok "kubectl — credential wrapper ${WRAPPER_PATH}"

  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/devbot-kubeconfig.XXXXXX")"
  {
    printf 'apiVersion: v1\nkind: Config\nclusters:\n'
    printf '%s' "${clusters_yaml}"
    printf 'users:\n'
    local i
    for i in "${!names[@]}"; do
      printf '  - name: devbot-%s\n    user:\n      exec:\n        apiVersion: client.authentication.k8s.io/v1beta1\n        command: %s\n        args: ["%s", "%s"]\n        interactiveMode: Never\n' \
        "${names[$i]}" "${WRAPPER_PATH}" "${regions[$i]}" "${names[$i]}"
    done
    printf 'contexts:\n'
    for i in "${!names[@]}"; do
      printf '  - name: %s\n    context:\n      cluster: %s\n      user: devbot-%s\n      namespace: default\n' \
        "${contexts[$i]}" "${names[$i]}" "${names[$i]}"
    done
    printf 'current-context: %s\n' "${contexts[0]}"
  } > "${tmp}"

  mkdir -p "$(dirname "${KUBECONFIG_PATH}")"
  mv "${tmp}" "${KUBECONFIG_PATH}"
  chmod 600 "${KUBECONFIG_PATH}"
  _ok "kubectl — ${KUBECONFIG_PATH}"

  # kubectl reads ~/.kube/config unless KUBECONFIG says otherwise, so a
  # generated file nobody points at is inert. A separate file rather than a
  # merge: mixing agent contexts into a human's admin kubeconfig is how a
  # `--context` typo reaches production.
  {
    printf '# Generated by dev-bot src/agentic/k8s/init.sh — do not edit.\n'
    printf '# Source this file to point kubectl at the generated config:\n'
    printf '#   . %s\n' "${ENV_PATH}"
    printf 'export KUBECONFIG="%s"\n' "${KUBECONFIG_PATH}"
  } > "${ENV_PATH}"
  chmod 600 "${ENV_PATH}"

  local ctx
  _info "  use: KUBECONFIG=${KUBECONFIG_PATH} kubectl --context <name> ..."
  for ctx in "${contexts[@]}"; do
    _info "  context ${ctx}"
  done
}

main "$@"

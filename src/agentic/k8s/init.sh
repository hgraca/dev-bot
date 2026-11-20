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
# The MCP server name per rendered cluster: `kctl-<key>`. One server per
# cluster is the scoping — the agent's tool list names the target, and the
# server can only run kubectl against that cluster's context.
#
# The runtime-manifest GROUP keeps the module's name (`k8s-<cluster>`): a
# disabled module's manifests are recognised by their filename, so the key may
# be shorter than the module but the file may not (docs/create-a-module.md).
MCP_PREFIX="kctl-"
MCP_GROUP_PREFIX="k8s-"
MCP_LAUNCHER="kctl-mcp.sh"
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

# The cluster object names in the generated file — the labels. A rename changes
# these while the exec args (the keys) stay put, so the stale check has to see
# both or a renamed entry survives an unavailable AWS.
_rendered_manifest_path() {
  printf '%s' "${KUBECONFIG_PATH%.yaml}.rendered"
}

# The cluster objects this module last rendered, one per line — the catalogue
# keys. Recorded rather than inferred: a static kubeconfig brings arbitrary
# object and user names, and a name-prefix heuristic cannot tell the two apart.
_existing_rendered() {
  local manifest
  manifest="$(_rendered_manifest_path)"
  [[ -f "${manifest}" ]] || return 0
  cat "${manifest}" 2>/dev/null || true
}

# Static entries carry no exec block, so the AWS-shaped grep above cannot see
# them. What was rendered is recorded in a sidecar manifest next to the
# kubeconfig — deriving it from the catalogue cannot see an entry that has since
# been removed, and that is exactly the case revocation must catch.
_static_manifest_path() {
  printf '%s' "${KUBECONFIG_PATH%.yaml}.static"
}

# The catalogue's current kind for a cluster name: "static", "eks", or empty
# when the name is no longer declared.
_catalogue_kind() {
  local spec="$1" target="$2"
  echo "${spec}" | jq -r --arg n "${target}" \
    '.clusters | to_entries[]
     | select(.key == $n)
     | (.value.type // "eks")' 2>/dev/null | head -1
}

_existing_static_clusters() {
  local spec="$1" name context manifest
  [[ -f "${KUBECONFIG_PATH}" ]] || return 0
  manifest="$(_static_manifest_path)"

  if [[ -f "${manifest}" ]]; then
    local present=""
    present="$(kubectl --kubeconfig "${KUBECONFIG_PATH}" config get-contexts -o name 2>/dev/null || true)"
    while IFS=$'\t' read -r name context kind; do
      [[ -n "${name}" ]] || continue
      # Fail closed: an unreadable generated file is not evidence that the entry
      # is gone, and the manifest is the only durable record of what was
      # rendered. Reporting it keeps revocation working when kubectl cannot read.
      if [[ -z "${present}" ]] || grep -Fxq "${context}" <<<"${present}"; then
        printf '%s\n' "${name}"
      fi
    done < "${manifest}"
    return 0
  fi

  # No manifest: a file rendered before it existed. Fall back to the catalogue,
  # applying the same valid-name fallback the render applies.
  while IFS=$'\t' read -r name context; do
    [[ -n "${name}" ]] || continue
    if ! [[ "${context}" =~ ${NAME_RE} ]]; then
      context="${name}"
    fi
    if kubectl --kubeconfig "${KUBECONFIG_PATH}" config get-contexts -o name 2>/dev/null \
      | grep -Fxq "${context}"; then
      printf '%s\n' "${name}"
    fi
  done < <(echo "${spec}" | jq -r \
    '.clusters | to_entries[]
     | select((.value.type // "eks") == "static")
     | "\(.key)\t\(.value.context // .key)"')
}

# Only this project's own files are pruned. The wrapper is shared by every
# project on the machine, so deleting it here would break the others; it holds
# references, never values, and is harmless while unused.
#
# Retiring the MCP servers here keeps them and the kubeconfig in step: every
# path that removes the project's kubeconfig also means no cluster of this
# project is reachable, and a `kctl-<key>` server left registered would fail
# one tool call at a time instead of being absent.
_prune_generated() {
  local removed=0
  if [[ -e "${KUBECONFIG_PATH}" ]]; then
    rm -f "${KUBECONFIG_PATH}" && removed=1
  fi
  if [[ -e "${ENV_PATH}" ]]; then
    rm -f "${ENV_PATH}" && removed=1
  fi
  if [[ -e "$(_static_manifest_path)" ]]; then
    rm -f "$(_static_manifest_path)" && removed=1
  fi
  if [[ -e "$(_rendered_manifest_path)" ]]; then
    rm -f "$(_rendered_manifest_path)" && removed=1
  fi
  _retire_mcps
  [[ "${removed}" -eq 1 ]]
}

# ── MCP exposure ─────────────────────────────────────────────────────────────
#
# One stdio server per rendered cluster, published through the harness-agnostic
# runtime manifest (the aws/datasources contract): init declares, the harness
# applies. The command is secret-free — it names the cluster, and kctl.sh
# resolves the kubeconfig, the context and the credential references at call
# time. `{harness-dir}` is a translator token, so no harness is named here.
#
# The argument is the catalogue key: it names the server, the manifest group and
# what kctl.sh resolves, so one identifier reaches from the config to the tool.
_wire_mcps() {
  local name group
  local -a keep=()

  for name in "$@"; do
    group="${MCP_GROUP_PREFIX}${name}"
    if ! _devbot_publish_runtime_mcp "${PROJECT_DIR}" "${group}" \
      "$(jq -nc --arg s "${MCP_PREFIX}${name}" --arg c \
        "mkdir -p .agents/logs && exec bash {harness-dir}/${MCP_LAUNCHER} ${name} 2>>.agents/logs/${MCP_PREFIX}${name}-mcp.log" \
        '{($s): {type: "stdio", command: ["bash", "-c", $c]}}')"; then
      # Not in `keep`: the previous manifest for this cluster is pruned below,
      # so a failed publish leaves the server absent rather than stale.
      _warn "kubectl — could not publish the ${MCP_PREFIX}${name} MCP manifest"
      continue
    fi
    keep+=("${group}")
    _ok "kubectl — MCP ${MCP_PREFIX}${name}"
  done

  _devbot_prune_runtime_mcp "${PROJECT_DIR}" "${MCP_GROUP_PREFIX}" ${keep[@]+"${keep[@]}"}
  _devbot_apply_runtime_mcps "${PROJECT_DIR}"
}

# Prune when the project's own name cannot be read: the slug's name half comes
# from the project config, but its hash half is the path's alone, so the hash
# still identifies every file this project rendered.
_prune_by_hash() {
  local suffix f removed=0
  suffix="$(_project_slug)"
  suffix="${suffix##*-}"
  for f in "${WORK_DIR}/"*"-${suffix}.yaml" "${WORK_DIR}/"*"-${suffix}.env" \
           "${WORK_DIR}/"*"-${suffix}.rendered" "${WORK_DIR}/"*"-${suffix}.static"; do
    [[ -e "${f}" ]] || continue
    rm -f "${f}" && removed=1
  done
  _retire_mcps
  [[ "${removed}" -eq 1 ]]
}

# Drop every `kctl-*` server for this project — no cluster is reachable.
_retire_mcps() {
  _devbot_prune_runtime_mcp "${PROJECT_DIR}" "${MCP_GROUP_PREFIX}"
  _devbot_apply_runtime_mcps "${PROJECT_DIR}"
}

# The module's always-on instructions belong to the module, not to the project's
# project.md: reinit clears active/modules/ and every enabled module rewrites its
# own file, so the text has one source and no per-project copy to drift.
#
# The rule it carries is absolute — no kubectl in any shell — so it is written
# whenever the module is enabled, not only when a cluster renders. A project
# whose credentials are stale would otherwise lose the prohibition exactly when
# plain kubectl looks most tempting.
_write_memory() {
  if ! _devbot_write_module_memory "${PROJECT_DIR}" "k8s.md" "${MODULE_DIR}/k8s.md"; then
    _skip "kubectl — module memory not written"
    return 0
  fi
  _ok "kubectl — active/modules/k8s.md"
}

# Vendored skills are checkouts: init fetches them.
# Subshell: the library reassigns MODULE_DIR.
_ensure_external_skills() {
  (
    # shellcheck source=../../tools/external-modules/functions.sh
    source "${MODULE_DIR}/../../tools/external-modules/functions.sh"
    _external_module_ensure_declared k8s "${DEV_BOT_ROOT}"
  ) || _warn "agentgateway skill not fetched into vendor/ — check the network"
}

# Is the k8s module itself turned off for this project? `_run_module_script`
# already skips a disabled module's init.sh; this guard keeps a direct run
# (`bash init.sh`) from writing instructions a disabled module does not own.
_k8s_module_disabled() {
  _devbot_get_disabled_modules "${PROJECT_DIR}" |
    jq -e 'index("k8s") != null' >/dev/null 2>&1
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

# Index of the cluster whose catalogue name the project name names, or -1.
# The name decides, not the position: every project lists the same clusters in
# the same order, so position says nothing about which one it works on. The
# longest match wins (`gete-dev` over `gete`); -1 hands the caller its
# first-rendered fallback.
#
# Args: <project-name> <cluster-name>...
_default_index() {
  local project="$1" name best=-1 best_len=0 n=0
  shift

  for name in "$@"; do
    if [[ "${project}" == "${name}" || "${project}" == *"-${name}" ]] \
      && [[ "${#name}" -gt "${best_len}" ]]; then
      best="${n}"
      best_len="${#name}"
    fi
    n=$((n + 1))
  done

  printf '%s' "${best}"
}

main() {
  # Upgrade path, run before any return below: the machine-wide files of the
  # pre-selection implementation are shared, and a shell that already sourced
  # the old env file keeps pointing at them — so they must not survive an init
  # that bails out early either.
  _migrate_legacy

  # The prohibition on plain kubectl is the module's, not the render's: write it
  # before every return below, so a project with no cluster (or with a broken
  # AWS environment) still learns that the shell is off limits.
  if _k8s_module_disabled; then
    _devbot_remove_module_memory "${PROJECT_DIR}" "k8s.md"
    _skip "kubectl — module disabled for this project; k8s.md not written"
    # Disabling the module revokes what an earlier, enabled run generated. This
    # only matters when the script is run directly (init skips a disabled
    # module), and then leaving a kubeconfig and live servers behind would be
    # the one thing the module exists to prevent.
    #
    # Manifests are removed here; the aggregate a harness keeps (claudecode's
    # `.mcp.json`) is regenerated from scratch by that harness, because a module
    # never writes a harness manifest. `devbot reinit` therefore finishes the
    # revocation, which is the documented way to change the module set.
    KUBECONFIG_PATH="${WORK_DIR}/$(_project_slug).yaml"
    ENV_PATH="${KUBECONFIG_PATH%.yaml}.env"
    if _prune_generated; then
      _ok "kubectl — module disabled; removed the generated kubeconfig and MCP manifests"
    fi
    return 0
  fi

  _write_memory

  _ensure_external_skills

  local config spec slug selection project
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

  # The array form predates the keyed catalogue: it gives one `name` to the AWS
  # cluster, the kubeconfig objects and the MCP server key. Refused by name, and
  # the previous render is revoked with it — a refusal that leaves the old
  # kubeconfig live is not a refusal.
  if [[ "$(echo "${spec}" | jq -r '.clusters | type')" != "object" ]]; then
    _prune_generated || true
    _fatal "kubectl — 'kubectl.clusters' must be an object keyed by cluster name; run 'devbot update' to migrate it"
    return 1
  fi

  if [[ "$(echo "${spec}" | jq -r '.clusters | length')" -eq 0 ]]; then
    if _prune_generated; then
      _ok "kubectl — no clusters configured; removed the generated kubeconfig for ${slug}"
    else
      _skip "kubectl — no clusters configured and nothing to prune"
    fi
    return 0
  fi

  if [[ ! -f "${PROJECT_CONFIG}" ]]; then
    _skip "kubectl — no project config; nothing to render"
    return 0
  fi

  # A project config that will not parse is a configuration error, not an
  # opt-out: keeping the previous render live would keep access the file no
  # longer describes.
  local selection_rc=0
  selection="$(python3 "${READER}" "${PROJECT_CONFIG}" kubectl 2>/dev/null)" || selection_rc=$?
  if [[ "${selection_rc}" -ne 0 ]]; then
    _prune_by_hash || true
    _fatal "kubectl — ${PROJECT_CONFIG##*/} cannot be read; fix it and run devbot reinit"
    return 1
  fi
  if [[ -z "${selection}" || "${selection}" == "null" ]]; then
    _skip "kubectl — no 'kubectl' selection in the project config; opt in with catalogue keys"
    return 0
  fi
  if [[ "$(echo "${selection}" | jq -r 'type')" != "array" ]]; then
    _prune_generated || true
    _fatal "kubectl — the project's 'kubectl' must be an array of catalogue keys; refusing to keep a render it no longer describes"
    return 1
  fi
  if [[ "$(echo "${selection}" | jq -r 'length')" -eq 0 ]]; then
    if _prune_generated; then
      _ok "kubectl — no clusters selected; removed the generated kubeconfig for ${slug}"
    else
      _skip "kubectl — no clusters selected and nothing to prune"
    fi
    return 0
  fi

  # Read once, here: both the excluded-match warning below and the
  # current-context choice at the end of the render depend on it.
  project="$(_project_name)"

  # Catalogue membership and the selection's size are decided before anything
  # environment-dependent: a selection that names no catalogue entry has to
  # revoke access even when AWS is unreachable or the credentials are stale,
  # otherwise a broken environment silently keeps the previous kubeconfig alive.
  local unknown
  while IFS= read -r unknown; do
    _warn "kubectl — cluster '${unknown}' is not in the global kubectl catalogue; leaving it out"
  done < <(echo "${spec}" | jq -r --argjson sel "${selection}" \
    '(.clusters | keys) as $have | $sel[] as $n | select(($have | index($n)) == null) | $n')

  local permitted
  permitted="$(echo "${spec}" | jq -c --argjson sel "${selection}" \
    '.clusters as $c
     | ($sel | reduce .[] as $x ([]; if index($x) then . else . + [$x] end)) as $s
     | [$s[] as $n | select($c | has($n)) | $n]')"

  # A catalogue that cannot be rendered unambiguously is refused here, before any
  # file is written or left behind: the previous render is revoked, because a
  # refusal that keeps the old kubeconfig alive is not a refusal.
  #
  # The key names the MCP server and the kubeconfig objects; `name` names the AWS
  # EKS cluster and is required. Every value is validated from JSON, never
  # through a field-separated round trip — a name holding a tab would otherwise
  # be cut down to a valid one.
  local -a catalogue_errors=()
  local bad
  bad="$(echo "${spec}" | jq -r \
    '[.clusters | to_entries[] | select((.value | type) != "object") | .key] | first // empty')"
  if [[ -n "${bad}" ]]; then
    _prune_generated || true
    _fatal "kubectl — refusing the kubectl catalogue: cluster '${bad}' is not an object"
    return 1
  fi
  bad="$(echo "${spec}" | jq -r --arg re "${NAME_RE}" \
    '[.clusters | keys[] | select(test($re) | not)] | first // empty')"
  [[ -n "${bad}" ]] && catalogue_errors+=("key '${bad}' is not a valid name; it names the MCP server and the kubeconfig objects")
  bad="$(echo "${spec}" | jq -r \
    '[.clusters | to_entries[] | select(.value | has("name") | not) | .key] | first // empty')"
  [[ -n "${bad}" ]] && catalogue_errors+=("cluster '${bad}' has no \"name\"; the AWS cluster name is required")
  bad="$(echo "${spec}" | jq -r \
    '[.clusters | to_entries[] | select(.value | has("name")) | select((.value.name | type) != "string") | .key] | first // empty')"
  [[ -n "${bad}" ]] && catalogue_errors+=("cluster '${bad}' has a \"name\" that is not a string")
  bad="$(echo "${spec}" | jq -r \
    '[.clusters | to_entries[] | select(.value | has("context")) | select((.value.context | type) != "string") | .key] | first // empty')"
  [[ -n "${bad}" ]] && catalogue_errors+=("cluster '${bad}' has a \"context\" that is not a string")
  bad="$(echo "${spec}" | jq -r --arg re "${NAME_RE}" \
    '[.clusters | to_entries[] | select((.value.name | type) == "string") | .value.name | select(test($re) | not)] | first // empty')"
  [[ -n "${bad}" ]] && catalogue_errors+=("the AWS cluster name '${bad}' is not valid")
  # The render falls back to the key when `context` is not a plain name, so the
  # comparison has to apply the same fallback or it checks a value nobody uses.
  bad="$(echo "${spec}" | jq -r --arg re "${NAME_RE}" \
    '[.clusters | to_entries[]
      | (if (.value.context | type) == "string" then .value.context else "" end) as $c
      | (if ($c | test($re)) then $c else .key end)]
     | group_by(.) | map(select(length > 1)) | .[0][0] // empty')"
  [[ -n "${bad}" ]] && catalogue_errors+=("two catalogue entries share the context '${bad}'; kubectl could reach the wrong cluster")

  if [[ ${#catalogue_errors[@]} -gt 0 ]]; then
    _prune_generated || true
    _fatal "kubectl — refusing the kubectl catalogue: ${catalogue_errors[0]}"
    return 1
  fi

  # The key is what the generated cluster objects and every `kctl-*` server
  # carry, and what the project name matches on. The AWS cluster name is used by
  # the two EKS calls and by the exec args the wrapper is called with.
  local aws_json
  aws_json="$(echo "${spec}" | jq -c --argjson perm "${permitted}" \
    '.clusters as $c | [$perm[] as $n | $c[$n].name]')"

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


  # The incident in another shape: the name says staging, the fallback says
  # production, and without this the only trace is init's `(default)` marker.
  # The message stops at "cannot be the default": a shorter *selected* match may
  # still win, so the fallback is not necessarily the first rendered cluster.
  local excluded
  while IFS= read -r excluded; do
    _warn "kubectl — the project name '${project}' names cluster '${excluded}', which this project does not select, so it cannot be the default context"
  done < <(echo "${spec}" | jq -r --arg p "${project}" --argjson perm "${permitted}" '
    .clusters
    | keys[] as $k
    | select((($p == $k) or ($p | endswith("-" + $k))) and (($perm | index($k)) == null))
    | $k')

  # Revoke anything wider than the permitted set *before* the environment is
  # touched. Every return below this point may leave the file on disk, so it
  # must already be within the selection — otherwise a missing AWS CLI, an
  # expired credential or a non-role profile would preserve access the project
  # has since dropped. The comparison is against the catalogue intersection, not
  # the raw selection: a name the catalogue no longer declares is not permitted
  # merely because the project still lists it.
  local stale=0 existing
  # A render with no record predates it, so its objects cannot be verified.
  # Invalidate it once instead of trusting it: the next successful render writes
  # the record, and an unavailable AWS must not keep stale names live meanwhile.
  if [[ -f "${KUBECONFIG_PATH}" && ! -f "$(_rendered_manifest_path)" ]]; then
    _warn "kubectl — the generated kubeconfig predates the render record; removing it so the next render records it"
    stale=1
  fi

  # Each source is compared against the names it was rendered from: the exec args
  # carry the AWS cluster name, the generated objects carry the key.
  if [[ "${stale}" -eq 0 ]]; then
  while IFS= read -r existing; do
    [[ -n "${existing}" ]] || continue
    if ! echo "${aws_json}" | jq -e --arg c "${existing}" 'index($c) != null' >/dev/null; then
      stale=1
      break
    fi
  done < <(_existing_clusters)
  fi

  if [[ "${stale}" -eq 0 ]]; then
    while IFS= read -r existing; do
      [[ -n "${existing}" ]] || continue
      if ! echo "${permitted}" | jq -e --arg c "${existing}" 'index($c) != null' >/dev/null; then
        stale=1
        break
      fi
    done < <( { _existing_rendered; _existing_static_clusters "${spec}"; } )
  fi

  if [[ "${stale}" -eq 1 ]]; then
    if _prune_generated; then
      _ok "kubectl — the existing kubeconfig reached outside the selection; removed it"
    fi
  fi

  # A manifest entry whose catalogue kind is no longer "static" describes a
  # render that cannot be reproduced: swapping an entry for an EKS one under the
  # same name must not leave the old static credentials usable. This runs before
  # the AWS gate, because an unavailable AWS would otherwise preserve them.
  if [[ -f "$(_static_manifest_path)" ]]; then
    local mname
    while IFS=$'\t' read -r mname _ _; do
      [[ -n "${mname}" ]] || continue
      if [[ "$(_catalogue_kind "${spec}" "${mname}")" != "static" ]]; then
        if _prune_generated; then
          _warn "kubectl — static cluster ${mname} is no longer a static entry; removed the generated kubeconfig"
        fi
        break
      fi
    done < "$(_static_manifest_path)"
  fi

  local profile
  profile="$(echo "${spec}" | jq -r '.profile // "devbot-agent"')"

  # A catalogue entry is EKS unless it declares `type: "static"`: that one names a
  # kubeconfig this module reduces to the selected context, so it needs no AWS.
  local has_eks has_static
  has_eks="$(echo "${spec}" | jq -r --argjson perm "${permitted}" \
    '[.clusters as $c | $perm[] as $n | $c[$n] | select((.type // "eks") != "static")] | length')"
  has_static="$(echo "${spec}" | jq -r --argjson perm "${permitted}" \
    '[.clusters as $c | $perm[] as $n | $c[$n] | select((.type // "eks") == "static")] | length')"

  # An unusable AWS environment aborts the render only when EKS clusters are all
  # the project has; a mixed selection still gets its static clusters.
  local aws_ready=1
  if [[ "${has_eks}" -gt 0 ]]; then
    if ! command -v aws >/dev/null 2>&1; then
      _warn "kubectl — aws CLI not found; cannot resolve cluster endpoints"
      aws_ready=0
    elif ! aws configure list-profiles 2>/dev/null | grep -Fxq "${profile}"; then
      _warn "kubectl — AWS profile '${profile}' is not configured; skipping"
      aws_ready=0
    elif ! _validate "${spec}" "${profile}"; then
      aws_ready=0
    elif ! _verify_identity "${spec}" "${profile}"; then
      aws_ready=0
    fi
    if [[ "${aws_ready}" -eq 0 && "${has_static}" -eq 0 ]]; then
      return 0
    fi
  fi

  # Only clusters that answered get a user and a context. Emitting the rest
  # would produce a context whose cluster entry does not exist, and the
  # current-context could land on it.
  local -a names=() aws_names=() regions=() contexts=() kinds=() files=()
  local dropped_static=0

  local name aws kind region context endpoint ca file block clusters_yaml=""

  while IFS=$'\t' read -r name aws kind region context; do
    [[ -n "${name}" ]] || continue
    # The context is emitted as a YAML plain scalar: "team: prod" would be
    # parsed as a mapping and corrupt the file, so only simple names pass.
    if ! [[ "${context}" =~ ${NAME_RE} ]]; then
      _warn "kubectl — context '${context}' is not a valid kubeconfig name; using '${name}'"
      context="${name}"
    fi
    if [[ "${kind}" == "static" ]]; then
      file="$(echo "${spec}" | jq -r --arg n "${name}" \
        '.clusters[$n].kubeconfig // ""')"
      if [[ -z "${file}" || ! -r "${file}" ]]; then
        _warn "kubectl — static cluster ${name}: kubeconfig '${file}' is not readable; leaving it out"
        dropped_static=1
        continue
      fi
      # The context is the key the generated file will expose; it has to exist
      # in the file being merged or the resulting kubeconfig is unusable.
      if ! kubectl --kubeconfig "${file}" config get-contexts -o name 2>/dev/null \
        | grep -Fxq "${context}"; then
        _warn "kubectl — static cluster ${name}: context '${context}' is not in ${file}; leaving it out"
        dropped_static=1
        continue
      fi
      names+=("${name}")
      aws_names+=("${aws}")
      regions+=("-")
      contexts+=("${context}")
      kinds+=("static")
      files+=("${file}")
      continue
    fi
    if [[ "${aws_ready}" -eq 0 ]]; then
      _warn "kubectl — cannot describe cluster ${name}: AWS is not usable; leaving it out"
      continue
    fi
    # The payload uses "-" for a missing field so an empty column cannot shift
    # the later ones (IFS collapsing).
    if [[ "${region}" == "-" ]]; then
      region=""
    fi
    if ! endpoint=$(_with_credentials "${spec}" "${profile}" --region "${region}" \
      eks describe-cluster --name "${aws}" --query 'cluster.endpoint' --output text 2>/dev/null); then
      _warn "kubectl — cannot describe cluster ${name} in ${region}; leaving it out"
      continue
    fi
    if ! ca=$(_with_credentials "${spec}" "${profile}" --region "${region}" \
      eks describe-cluster --name "${aws}" --query 'cluster.certificateAuthority.data' --output text 2>/dev/null); then
      _warn "kubectl — no certificate authority for ${name}; leaving it out"
      continue
    fi
    names+=("${name}")
    aws_names+=("${aws}")
    regions+=("${region}")
    contexts+=("${context}")
    kinds+=("eks")
    files+=("")
    printf -v block '  - name: %s\n    cluster:\n      server: %s\n      certificate-authority-data: %s\n' \
      "${name}" "${endpoint}" "${ca}"
    clusters_yaml+="${block}"
  # Selection order only decides which cluster the file lists first; the
  # current-context is chosen below by project name. Duplicates are folded; an
  # unknown name matches nothing (reported above).
  done < <(echo "${spec}" | jq -r --argjson perm "${permitted}" \
    '.clusters as $c
     | $perm[] as $n
     | $c[$n] as $e
     | "\($n)\t\($e.name)\t\($e.type // "eks")\t\(if ($e.region // "") == "" then "-" else $e.region end)\t\($e.context // $n)"')

  # A static kubeconfig may hold more than the context this project selected:
  # another cluster, another user, an admin context. Reduce each one to its
  # selected context, and drop any whose object names the generated file already
  # uses — kubectl resolves duplicate names in favour of the first file, so a
  # collision would silently point the context at another cluster.
  local -A taken=()
  local ki
  for ki in "${!names[@]}"; do
    if [[ "${kinds[$ki]}" == "eks" ]]; then
      taken["${names[$ki]}"]=1
      taken["${contexts[$ki]}"]=1
      taken["devbot-${names[$ki]}"]=1
    fi
  done

  local -a keep_names=() keep_aws=() keep_regions=() keep_contexts=() keep_kinds=() keep_files=()
  local mini object collide
  for ki in "${!names[@]}"; do
    if [[ "${kinds[$ki]}" != "static" ]]; then
      keep_names+=("${names[$ki]}")
      keep_aws+=("${aws_names[$ki]}")
      keep_regions+=("${regions[$ki]}")
      keep_contexts+=("${contexts[$ki]}")
      keep_kinds+=("eks")
      keep_files+=("${files[$ki]}")
      continue
    fi

    mini="$(mktemp "${TMPDIR:-/tmp}/devbot-kubeconfig-mini.XXXXXX")"
    if ! kubectl --kubeconfig "${files[$ki]}" config view --minify --flatten --raw \
      --context "${contexts[$ki]}" >"${mini}" 2>/dev/null; then
      rm -f "${mini}"
      _warn "kubectl — static cluster ${names[$ki]}: could not reduce it to context ${contexts[$ki]}; leaving it out"
      dropped_static=1
      continue
    fi

    collide=0
    while IFS= read -r object; do
      [[ -n "${object}" ]] || continue
      if [[ -n "${taken["${object}"]:-}" ]]; then
        collide=1
        break
      fi
    done < <(kubectl --kubeconfig "${mini}" config view --raw -o json 2>/dev/null \
      | jq -r '(.clusters[]?.name), (.contexts[]?.name), (.users[]?.name)')
    if [[ "${collide}" -eq 1 ]]; then
      rm -f "${mini}"
      _warn "kubectl — static cluster ${names[$ki]}: a cluster, context or user name collides with another selected cluster; leaving it out"
      dropped_static=1
      continue
    fi

    while IFS= read -r object; do
      [[ -n "${object}" ]] || continue
      taken["${object}"]=1
    done < <(kubectl --kubeconfig "${mini}" config view --raw -o json 2>/dev/null \
      | jq -r '(.clusters[]?.name), (.contexts[]?.name), (.users[]?.name)')

    keep_names+=("${names[$ki]}")
    keep_aws+=("${aws_names[$ki]}")
    keep_regions+=("-")
    keep_contexts+=("${contexts[$ki]}")
    keep_kinds+=("static")
    keep_files+=("${mini}")
  done

  names=("${keep_names[@]}")
  aws_names=("${keep_aws[@]}")
  regions=("${keep_regions[@]}")
  contexts=("${keep_contexts[@]}")
  kinds=("${keep_kinds[@]}")
  files=("${keep_files[@]}")

  if [[ ${#names[@]} -eq 0 ]]; then
    # A static entry that cannot be rendered any more is not a transient
    # failure: the previous render is stale, and keeping it would keep its
    # credentials usable. Anything wider than the selection was revoked above.
    if [[ "${dropped_static}" -eq 1 ]]; then
      if _prune_generated; then
        _warn "kubectl — a selected static cluster could not be rendered; removed the generated kubeconfig"
      fi
      return 0
    fi
    _warn "kubectl — no cluster could be described; leaving the existing kubeconfig untouched"
    return 0
  fi

  # A name match on a cluster that could not be described was dropped above, so
  # it falls back like any other miss: the current-context never points at a
  # context the file lacks.
  local idx default_context
  idx="$(_default_index "${project}" "${names[@]}")"
  if [[ "${idx}" -ge 0 ]]; then
    default_context="${contexts[${idx}]}"
  else
    default_context="${contexts[0]}"
  fi

  local i eks_count=0
  for i in "${!names[@]}"; do
    if [[ "${kinds[$i]}" == "eks" ]]; then
      eks_count=$((eks_count + 1))
    fi
  done
  if [[ "${eks_count}" -gt 0 && "${aws_ready}" -eq 1 ]]; then
    _write_wrapper "${spec}" "${profile}"
    _ok "kubectl — credential wrapper ${WRAPPER_PATH}"
  fi

  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/devbot-kubeconfig.XXXXXX")"
  {
    printf 'apiVersion: v1\nkind: Config\nclusters:\n'
    printf '%s' "${clusters_yaml}"
    if [[ "${eks_count}" -eq 0 ]]; then
      printf 'users: []\n'
    else
      printf 'users:\n'
      for i in "${!names[@]}"; do
        if [[ "${kinds[$i]}" == "eks" ]]; then
          printf '  - name: devbot-%s\n    user:\n      exec:\n        apiVersion: client.authentication.k8s.io/v1beta1\n        command: %s\n        args: ["%s", "%s"]\n        interactiveMode: Never\n' \
            "${names[$i]}" "${WRAPPER_PATH}" "${regions[$i]}" "${aws_names[$i]}"
        fi
      done
    fi
    if [[ "${eks_count}" -eq 0 ]]; then
      printf 'contexts: []\n'
    else
      printf 'contexts:\n'
      for i in "${!names[@]}"; do
        if [[ "${kinds[$i]}" == "eks" ]]; then
          printf '  - name: %s\n    context:\n      cluster: %s\n      user: devbot-%s\n      namespace: default\n' \
            "${contexts[$i]}" "${names[$i]}" "${names[$i]}"
        fi
      done
    fi
    printf 'current-context: %s\n' "${default_context}"
  } > "${tmp}"

  # Static entries already hold their own cluster, user and context — and their
  # auth may be a client certificate, a token or anything else. Merge those
  # files in rather than reconstructing them.
  local -a static_files=()
  for i in "${!names[@]}"; do
    if [[ "${kinds[$i]}" == "static" ]]; then
      static_files+=("${files[$i]}")
    fi
  done
  if [[ ${#static_files[@]} -gt 0 ]]; then
    local merged joined="${tmp}" f
    for f in "${static_files[@]}"; do joined="${joined}:${f}"; done
    merged="$(mktemp "${TMPDIR:-/tmp}/devbot-kubeconfig-merged.XXXXXX")"
    if ! KUBECONFIG="${joined}" kubectl config view --flatten --raw > "${merged}" 2>/dev/null; then
      rm -f "${merged}" "${tmp}"
      # The accepted static entries are copies of their authentication data.
      for f in "${static_files[@]}"; do rm -f "${f}"; done
      _warn "kubectl — could not merge the static kubeconfigs; leaving the existing kubeconfig untouched"
      return 0
    fi
    rm -f "${tmp}"
    tmp="${merged}"
    # --flatten keeps the first file's current-context; the default is decided
    # by project name, so set it explicitly on the merged result.
    kubectl --kubeconfig "${tmp}" config use-context "${default_context}" >/dev/null 2>&1 || true
  fi

  mkdir -p "$(dirname "${KUBECONFIG_PATH}")"
  mv "${tmp}" "${KUBECONFIG_PATH}"
  chmod 600 "${KUBECONFIG_PATH}"

  local static_count=0 mi
  for mi in "${!names[@]}"; do
    if [[ "${kinds[$mi]}" == "static" ]]; then
      static_count=$((static_count + 1))
    fi
  done
  if [[ "${static_count}" -gt 0 ]]; then
    for mi in "${!names[@]}"; do
      if [[ "${kinds[$mi]}" == "static" ]]; then
        printf '%s\t%s\n' "${names[$mi]}" "${contexts[$mi]}"
        rm -f "${files[$mi]}"
      fi
    done >"$(_static_manifest_path)"
    chmod 600 "$(_static_manifest_path)"
  else
    rm -f "$(_static_manifest_path)"
  fi

  printf '%s\n' "${names[@]}" >"$(_rendered_manifest_path)"
  chmod 600 "$(_rendered_manifest_path)"

  _ok "kubectl — ${KUBECONFIG_PATH}"

  # One MCP server per rendered cluster. Published from the rendered set, not
  # the selection: a cluster the render dropped has no context in the file, so
  # its server could only ever fail.
  _wire_mcps "${names[@]}"

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
    if [[ "${ctx}" == "${default_context}" ]]; then
      _info "  context ${ctx} (default)"
    else
      _info "  context ${ctx}"
    fi
  done
}

main "$@"

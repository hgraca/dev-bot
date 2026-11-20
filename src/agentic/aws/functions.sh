#!/usr/bin/env bash
# src/agentic/aws/functions.sh
# Shared helpers — delegates to src/_shared/functions.sh for boilerplate.

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_shared/functions.sh
source "${MODULE_DIR}/../../_shared/functions.sh"

# The AWS MCP proxy runs as an installed uv tool, never resolved at launch:
# `uvx` re-resolves the whole dependency graph against PyPI on every start, and a
# single stalled request outruns the MCP client's 30 s init budget.
#
# `-cli` (not the bare library) is AWS's designated CLI artifact: it exact-pins
# the whole tree, so one version resolves identically on every machine.
MCP_PROXY_PACKAGE='mcp-proxy-for-aws-cli'
MCP_PROXY_VERSION='1.7.0'

# The agent-rules pin. The committed versions.env.dist ships the default; the
# machine-local versions.env (gitignored) is what `devbot update` bumps, so a
# bump never leaves the release checkout dirty.
AWS_RULES_REF=""
_devbot_versions_env_source "${MODULE_DIR}"

# Install the pinned proxy as a uv tool. Idempotent: an exact-version match is
# skipped, so this is safe to call from both install.sh and update.sh.
_mcp_proxy_install() {
  local spec="${MCP_PROXY_PACKAGE}==${MCP_PROXY_VERSION}"
  # Capture before matching: under `pipefail`, `grep -q` exiting on the first
  # match sends SIGPIPE to uv, so a present tool would read as absent.
  local listed
  listed="$(uv tool list 2>/dev/null || true)"
  if grep -qE "^${MCP_PROXY_PACKAGE} v${MCP_PROXY_VERSION}$" <<<"${listed}"; then
    _skip "${MCP_PROXY_PACKAGE} (v${MCP_PROXY_VERSION})"
    return 0
  fi
  _info "Installing the AWS MCP proxy (${spec})..."
  if uv tool install "${spec}" 2>&1 | sed 's/^/  /'; then
    _ok "${MCP_PROXY_PACKAGE} installed"
    return 0
  fi
  _warn "Failed to install ${spec} — the AWS MCP server will not start until it is installed"
  return 1
}

# ── Agent rules ───────────────────────────────────────────────────────────────
# AWS publishes the rules an agent follows at this repo/path; init.sh appends
# them to the module memory file.

AWS_RULES_REPO='https://github.com/aws/agent-toolkit-for-aws'
AWS_RULES_PATH='rules/aws-agent-rules.md'

_aws_rules_dir() {
  printf '%s\n' "${DEV_BOT_ROOT:-$(cd "${MODULE_DIR}/../../.." && pwd)}/storage/aws/rules"
}

_aws_rules_file() {
  printf '%s\n' "$(_aws_rules_dir)/aws-agent-rules.md"
}

_aws_rules_url() {
  printf 'https://raw.githubusercontent.com/aws/agent-toolkit-for-aws/%s/%s\n' \
    "${1:-${AWS_RULES_REF}}" "${AWS_RULES_PATH}"
}

# The artifact names its own ref, so a reader can tell whether it matches the
# pin — and a crash between the two renames is repairable, not silent.
_aws_rules_marker() {
  printf '<!-- aws-agent-rules ref: %s -->\n' "$1"
}

# Echo the ref the stored artifact names; empty when it names none.
_aws_rules_stored_ref() {
  local file
  file="$(_aws_rules_file)"
  [[ -s "${file}" ]] || return 0
  sed -n '1s/^<!-- aws-agent-rules ref: \([0-9a-f]\{7,40\}\) -->$/\1/p' "${file}"
}

# Re-read the pin from disk. The value captured when functions.sh was sourced
# goes stale if `update` rewrites versions.env while we wait.
_aws_rules_pin() {
  (
    AWS_RULES_REF=""
    _devbot_versions_env_source "${MODULE_DIR}"
    printf '%s\n' "${AWS_RULES_REF:-}"
  )
}

# Echo upstream main's commit; empty when the remote is unreachable.
# awk exits on the match so nothing upstream sees SIGPIPE under pipefail.
_aws_rules_upstream_ref() {
  { git ls-remote "${AWS_RULES_REPO}" main 2>/dev/null || true; } \
    | awk '$2 == "refs/heads/main" { print $1; exit }'
}

# Download <ref> into <staged>, labelled with the ref it came from — label and
# body land in one rename, so a placed artifact never lies about its origin.
# No lock: the caller decides where it goes.
_aws_rules_download() {
  local ref="$1" staged="$2" body="${2}.body"
  if ! curl -fsSL --connect-timeout 5 --max-time 30 \
    "$(_aws_rules_url "${ref}")" -o "${body}" || [[ ! -s "${body}" ]]; then
    rm -f "${body}"
    return 1
  fi
  if ! { _aws_rules_marker "${ref}"; cat "${body}"; } > "${staged}"; then
    rm -f "${body}" "${staged}"
    return 1
  fi
  rm -f "${body}"
}

# Install (or refresh) the AWS agent rules into storage/aws/rules.
# --if-missing re-checks under the lock. --ref fetches a candidate before the
# pin moves, so a failed fetch cannot leave the pin ahead of the file; without
# it the pin is re-read under the lock, never trusted from process start.
# Returns non-zero on failure; every caller tolerates it.
_aws_fetch_rules() {
  local only_if_missing=0 ref=""
  while (( $# )); do
    case "$1" in
      --if-missing) only_if_missing=1 ;;
      --ref)
        ref="${2:-}"
        shift
        ;;
      *)
        _warn "aws — unknown flag '$1'"
        return 1
        ;;
    esac
    shift
  done

  local dir file
  dir="$(_aws_rules_dir)"
  file="$(_aws_rules_file)"

  if ! command -v curl >/dev/null 2>&1; then
    _warn "curl not found — cannot fetch the AWS agent rules"
    return 1
  fi

  mkdir -p "${dir}" || return 1

  # The subshell releases fd 200.
  (
    _devbot_lock_wait "${dir}/.rules.lock" 300 \
      "gave up waiting for the AWS agent-rules lock" || {
      _warn "Could not lock ${dir}/.rules.lock — AWS agent rules not fetched"
      exit 1
    }

    # Re-read the pin: `update` may have moved it while we waited for the lock.
    [[ -n "${ref}" ]] || ref="$(_aws_rules_pin)"
    if [[ -z "${ref}" ]]; then
      _warn "No AWS agent-rules pin — check ${MODULE_DIR}/versions.env.dist"
      exit 1
    fi

    if (( only_if_missing )) && [[ "$(_aws_rules_stored_ref)" == "${ref}" ]]; then
      _skip "AWS agent rules at ${ref:0:10} already fetched (${file})"
      exit 0
    fi

    _info "Fetching AWS agent rules (${ref:0:10})..."
    # Staged, then renamed: a killed curl leaves no truncated file behind.
    local staged="${dir}/.rules.staging.$$"
    if ! _aws_rules_download "${ref}" "${staged}"; then
      rm -f "${staged}"
      _warn "Failed to fetch rules from $(_aws_rules_url "${ref}")"
      exit 1
    fi
    # errexit is disabled here (the caller runs us under if/|| true), so
    # the rename has to be checked or a failed one reads as success.
    if ! mv "${staged}" "${file}"; then
      rm -f "${staged}"
      _warn "Could not move the fetched rules into ${file}"
      exit 1
    fi
    _ok "Stored ${file}"
  )
}

# Persist the pin. The live file is machine-local (gitignored) so a bump never
# dirties the checkout; the committed .dist is never touched.
_aws_rules_pin_write() {
  local ref="$1"
  if [[ -f "${MODULE_DIR}/versions.env" ]] \
    && grep -qx "AWS_RULES_REF=${ref}" "${MODULE_DIR}/versions.env"; then
    _skip "rules pin already at ${ref:0:10}"
    return 0
  fi
  _devbot_versions_env_seed "${MODULE_DIR}" || {
    _warn "No ${MODULE_DIR}/versions.env to bump — pin stays at ${AWS_RULES_REF:-unset}"
    return 1
  }
  # sed->tmp->mv (no bare `sed -i` — macOS needs a backup suffix).
  if ! sed "s/^AWS_RULES_REF=.*/AWS_RULES_REF=${ref}/" \
    "${MODULE_DIR}/versions.env" > "${MODULE_DIR}/versions.env.tmp" \
    || ! grep -qx "AWS_RULES_REF=${ref}" "${MODULE_DIR}/versions.env.tmp"; then
    rm -f "${MODULE_DIR}/versions.env.tmp"
    _warn "Could not rewrite ${MODULE_DIR}/versions.env — pin unchanged"
    return 1
  fi
  if ! mv "${MODULE_DIR}/versions.env.tmp" "${MODULE_DIR}/versions.env"; then
    rm -f "${MODULE_DIR}/versions.env.tmp"
    _warn "Could not replace ${MODULE_DIR}/versions.env — pin unchanged"
    return 1
  fi
  AWS_RULES_REF="${ref}"
  _ok "rules pin bumped to ${ref:0:10} (versions.env)"
}

# update's transaction: fetch at <ref> and move the pin to it under ONE lock, so
# a second update cannot interleave the pair, and restore the previous rules if
# the pin cannot be written.
_aws_rules_refresh() {
  local ref="${1:-}"
  local dir file
  dir="$(_aws_rules_dir)"
  file="$(_aws_rules_file)"

  if [[ -z "${ref}" ]]; then
    _warn "No AWS agent-rules ref to refresh at"
    return 1
  fi
  if ! command -v curl >/dev/null 2>&1; then
    _warn "curl not found — cannot fetch the AWS agent rules"
    return 1
  fi
  mkdir -p "${dir}" || return 1

  # The subshell releases fd 200.
  (
    _devbot_lock_wait "${dir}/.rules.lock" 300 \
      "gave up waiting for the AWS agent-rules lock" || {
      _warn "Could not lock ${dir}/.rules.lock — AWS agent rules not refreshed"
      exit 1
    }

    local staged="${dir}/.rules.staging.$$" previous="${dir}/.rules.previous.$$"
    _info "Fetching AWS agent rules (${ref:0:10})..."
    if ! _aws_rules_download "${ref}" "${staged}"; then
      rm -f "${staged}"
      _warn "Failed to fetch rules from $(_aws_rules_url "${ref}")"
      exit 1
    fi

    # The old copy survives until the pin naming the new one has landed.
    if [[ -f "${file}" ]] && ! cp "${file}" "${previous}"; then
      rm -f "${staged}"
      _warn "Could not back up ${file} — rules and pin left untouched"
      exit 1
    fi
    if ! mv "${staged}" "${file}"; then
      rm -f "${staged}" "${previous}"
      _warn "Could not move the fetched rules into ${file} — pin not moved"
      exit 1
    fi
    if ! _aws_rules_pin_write "${ref}"; then
      if [[ ! -f "${previous}" ]]; then
        rm -f "${file}"
        _warn "Rules discarded — pin still at ${AWS_RULES_REF:0:10}"
      elif mv "${previous}" "${file}"; then
        _warn "Previous rules restored — pin still at ${AWS_RULES_REF:0:10}"
      else
        _warn "RULES/PIN INCONSISTENT: ${file} is ${ref:0:10}, pin is ${AWS_RULES_REF:0:10}"
      fi
      exit 1
    fi
    rm -f "${previous}"
  )
}

# Print the stored rules under the refresh lock, so a reader never consumes a
# candidate the pin does not name yet.
_aws_rules_snapshot() {
  local dir file
  dir="$(_aws_rules_dir)"
  file="$(_aws_rules_file)"
  (
    _devbot_lock_wait "${dir}/.rules.lock" 300 \
      "gave up waiting for the AWS agent-rules lock" || {
      _warn "Could not lock ${dir}/.rules.lock — AWS agent rules not read"
      exit 1
    }
    local pin stored
    pin="$(_aws_rules_pin)"
    stored="$(_aws_rules_stored_ref)"
    if [[ -z "${pin}" || "${stored}" != "${pin}" ]]; then
      _warn "AWS rules are ${stored:-unlabelled}, pin is ${pin:-unset} — run 'devbot update'"
      exit 1
    fi
    cat "${file}"
  )
}

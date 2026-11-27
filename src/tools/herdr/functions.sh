#!/usr/bin/env bash
# herdr module helpers — install the binary, merge its config, and keep the
# devbot-managed shell wrapper current.
#
# The wrapper makes herdr the OWNER of the docker stack: `devbot up` records an
# owner claim under the shell's pid and `devbot down --owner` releases it when
# herdr exits, so a devbot session opened inside a herdr pane can no longer tear
# the containers down (see the ownership registry in src/_shared/functions.sh).

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_shared/functions.sh
source "${MODULE_DIR}/../../_shared/functions.sh"

# Interactive shells only: a bash user reads .bashrc, a zsh user .zshrc, and a
# machine with both gets the wrapper in each. A missing file is never created —
# writing a shell config the machine does not use would be a side effect nobody
# asked for.
HERDR_SHELL_RCS=(".bashrc" ".zshrc")

_herdr_installed() {
  command -v herdr >/dev/null 2>&1
}

# Official installer: fetches the release manifest, verifies the SHA-256 and
# drops the binary in ~/.local/bin (or HERDR_INSTALL_DIR). Linux and macOS.
_herdr_install() {
  if _herdr_installed; then
    _skip "herdr already installed: $(command -v herdr)"
    return 0
  fi

  _info "installing herdr…"
  if ! curl -fsSL https://herdr.dev/install.sh | sh; then
    _error "herdr install failed — see https://herdr.dev"
    return 1
  fi
  if ! _herdr_installed; then
    _warn "herdr is installed but not on PATH — add ~/.local/bin to it"
    return 0
  fi
  _ok "herdr installed: $(command -v herdr)"
}

_herdr_update_binary() {
  if ! _herdr_installed; then
    _herdr_install
    return $?
  fi

  _info "updating herdr…"
  if herdr update; then
    _ok "herdr updated: $(herdr --version 2>/dev/null | head -1)"
  else
    _warn "herdr update failed — keeping the installed version"
  fi
}

# _herdr_config_has_window_title <config> — the setting is present and scoped
# where herdr reads it: inside the [ui] table, or as the dotted `ui.window_title`.
# An unqualified `window_title` under any OTHER table is a different key, and
# treating it as ours would skip the merge the user asked for.
_herdr_config_has_window_title() {
  awk '
    /^[[:space:]]*\[[[:space:]]*ui[[:space:]]*\][[:space:]]*(#.*)?$/ { in_ui = 1; next }
    /^[[:space:]]*\[/ { in_ui = 0 }
    /^[[:space:]]*"?ui"?[[:space:]]*\.[[:space:]]*"?window_title"?[[:space:]]*=/ { found = 1 }
    in_ui == 1 && /^[[:space:]]*"?window_title"?[[:space:]]*=/ { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "${1}"
}

# herdr has no config set: merge, never clobber. Ported from the setup script
# that grew it — the same setting, the same revert on a config that would break.
_herdr_merge_config() {
  local cfg="${XDG_CONFIG_HOME:-${HOME}/.config}/herdr/config.toml"
  local setting='window_title = "{terminal_title}"'
  local header='^[[:space:]]*\[[[:space:]]*ui[[:space:]]*\][[:space:]]*(#.*)?$'

  # A config that already fails to parse would make every post-merge check fail
  # and turn the revert into an accusation of this key: establish the baseline
  # first, and say what is actually wrong instead of touching the file.
  if _herdr_installed; then
    local baseline
    baseline="$(herdr config check 2>&1 || true)"
    if [[ "${baseline}" == *"parse error"* ]]; then
      _warn "herdr: ${cfg} does not parse already — window_title not merged:"
      printf '%s\n' "${baseline}" | sed -e 's/^/      /' | head -3 >&2
      return 0
    fi
  fi

  mkdir -p "$(dirname "${cfg}")" 2>/dev/null \
    || { _warn "herdr: cannot create $(dirname "${cfg}") — config not merged"; return 0; }
  touch "${cfg}" 2>/dev/null \
    || { _warn "herdr: cannot write ${cfg} — config not merged"; return 0; }

  if _herdr_config_has_window_title "${cfg}"; then
    _skip "herdr: window_title already configured — leaving it alone"
    return 0
  fi

  # The backup is the restore point for every write below: without it, nothing
  # is attempted rather than risking a truncated config.
  if ! cp "${cfg}" "${cfg}.devbot-bak" 2>/dev/null; then
    _warn "herdr: could not back up ${cfg} — window_title not merged"
    return 0
  fi

  # Inside an existing [ui] table the key belongs to that table; with no table
  # it gets one, and never a second copy of the key. Either way the write is
  # checked: a failed write restores the backup instead of leaving half a file.
  local wrote=0
  if grep -qE "${header}" "${cfg}"; then
    if awk -v s="${setting}" -v h="${header}" \
      '{ print } !done && $0 ~ h { print s; done = 1 }' "${cfg}" >"${cfg}.new"; then
      cat "${cfg}.new" >"${cfg}" && wrote=1
    fi
    rm -f "${cfg}.new"
  else
    printf '\n[ui]\n%s\n' "${setting}" >>"${cfg}" && wrote=1
  fi

  if [[ ${wrote} -eq 0 ]]; then
    _warn "herdr: could not write ${cfg} — restoring the previous config"
    cat "${cfg}.devbot-bak" >"${cfg}" 2>/dev/null || true
    rm -f "${cfg}.devbot-bak"
    return 0
  fi

  if _herdr_installed; then
    local diagnostics
    diagnostics="$(herdr config check 2>&1 || true)"
    if [[ "${diagnostics}" == *"parse error"* ]]; then
      _warn "herdr: window_title would break ${cfg} — reverting"
      cat "${cfg}.devbot-bak" >"${cfg}"
      rm -f "${cfg}.devbot-bak"
      return 0
    fi
    herdr server reload-config >/dev/null 2>&1 \
      && _info "herdr: config reloaded into the running server"
  fi

  rm -f "${cfg}.devbot-bak"
  _ok "herdr: terminal title follows the focused pane title"
}

# Replace whatever wrote the `herdr` shell function last — a hand-rolled one, or
# the block an older setup script appended — with devbot's marked block. The
# body lives in herdr-function.sh so a change to it ships with a release.
_herdr_wire_shell() {
  local rc found=0 snippet
  # Validate the snippet ONCE, before any rc is touched: stripping the foreign
  # definition first and failing on the body afterwards would leave the user with
  # no herdr function at all. The snippet is shell, so it is parsed; the lint
  # directive it carries for this repo is dropped from what gets rendered.
  snippet="$(mktemp)" || return 1
  if ! sed '/^# shellcheck /d' "${MODULE_DIR}/herdr-function.sh" >"${snippet}" 2>/dev/null \
    || [[ ! -s "${snippet}" ]] || ! bash -n "${snippet}" 2>/dev/null; then
    rm -f "${snippet}"
    _warn "the herdr function snippet is missing or invalid — no shell rc touched"
    return 1
  fi

  local work_dir=""
  for rc in "${HERDR_SHELL_RCS[@]}"; do
    [[ -f "${HOME}/${rc}" ]] || continue
    found=1

    # Edit a COPY and install it only when both steps succeed: a strip that lands
    # without its render (a malformed managed block, a body that will not parse)
    # would otherwise leave the user with no herdr function at all. The copy
    # keeps the rc's file name so the syntax check picks the right shell.
    [[ -n "${work_dir}" ]] || work_dir="$(mktemp -d)" || break
    local work="${work_dir}/${rc}"
    # An unreadable rc must not be replaced by a strip/render of an empty copy.
    if ! cat "${HOME}/${rc}" >"${work}"; then
      rm -f "${work}"
      _warn "could not read ~/${rc} — file left as it is"
      continue
    fi

    if ! _devbot_shell_function_strip "${work}" herdr \
      || ! _devbot_shell_block_upsert "${work}" herdr <"${snippet}"; then
      rm -f "${work}"
      _warn "could not safely update ~/${rc} — file left as it is"
      continue
    fi

    if cmp -s "${work}" "${HOME}/${rc}"; then
      rm -f "${work}"
      _ok "herdr wrapper in ~/${rc}"
      continue
    fi
    if ! cat "${work}" >"${HOME}/${rc}"; then
      rm -f "${work}"
      _warn "could not write ~/${rc} — the herdr wrapper is not wired there"
      continue
    fi
    rm -f "${work}"
    _ok "herdr wrapper in ~/${rc}"
  done
  rm -f "${snippet}"
  [[ -z "${work_dir}" ]] || rm -rf "${work_dir}"

  [[ ${found} -eq 1 ]] || _skip "no ~/.bashrc or ~/.zshrc — herdr wrapper not wired"
}

# _herdr_main install|update
_herdr_main() {
  local mode="${1:-install}"
  _info "herdr"

  # bin/install.sh and bin/update.sh run every module's script, disabled ones
  # included: a disabled module must not install a binary or touch a shell rc.
  if ! _devbot_module_enabled herdr; then
    _skip "herdr module disabled — nothing installed, no shell wrapper written"
    return 0
  fi

  if [[ "${mode}" == "update" ]]; then
    _herdr_update_binary || return 1
  else
    _herdr_install || return 1
  fi

  _herdr_wire_shell
  _herdr_merge_config
  _ok "herdr ready"
}

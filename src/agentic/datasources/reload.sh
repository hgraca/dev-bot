#!/usr/bin/env bash
# src/agentic/datasources/reload.sh
# Re-evaluate the catalogue against the network as it is NOW, and hand the
# result to the running gateway.
#
# Datasources are evaluated once, at startup. A source that was unreachable
# then — a database behind a VPN that was down — is dropped from the rendered
# config, and nothing re-renders until the next boot. The harness, though,
# registers a manifest for every SELECTED source whatever the render decided, so
# turning that manifest on points the client at a toolset the gateway never
# loaded: the connect fails, and only a restart fixes it.
#
# This is the missing step in between: keep the gateway up, re-render, and let
# toolbox's own poll pick the new config up. It stays explicit, so the
# evaluate-once rule holds — nothing here runs in the background.
#
# Usage:
#   reload.sh              # reload for the current directory's project
#   reload.sh <project>    # ...for that project (which sidecars it demands)
set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "${MODULE_DIR}/../../.." && pwd)}"
export DEV_BOT_ROOT

PROJECT_DIR="${1:-$(pwd)}"

# The MCP protocol version this probe negotiates, and therefore the one every
# later request in the session must declare.
MCP_PROTOCOL_VERSION="2024-11-05"

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

# The sources the render just published, one name per `kind: source` document —
# and the tools it declares for them. Read back from the artifact rather than
# recomputed: the answer must describe what the gateway was actually handed.
_published_sources() {
  [[ -f "${CONF_FILE}" ]] || return 0
  awk '/^kind: source$/ { in_source = 1; next }
       in_source && /^name: / { print $2; in_source = 0 }' "${CONF_FILE}"
}

_published_tools() {
  [[ -f "${CONF_FILE}" ]] || return 0
  awk '/^kind: tool$/ { in_tool = 1; next }
       in_tool && /^name: / { print $2; in_tool = 0 }' "${CONF_FILE}"
}

# The port a sidecar listens on, from the same allocation its manifest uses.
_sidecar_port() {
  local name="$1" ports="$2"
  python3 -c '
import json, sys
try:
    ports = json.loads(sys.argv[1])
except Exception:
    ports = {}
print(ports.get(sys.argv[2], ""))
' "${ports}" "${name}" 2>/dev/null || true
}

# Does this endpoint actually SERVE its toolset?
#
# Never an `initialize` handshake alone: toolbox answers that on /mcp/<anything>,
# including a toolset it never loaded, so a transport-only probe reports success
# for exactly the case this command exists to catch. `tools/list` is served per
# toolset — a missing one comes back as a JSON-RPC error ("toolset does not
# exist") with HTTP 200, so the BODY decides, not the status code.
#
# The session is a real one: initialize first, keep the `Mcp-Session-Id` a
# stateful server issues, and carry it on tools/list. Toolbox 1.11.0 is
# stateless and issues none, so it is called without the header — but a sidecar
# built on a stateful transport rejects a bare tools/list, which would read as
# a healthy server being unavailable.
_probe_toolset() {
  local source="$1" url="$2" tries="$3" expected="" attempt=1 body session
  # Only a PUBLISHED toolbox source has a tool to look for. Deriving it by name
  # alone would hold a sidecar to a tools.yaml entry it can never have.
  if _published_sources | grep -qx "${source}"; then
    expected="$(_published_tools | grep -E "^${source}_" | head -1 || true)"
  fi

  while true; do
    session="$(_toolset_session "${url}")"
    _toolset_initialized "${url}" "${session}"
    body="$(_toolset_tools "${url}" "${session}")"
    _toolset_close "${url}" "${session}"
    if _tools_served "${body}" "${expected}"; then
      return 0
    fi
    if [[ ${attempt} -ge ${tries} ]]; then
      _skip "${source}: toolset is not served at ${url} after ${tries}s — MCP server will be unavailable"
      return 1
    fi
    attempt=$((attempt + 1))
    sleep 1
  done
}

# A clean JSON-RPC result — and, when a tool is named, that tool in the result.
# A sidecar names none: its tools come from its own server, not from tools.yaml,
# so a clean `tools` result is the whole proof there.
_tools_served() {
  local body="$1" expected="$2"
  [[ -n "${body}" ]] || return 1
  # Parse, never pattern-match the body: a tool's input schema may legitimately
  # declare a property called `error`, and only the TOP-LEVEL `error` member
  # marks a JSON-RPC failure. Non-JSON output (a dead endpoint, an HTML error
  # page) is not a served toolset either.
  printf '%s' "${body}" | python3 -c '
import json, sys

raw = sys.stdin.read()
candidates = [raw]
# An SSE response carries the JSON on `data:` lines; a pretty-printed body keeps
# it across lines. Try the joined data payloads first, then the body as-is —
# never a single line, which would be a fragment of either.
data = [line.strip()[5:].strip() for line in raw.splitlines() if line.strip().startswith("data:")]
if data:
    candidates.insert(0, "\n".join(data))
doc = None
for candidate in candidates:
    try:
        doc = json.loads(candidate)
        break
    except ValueError:
        continue
if doc is None:
    sys.exit(1)
if not isinstance(doc, dict) or "error" in doc or "result" not in doc:
    sys.exit(1)
tools = doc["result"].get("tools")
if not isinstance(tools, list):
    sys.exit(1)
expected = sys.argv[1]
if expected and not any(
    isinstance(tool, dict) and tool.get("name") == expected for tool in tools
):
    sys.exit(1)
' "${expected}"
}

# The session id an initialize response carries, empty for a stateless server.
_toolset_session() {
  local url="$1" resp
  resp="$(curl -s -i --max-time 2 -X POST "${url}" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"'"${MCP_PROTOCOL_VERSION}"'","capabilities":{},"clientInfo":{"name":"devbot-reload","version":"1"}}}' 2>/dev/null)" || resp=""
  printf '%s' "${resp}" | tr -d '\r' |
    awk -F': ' 'tolower($1)=="mcp-session-id"{print $2; exit}'
}

# The notification that completes the handshake. A compliant stateful server may
# reject every request that arrives before it; a stateless one ignores it.
_toolset_initialized() {
  local url="$1" session="$2"
  local -a session_header=()
  [[ -n "${session}" ]] && session_header=(-H "Mcp-Session-Id: ${session}")
  curl -s --max-time 2 -o /dev/null -X POST "${url}" \
    -H 'Content-Type: application/json' \
    -H "MCP-Protocol-Version: ${MCP_PROTOCOL_VERSION}" \
    -H 'Accept: application/json, text/event-stream' \
    ${session_header[@]+"${session_header[@]}"} \
    -d '{"jsonrpc":"2.0","method":"notifications/initialized"}' 2>/dev/null || true
}

# Close the session a stateful server opened: streamable HTTP terminates one
# with a DELETE carrying the session id. Best effort — leaked sessions would
# accumulate on the server across repeated reloads, and a stateless server has
# none to close.
_toolset_close() {
  local url="$1" session="$2"
  [[ -n "${session}" ]] || return 0
  curl -s --max-time 2 -o /dev/null -X DELETE "${url}" \
    -H "Mcp-Session-Id: ${session}" 2>/dev/null || true
}

# tools/list on that session, printing the response body (SSE `data:` payload
# included as-is — the JSON is what the callers look for).
_toolset_tools() {
  local url="$1" session="$2"
  local -a session_header=()
  [[ -n "${session}" ]] && session_header=(-H "Mcp-Session-Id: ${session}")
  curl -s --max-time 2 -X POST "${url}" \
    -H 'Content-Type: application/json' \
    -H "MCP-Protocol-Version: ${MCP_PROTOCOL_VERSION}" \
    -H 'Accept: application/json, text/event-stream' \
    ${session_header[@]+"${session_header[@]}"} \
    -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' 2>/dev/null || true
}

# The sources this project SELECTED that the gateway still cannot serve: the
# manifest exists (selection), the toolset does not (the render dropped it).
# Enabling one would fail, so a reload that leaves them cannot claim success.
_unpublished_selected() {
  local project_dir="$1" strict="${2:-0}"
  local selected declared toolbox published name
  selected="$(_datasources_selected "${project_dir}")"
  [[ -n "${selected}" ]] || return 0
  declared="$(_datasources_declared)"
  toolbox="$(python3 "${MODULE_DIR}/../../_shared/read_jsonc.py" \
    "${DEV_BOT_ROOT}/.devbot.global.jsonc" datasources 2>/dev/null |
    python3 "${MODULE_DIR}/render_tools_yaml.py" --toolbox-names 2>/dev/null)" || toolbox=""
  published="$(_published_sources)"

  for name in ${selected}; do
    # Not in the catalogue at all: a typo. init writes its manifest and warns,
    # but no render can ever publish it. Only this project's own typos count
    # against this command — another project's config error is not ours to fail.
    if ! printf ' %s ' "${declared}" | grep -Fq " ${name} "; then
      if [[ "${strict}" == "1" ]]; then
        echo "${name}"
      fi
      continue
    fi
    if printf ' %s ' "${toolbox}" | grep -Fq " ${name} "; then
      # A toolbox source is published, or it is not.
      printf ' %s ' "${published}" | grep -Fq " ${name} " || echo "${name}"
      continue
    fi
    # A declared sidecar is served by its OWN container — but only if the render
    # emitted its service. A live project absent from the configured project
    # list selects one the static demand filter never renders, so its manifest
    # points at nothing even though the name is declared.
    printf ' %s ' "$(_sidecar_services)" | grep -Fq " ${name} " || echo "${name}"
  done
}

# A harness manifest pointing somewhere other than where this render put the
# source. Manifests are written at init time and the harness caches them, so a
# re-allocated sidecar port (a new name that sorts earlier, or a new
# DATASOURCES_PORT) leaves the harness enabling a URL nothing listens on — a
# reload cannot rewrite what the harness has cached, so it must not claim
# success silently either. Prints "<project>:<source>" per stale manifest.
_stale_manifests() {
  local project_dir="$1" gateway_url="$2" ports="$3" name file actual expected port
  for name in $(_datasources_selected "${project_dir}"); do
    port="$(_sidecar_port "${name}" "${ports}")"
    if [[ -n "${port}" ]]; then
      expected="http://127.0.0.1:${port}/mcp"
    else
      expected="${gateway_url}/${name}"
    fi
    # Only the harnesses this project actually consumes: init does not write or
    # prune a disabled harness's manifests, so a leftover from one it used to
    # have must not fail every reload. Shapes differ — opencode keeps the server
    # at the top level, claudecode nests it under mcpServers.
    local -a manifests=()
    if ! _datasources_harness_disabled "${project_dir}" opencode; then
      manifests+=("${project_dir}/.opencode/datasources-${name}.mcp.json")
    fi
    if ! _datasources_harness_disabled "${project_dir}" claudecode; then
      manifests+=("${project_dir}/.claude/datasources-${name}.mcp.json")
    fi
    for file in ${manifests[@]+"${manifests[@]}"}; do
      [[ -f "${file}" ]] || continue
      actual="$(_manifest_url "${file}" "datasources-${name}")"
      if [[ -n "${actual}" && "${actual}" != "${expected}" ]]; then
        echo "$(basename "${project_dir}"):${name}"
        break
      fi
    done
  done
}

# The URL a generated manifest points at, whichever shape it has.
_manifest_url() {
  python3 -c '
import json, sys
try:
    with open(sys.argv[1]) as fh:
        doc = json.load(fh)
except Exception:
    sys.exit(0)
key = sys.argv[2]
entry = doc.get(key)
if not isinstance(entry, dict):
    servers = doc.get("mcpServers")
    entry = servers.get(key) if isinstance(servers, dict) else None
print(entry.get("url", "") if isinstance(entry, dict) else "")
' "$1" "$2" 2>/dev/null || true
}

# Every project the shared gateway serves right now: this one plus any live
# session's. A source dropped from the catalogue is dropped for all of them.
_served_projects() {
  { printf '%s\n' "${PROJECT_DIR}"; _devbot_live_session_projects | tr ' ' '\n'; } |
    awk 'NF && !seen[$0]++'
}

main() {
  _info "datasources — reload"

  command -v docker >/dev/null 2>&1 || {
    _error "datasources — docker not found; cannot reload"
    return 1
  }
  command -v curl >/dev/null 2>&1 || {
    _error "datasources — curl not found; cannot verify the reload"
    return 1
  }

  # Held across render, compose reconciliation and verification. Without it a
  # concurrent `devbot up` — which stops the gateway before rendering — can
  # replace the artifacts mid-run, and this invocation would verify one
  # catalogue while another is being published.
  if ! _datasources_lock; then
    _error "datasources — another lifecycle run is in progress; nothing was reloaded"
    return 1
  fi

  _devbot_load_env
  # Before the render, for the same reason up.sh does it: a detached poller from
  # an older install would rewrite tools.yaml under this render — even after the
  # verification — so the command could verify one catalogue and hand the
  # gateway another.
  _stop_legacy_poller

  # Unlike the boot path, a failed render is NOT survivable here: the whole
  # point is to hand the gateway the config this render produced, and a
  # half-answer would leave the user believing a source is available when the
  # gateway still does not serve it. The reload reports the unusable sources
  # itself, so the render's generic hint would only be circular advice.
  if ! DATASOURCES_SUPPRESS_RELOAD_HINT=1 DATASOURCES_LIFECYCLE_HELD=1 \
    bash "${MODULE_DIR}/render.sh" "${PROJECT_DIR}"; then
    _error "datasources — reload aborted; the gateway keeps its current config"
    return 1
  fi

  local gateway_url has_sources="false" sidecars=""
  gateway_url="$(_datasources_gateway_url)"
  _catalogue_has_sources && has_sources="true"
  sidecars="$(_sidecar_services)"

  # Computed here, not at the end: "nothing to serve" must not read as success
  # when what the project selects is exactly what could not be published. The
  # gateway is machine-wide, so every live project's selections are checked too:
  # another session's source dropped by this render is that session's outage,
  # and it must not be silent just because it is not this project's.
  # The allocation the RENDER produced — the same call render.sh makes — shared
  # by every check below. Recomputing it per project would let a live project
  # outside the configured set disagree with the endpoints that were rendered.
  local sidecar_ports
  sidecar_ports="$(_datasources_sidecar_ports "${PROJECT_DIR}")"

  local project name strict stale="" unpublished="" other_projects=""
  while IFS= read -r project; do
    [[ -n "${project}" ]] || continue
    strict=0
    if [[ "${project}" == "${PROJECT_DIR}" ]]; then
      strict=1
    fi
    while IFS= read -r name; do
      [[ -n "${name}" ]] || continue
      if [[ "${strict}" == "1" ]]; then
        unpublished+=" ${name}"
      else
        other_projects+=" ${name} ($(basename "${project}"))"
      fi
    done < <(_unpublished_selected "${project}" "${strict}")
    while IFS= read -r name; do
      [[ -n "${name}" ]] || continue
      stale+=" ${name}"
    done < <(_stale_manifests "${project}" "${gateway_url}" "${sidecar_ports}")
  done < <(_served_projects)
  unpublished="${unpublished# }"
  other_projects="${other_projects# }"

  if [[ -n "${other_projects}" ]]; then
    _warn "datasources — another live project selects what is still unpublishable: ${other_projects}"
  fi

  if [[ "${has_sources}" != "true" && -z "${sidecars}" ]]; then
    _skip "datasources — no usable datasources; nothing to serve"
    if [[ -n "${unpublished}" ]]; then
      _warn "datasources — selected but still unpublishable: ${unpublished}"
      _error "datasources — reload incomplete; see the warnings above"
      return 1
    fi
    return 0
  fi

  # A running gateway picks the published config up on its own poll
  # (`--poll-interval 5`), and render.sh already waited that interval out when
  # it found the container up. A stopped one — the boot that found every source
  # unreachable never started it — has to be started here.
  if [[ "${has_sources}" == "true" ]]; then
    if _gateway_running; then
      # Running is not the same as matching: this render may have re-allocated
      # the gateway's port or changed its env list, and the old container still
      # answers on the old one. Compose recreates only on a changed definition.
      if _update_gateway; then
        _ok "datasources — gateway reconciled with the rendered config"
        # Compose may have recreated it on a changed definition, and a cold
        # gateway needs its boot budget before any toolset probe can pass.
        _devbot_wait_for_mcp_gateway datasources "${gateway_url}" "" "$(_gateway_container_name)" || true
      else
        _error "datasources gateway could not be reconciled with the rendered config"
        return 1
      fi
    elif _start_gateway; then
      if _devbot_wait_for_mcp_gateway datasources "${gateway_url}" "" "$(_gateway_container_name)"; then
        _ok "datasources gateway reachable at ${gateway_url}"
      fi
    else
      _error "datasources gateway failed to start"
      return 1
    fi
  fi

  # Sidecars the live sessions demand, started if they are not already up.
  # Nothing is stopped: a reload only ever adds what is now reachable. Only a
  # DEMANDED sidecar is verified — the compose carries one for every project
  # that ever selects it, and an undemanded one is deliberately not running.
  local wanted="" service failed=0
  local verify_sidecars="" fresh_sidecars=""
  # shellcheck disable=SC2046  # project paths are space-free; split on purpose
  if ! wanted="$(_wanted_sidecars $(_devbot_live_session_projects) "${PROJECT_DIR}")"; then
    wanted=""
    _warn "datasources — could not read the catalogue; sidecars left as they are"
  fi
  for service in ${sidecars}; do
    printf ' %s ' "${wanted}" | grep -Fq " ${service} " || continue
    verify_sidecars+=" ${service}"
    if _running_sidecars | grep -qx "${service}"; then
      # Running is not the same as matching: this render may have re-allocated
      # the sidecar's port (another sidecar sorted before it, or a different
      # DATASOURCES_PORT), and the old container still listens on the old one.
      # `up` without --build recreates only when the definition changed.
      if _update_sidecar "${service}"; then
        _ok "datasources — sidecar '${service}' reconciled with the rendered config"
        # Compose may have recreated it on a changed definition — a re-allocated
        # port, a changed env list — so it gets the boot budget, not the
        # "already healthy" one.
        fresh_sidecars+=" ${service}"
      else
        _warn "datasources — sidecar '${service}' could not be reconciled with the rendered config"
        failed=1
      fi
      continue
    fi
    if _start_sidecar "${service}"; then
      _ok "datasources — sidecar '${service}' started"
      fresh_sidecars+=" ${service}"
    else
      _warn "datasources — sidecar '${service}' failed to start; its manifest will not answer"
      failed=1
    fi
  done

  # Verify what was published, and what this project selected. The handshake is
  # the last word: it is what the harness will do when the source is enabled.
  local name url
  for name in $(_published_sources); do
    url="${gateway_url}/${name}"
    if _probe_toolset "${name}" "${url}" "${DATASOURCES_RELOAD_PROBE_TRIES:-3}"; then
      _ok "datasources — ${name} answers"
    else
      _warn "datasources — ${name} is published but does not answer"
      failed=1
    fi
  done

  # A sidecar started a moment ago is still resolving its dependencies (the
  # server runs from uvx, on a cold cache), so it gets the boot-sized budget
  # rather than the "is it already healthy" one.
  local port tries
  for name in ${verify_sidecars}; do
    port="$(_sidecar_port "${name}" "${sidecar_ports}")"
    if [[ -z "${port}" ]]; then
      _warn "datasources — sidecar '${name}' has no allocated port to verify"
      failed=1
      continue
    fi
    tries="${DATASOURCES_RELOAD_PROBE_TRIES:-3}"
    if printf ' %s ' "${fresh_sidecars}" | grep -Fq " ${name} "; then
      tries="${DEV_BOT_MCP_WAIT_TRIES:-30}"
    fi
    if _probe_toolset "${name}" "http://127.0.0.1:${port}/mcp" "${tries}"; then
      _ok "datasources — ${name} answers"
    else
      _warn "datasources — sidecar '${name}' is running but does not answer"
      failed=1
    fi
  done

  if [[ -n "${stale}" ]]; then
    _warn "datasources — harness manifests are stale:${stale}"
    _warn "  run 'devbot reinit' and restart the harness to point them at the new endpoints"
    failed=1
  fi
  if [[ -n "${unpublished}" ]]; then
    _warn "datasources — selected but still unpublishable: ${unpublished}"
    failed=1
  fi

  if [[ ${failed} -ne 0 ]]; then
    _error "datasources — reload incomplete; see the warnings above"
    return 1
  fi

  _ok "datasources — reload complete; every selected source is served"
  return 0
}

main "$@"

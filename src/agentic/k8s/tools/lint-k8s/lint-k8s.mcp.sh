#!/usr/bin/env bash
# ---
# description: Audit Kubernetes, Kustomize, or Helm manifests using kubeconform (schema validation) and kube-linter (best practices)
# ---
# =============================================================================
# src/agentic/k8s/tools/lint-k8s/lint-k8s.mcp.sh
# Audit Kubernetes, Kustomize, or Helm manifests using kubeconform
# (schema validation) and kube-linter (best practices).
#
# Usage:
#   lint-k8s.mcp.sh <path>                    # file or directory
#   lint-k8s.mcp.sh --json <path>             # JSON output
#   lint-k8s.mcp.sh --schema <location> <path> # kubeconform schema override
#
# Parameters:
# - path (string, required): file or directory path containing YAML/YML manifests
# - schema (string, optional): kubeconform schema location override (e.g., 'default', 'kubernetes')
# - format (string, optional): 'json' (default) or 'markdown'
# =============================================================================

set -euo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"lint-k8s","description":"Audit Kubernetes, Kustomize, or Helm manifests using kubeconform (schema validation) and kube-linter (best practices)","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"CLI args: <path> [--json] [--format json|markdown] [--schema <location>]"}},"required":["args"]}}
JSON
    exit 0
    ;;
esac

# ── Find binary ──────────────────────────────────────────────────────────────

_find_bin() {
  local name="$1"
  for dir in "$HOME/.local/bin" "/usr/local/bin" "/usr/bin"; do
    [[ -x "$dir/$name" ]] && echo "$dir/$name" && return 0
  done
  command -v "$name" 2>/dev/null || true
}

# _run_with_timeout <seconds> <cmd...>
# `timeout` is GNU coreutils and is not available on macOS by default — fall
# back to `gtimeout` (coreutils) and finally to running without a timeout.
_run_with_timeout() {
  local seconds="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$seconds" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$seconds" "$@"
  else
    "$@"
  fi
}

# ── Gather manifests ─────────────────────────────────────────────────────────

# True when the file looks like a Kubernetes manifest — it contains an
# `apiVersion` key and a `kind` key (tolerating JSON's quoted keys). Directory
# sweeps gather only manifest-looking files; anything else (config files,
# editor/tool caches) would otherwise make kubeconform report a "missing
# 'kind' key" error for every non-manifest file (audit-48 N5). An explicitly
# passed file is still linted as-is — a mistaken explicit target stays loud.
_is_manifest() {
  local file="$1"
  grep -Eq '(^|[^[:alnum:]_-])apiVersion"?[[:space:]]*:' "$file" 2>/dev/null \
    && grep -Eq '(^|[^[:alnum:]_-])kind"?[[:space:]]*:' "$file" 2>/dev/null
}

_gather_files() {
  local path="$1"
  if [[ -f "$path" ]]; then
    [[ "$path" =~ \.(ya?ml|json)$ ]] && echo "$path"
  elif [[ -d "$path" ]]; then
    local f
    while IFS= read -r f; do
      [[ -n "$f" ]] && _is_manifest "$f" && echo "$f"
    done < <(find "$path" -type f \( -name "*.yml" -o -name "*.yaml" -o -name "*.json" \) \
      ! -path "*/.git/*" ! -path "*/node_modules/*" ! -path "*/.terraform/*" 2>/dev/null)
  fi
}

# ── Parse args ───────────────────────────────────────────────────────────────

FORMAT="text"
SCHEMA=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json|-j)   FORMAT="json"; shift ;;
    --markdown)  FORMAT="markdown"; shift ;;
    --schema|-s) SCHEMA="$2"; shift 2 ;;
    --*)         shift ;; # unknown flags passed through
    -*)          shift ;;
    *)           break ;;
  esac
done

TARGET="${1:-.}"
if [[ ! -e "$TARGET" ]]; then
  echo "lint-k8s: path not found: $TARGET" >&2
  exit 1
fi

# ── Find tools ───────────────────────────────────────────────────────────────

KUBECONFORM=$(_find_bin "kubeconform")
KUBELINTER=$(_find_bin "kube-linter")

if [[ -z "$KUBECONFORM" || -z "$KUBELINTER" ]]; then
  echo "lint-k8s: kubeconform or kube-linter not found. Install them:" >&2
  echo "  brew install kubeconform kube-linter" >&2
  exit 1
fi

# kubeconform args shared by both output modes. The --schema CLI flag maps to
# kubeconform's -schema-location (shellcheck SC2034: SCHEMA was parsed above
# but never reached kubeconform).
KC_ARGS=(-summary)
if [[ -n "$SCHEMA" ]]; then
  KC_ARGS+=(-schema-location "$SCHEMA")
fi

# ── Run linters ──────────────────────────────────────────────────────────────

FILES=()
while IFS= read -r f; do
  [[ -n "$f" ]] && FILES+=("$f")
done < <(_gather_files "$TARGET")

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "lint-k8s: no Kubernetes manifests found in $TARGET (sweeps gather only YAML/JSON files containing an apiVersion and a kind key)" >&2
  exit 1
fi

if [[ "$FORMAT" == "json" ]]; then
  # JSON output
  echo "{"
  echo '  "path": "'"$TARGET"'",'
  echo '  "kubeconform": {'

  KC_VALID=true
  KC_OUTPUT=""
  for f in "${FILES[@]}"; do
    result=$(_run_with_timeout 30 "$KUBECONFORM" "${KC_ARGS[@]}" "$f" 2>&1) || { KC_VALID=false; KC_OUTPUT+="$result"$'\n'; }
  done
  if [[ -z "$KC_OUTPUT" ]]; then
    KC_SUMMARY="all valid"
  else
    KC_SUMMARY="found issues"
  fi
  echo '    "valid": '$KC_VALID','
  echo '    "summary": "'"$KC_SUMMARY"'"'
  echo '  },'
  echo '  "kubelinter": {'

  KL_OUTPUT=$("$KUBELINTER" lint "${FILES[@]}" --format json 2>/dev/null || echo '{"Reports":[],"Summary":{"TotalViolations":0,"FilesWithViolations":0,"TotalFilesScanned":0}}')
  echo '    "report": '"$KL_OUTPUT"
  echo '  }'
  echo "}"
else
  # Text/markdown output
  if [[ "$FORMAT" == "markdown" ]]; then
    echo "## kubeconform"
    echo '```'
  else
    echo "--- kubeconform ---"
  fi

  KC_ERRORS=0
  for f in "${FILES[@]}"; do
    "$KUBECONFORM" "${KC_ARGS[@]}" "$f" 2>&1 || { KC_ERRORS=$((KC_ERRORS + 1)); }
  done
  [[ $KC_ERRORS -eq 0 ]] && echo "All valid"

  if [[ "$FORMAT" == "markdown" ]]; then
    echo '```'
    echo "## kube-linter"
    echo '```'
  else
    echo "--- kube-linter ---"
  fi

  "$KUBELINTER" lint "${FILES[@]}" 2>&1 || true

  if [[ "$FORMAT" == "markdown" ]]; then
    echo '```'
  fi
fi

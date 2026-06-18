#!/usr/bin/env bash
# ---
# description: Audit Kubernetes, Kustomize, or Helm manifests using kubeconform (schema validation) and kube-linter (best practices)
# ---
# =============================================================================
# src/agentic/k8s/tools/lint-k8s/lint-k8s.sh
# Audit Kubernetes, Kustomize, or Helm manifests using kubeconform
# (schema validation) and kube-linter (best practices).
#
# Usage:
#   lint-k8s.sh <path>                    # file or directory
#   lint-k8s.sh --json <path>             # JSON output
#   lint-k8s.sh --schema <location> <path> # kubeconform schema override
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

# ── Gather manifests ─────────────────────────────────────────────────────────

_gather_files() {
  local path="$1"
  if [[ -f "$path" ]]; then
    [[ "$path" =~ \.(ya?ml|json)$ ]] && echo "$path"
  elif [[ -d "$path" ]]; then
    find "$path" -type f \( -name "*.yml" -o -name "*.yaml" -o -name "*.json" \) \
      ! -path "*/.git/*" ! -path "*/node_modules/*" ! -path "*/.terraform/*" 2>/dev/null
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

# ── Run linters ──────────────────────────────────────────────────────────────

FILES=()
while IFS= read -r f; do
  [[ -n "$f" ]] && FILES+=("$f")
done < <(_gather_files "$TARGET")

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "lint-k8s: no YAML/YML/JSON files found in $TARGET" >&2
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
    result=$(timeout 30 "$KUBECONFORM" -summary "$f" 2>&1) || { KC_VALID=false; KC_OUTPUT+="$result"$'\n'; }
  done
  echo '    "valid": '$KC_VALID','
  echo '    "summary": "'$([ -z "$KC_OUTPUT" ] && echo "all valid" || echo "found issues")'"'
  echo '  },'
  echo '  "kubelinter": {'

  KL_OUTPUT=$("$KUBELINTER" lint "${FILES[@]}" --output json 2>/dev/null || echo '{"Reports":[],"Summary":{"TotalViolations":0,"FilesWithViolations":0,"TotalFilesScanned":0}}')
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
    "$KUBECONFORM" -summary "$f" 2>&1 || { KC_ERRORS=$((KC_ERRORS + 1)); }
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

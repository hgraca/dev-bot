#!/usr/bin/env bash
# =============================================================================
# src/agentic/k8s/hooks/claudecode/on-file_edited-lint-k8s.sh
# Claude Code PostToolUse hook — lints K8s manifests on file edit.
# Runs kubeconform (schema validation) and kube-linter (best practices).
#
# Register in .claude/settings.local.json:
#   "hooks": {
#     "PostToolUse": [
#       {
#         "matcher": "Edit|Write",
#         "hooks": [
#           {
#             "type": "command",
#             "command": "bash src/agentic/k8s/hooks/claudecode/on-file_edited-lint-k8s.sh"
#           }
#         ]
#       }
#     ]
#   }
#
# GATE: Must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Only react to YAML files
if [[ "$FILE_PATH" != *.yml && "$FILE_PATH" != *.yaml ]]; then
  exit 0
fi

# Quick gate: only lint K8s manifests (files containing apiVersion + kind)
if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

HEAD=$(head -c 4096 "$FILE_PATH" 2>/dev/null || true)
if [[ "$HEAD" != *"apiVersion:"* || "$HEAD" != *"kind:"* ]]; then
  exit 0
fi

# Find binaries
KUBECONFORM=""
KUBELINTER=""
for dir in "$HOME/.local/bin" "/usr/local/bin" "/usr/bin"; do
  [[ -z "$KUBECONFORM" && -x "$dir/kubeconform" ]] && KUBECONFORM="$dir/kubeconform"
  [[ -z "$KUBELINTER"  && -x "$dir/kube-linter" ]] && KUBELINTER="$dir/kube-linter"
done

if [[ -z "$KUBECONFORM" || -z "$KUBELINTER" ]]; then
  exit 0
fi

# ── kubeconform ──
echo "--- kubeconform: $FILE_PATH ---" >&2
"$KUBECONFORM" -summary "$FILE_PATH" 2>&1 || true

# ── kube-linter ──
echo "--- kube-linter: $FILE_PATH ---" >&2
"$KUBELINTER" lint "$FILE_PATH" 2>&1 || true

exit 0

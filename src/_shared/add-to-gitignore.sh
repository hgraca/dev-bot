#!/usr/bin/env bash
#
# devbot-exclude.sh
#
# Scans a folder for symlinks and writes them to a git ignore file
# (.gitignore or .git/info/exclude), wrapped in a tagged block.
#
# Every run replaces the block entirely, so the ignore list stays
# in sync with whatever symlinks currently exist in the folder.
# If the block doesn't exist yet, it is appended to the file.
#
# Usage:
#   ./devbot-exclude.sh [FOLDER] [OPTIONS]
#
# Arguments:
#   FOLDER                 Folder to scan for symlinks (default: .)
#
# Options:
#   --ignore-file <path>   File to write to (default: .git/info/exclude)
#   --header <string>      Opening marker for the managed block
#                            (default: ">>> DEVBOT - memory")
#   --footer <string>      Closing marker for the managed block
#                            (default: "<<< DEVBOT - memory")
#
# Examples:
#   ./devbot-exclude.sh
#   ./devbot-exclude.sh src/ --ignore-file .gitignore
#   ./devbot-exclude.sh --header "# BEGIN symlinks" --footer "# END symlinks"
#   ./devbot-exclude.sh src/ --ignore-file .gitignore \
#                            --header "# BEGIN symlinks" \
#                            --footer "# END symlinks"
#

# Defaults
FOLDER="."
IGNORE_FILE=".git/info/exclude"
HEADER=">>> DEVBOT - memory"
FOOTER="<<< DEVBOT - memory"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ignore-file)
      IGNORE_FILE="$2"
      shift 2
      ;;
    --header)
      HEADER="$2"
      shift 2
      ;;
    --footer)
      FOOTER="$2"
      shift 2
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      FOLDER="$1"
      shift
      ;;
  esac
done

# Find all symlinks in the folder
SYMLINKS=$(find "$FOLDER" -maxdepth 1 -type l -printf '%P\n' 2>/dev/null)

# Build the new block
NEW_BLOCK="$HEADER
$SYMLINKS
$FOOTER"

# Ensure the ignore file exists
mkdir -p "$(dirname "$IGNORE_FILE")"
touch "$IGNORE_FILE"

# If the section already exists, replace it; otherwise append
if grep -qF "$HEADER" "$IGNORE_FILE" 2>/dev/null; then
  awk -v header="$HEADER" -v footer="$FOOTER" -v block="$NEW_BLOCK" '
    $0 == header { in_block=1; print block; next }
    in_block && $0 == footer { in_block=0; next }
    !in_block
  ' "$IGNORE_FILE" > "$IGNORE_FILE.tmp" && mv "$IGNORE_FILE.tmp" "$IGNORE_FILE"
else
  printf '\n%s\n' "$NEW_BLOCK" >> "$IGNORE_FILE"
fi

echo "Updated '$IGNORE_FILE' with $(echo "$SYMLINKS" | grep -c .) symlink(s) from '$FOLDER'"

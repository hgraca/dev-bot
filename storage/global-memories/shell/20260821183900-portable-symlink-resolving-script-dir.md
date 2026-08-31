---
date: 2026-08-21
keywords: ["shell", "bash", "SCRIPT_DIR", "symlink", "readlink"]
---

## Portable symlink-resolving SCRIPT_DIR: the readlink loop, not readlink -f

When a bash script is symlinked as a **file** (e.g. dev-bot's `.agents/tools/<name>.sh` → `src/agentic/<mod>/tools/<name>.sh`), resolving its own directory must follow that file symlink. `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` only resolves _directory_ symlinks — it leaves a file-level symlink's parent (`.agents/tools`) as the dir, so a sibling `.py` next to the real script is not found. `readlink -f` resolves file symlinks but is GNU-only and absent on macOS. The portable idiom that does both (Linux Mint, Fedora, macOS):

```bash
SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
```

Do not shell out to `python3 -c 'os.path.realpath'` for this — macOS ships no `python3` by default, and a stubbed `python3` (in tests) turns `SCRIPT_DIR` into garbage.

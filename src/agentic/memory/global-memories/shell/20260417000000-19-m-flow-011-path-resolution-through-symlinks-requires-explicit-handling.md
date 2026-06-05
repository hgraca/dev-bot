---
date: 2026-04-17
keywords: ["bash", "shell"]
---

## M-FLOW-011: Path resolution through symlinks requires explicit handling

Wrapper script using BASH_SOURCE[0] with symlinked executables
BASH_SOURCE[0] returns symlink path not target - use readlink/realpath or inject absolute paths to avoid broken relative path calculations

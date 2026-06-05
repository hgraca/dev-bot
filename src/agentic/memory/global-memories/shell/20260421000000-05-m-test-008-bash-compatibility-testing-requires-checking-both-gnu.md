---
date: 2026-04-21
keywords: ["bash", "shell"]
---

## M-TEST-008: Bash compatibility testing requires checking both GNU and BSD variants

macOS uses BSD tools (readlink without -f) while Linux uses GNU tools
Shell scripts targeting both platforms need portable patterns. Test on both or use compatibility functions. Document platform-specific constraints.

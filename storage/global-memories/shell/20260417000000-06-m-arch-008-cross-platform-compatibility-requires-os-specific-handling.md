---
date: 2026-04-17
keywords: ["shell", "bash"]
---

## M-ARCH-008: Cross-platform compatibility requires OS-specific handling

sed -i syntax differs between macOS (BSD) and Linux (GNU), causing install failures on macOS
Test cross-platform scripts on both target platforms. Create wrapper functions for commands with different syntax.

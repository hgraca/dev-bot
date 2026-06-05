---
date: 2026-06-15
keywords: ["shell", "installer", "idempotency", "main", "wiring"]
---

## Installer idempotency guard must only guard the binary install block, not the entire main

A pattern like `if command -v tool &>/dev/null; then _skip "..."; return 0; fi` at the top of `main()` is common but wrong when `main()` also performs non-binary-install work (e.g., plugin wiring, config generation, systemd registration). The `return 0` exits the entire function before any downstream work runs.

On re-install (tool already in PATH), the guard exits immediately — plugin wiring, config regeneration, and other post-install actions never execute. On first install, the guard is skipped, binary install runs, and downstream work executes — so the bug is latent until re-install.

Fix: restructure `main()` so the idempotency check guards **only the binary install block** using an if/else. Downstream work (plugin wiring, etc.) executes unconditionally after the block, relying on its own idempotency checks (e.g., version file, existence check):

```bash
main() {
  if command -v tool &>/dev/null; then
    _skip "tool (already installed)"
  else
    # OS-specific binary install
    install_tool
    _ok "tool installed"
  fi

  # Plugin wiring always runs (idempotent via internal version check)
  _wire_tool_plugin
}
```

---
date: 2026-10-01
keywords: ["devbot", "refactor", "rename"]
trigger-on: ["php-rename-interface", "php-rename-trait", "refactor-rename-class"]
---

## `devbot tool refactor rename` leaves the declaration and `use` imports, while reporting success

Renaming a PHP interface or trait with `devbot tool refactor rename --kind class` moves the file correctly and rewrites `::class` and `instanceof` usages, but leaves the **declaration itself** and **every `use` import** on the old name. It lists them under "Unrewritten references (reported, not rewritten)" yet still prints `Applied: yes` / "Renamed … in N file(s)", so the tree is left with PSR-4 broken (file name ≠ declared name) and imports that no longer resolve. Always read that report and complete the enumerated lines by hand before running anything; `Applied: yes` does not mean the rename is complete. The dirty-tree guard behaves correctly — a second rename refuses until the first is committed.

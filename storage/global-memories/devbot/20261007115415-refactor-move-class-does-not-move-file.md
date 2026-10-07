---
date: 2026-10-07
keywords: ["devbot", "refactor", "move", "php"]
aliases: ["refactor move class", "refactor move does not move file"]
trigger-on: ["devbot-refactor-move-class"]
---

## `devbot tool refactor move --kind class` (PHP) rewrites references but does not move the file

`devbot tool refactor move --file X.php --kind class --from '<old FQCN>' --to '<new FQCN>' --apply` reports success ("Renamed … in N file(s)") and repoints the references, but leaves the class declaration and file in the old namespace/directory — so the references now point at a class that does not exist at that FQCN and the tree is broken. Root cause: in `src/agentic/refactor/langs/php/ops.py` the `move-class` spec sets `move_file`/`namespace_move` but omits `"declaration": "class"`, so the `move-target` step calls `find_declarations(kind: "")`, matches nothing and returns 0 — no target is emitted. Until the op is fixed, do the move by hand: `git mv` the file and its test, rewrite the `namespace`, and update the references the tool enumerated. This is the same family as the `rename` op leaving the declaration and `use` imports behind.

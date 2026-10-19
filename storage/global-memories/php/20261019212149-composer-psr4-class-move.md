---
date: 2026-10-19
keywords: ["php", "composer", "psr-4", "move-class", "autoload"]
aliases: ["psr-4 move destination", "classmap fallback", "global namespace move"]
---

## Resolving a class move through Composer PSR-4 maps

A class move must read `autoload`/`autoload-dev` `psr-4` (each prefix maps to a string or an array of base directories) instead of stripping the first namespace segment.

- Keep every base: the source FQCN must match the base that actually contains its file.
- Prefer the source base for the target when it also covers the target prefix; otherwise use Composer's first base.
- Check **every** target location for an existing file. An earlier base shadows the chosen one, and moving there produces a class that never loads.
- A namespaced target with no matching prefix is refused, not guessed.
- A source under a PSR-4 base whose path does not match its FQCN is a mismatch (refuse). A classmap/other-root source with no PSR-4 location falls back to the legacy namespace-tail layout.
- A global source still resolves a namespaced target through its mapping.
- A global target (empty `namespace_to`) is distinct from “no rewrite”: remove or insert the `namespace` declaration. Insert after `<?php` and any leading `declare`, preserving comments; `strict_types` must stay before the namespace.

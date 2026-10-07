---
date: 2026-10-08
keywords: ["php", "rector", "rename-class", "withImportNames", "ClassLike"]
aliases: ["RenameClassRector", "RenameDeclarationRector", "rector rename interface trait enum"]
trigger-on: ["rector-rename-class"]
---

## Rector's RenameClassRector skips the declaration site and leaves stale use imports

Renaming a class with Rector (2.6.7) leaves two independent gaps. First, `RenameClassRector` rewrites references — to the fully-qualified new name — but never the declaration site, so a companion rule must rename it; that rule must visit `PhpParser\Node\Stmt\ClassLike`, not `Class_` exclusively, or `interface`/`trait`/`enum` declarations are silently skipped and the file moves to its PSR-4 name while keeping the old declaration name. Rector matches node types with `is_a($nodeClass, $type, true)`, so the abstract `ClassLike` covers all four kinds in one registration. Second, without import handling the `use Old\Name;` line is left stale (the usage is rewritten to the fully-qualified new name); chain `->withImportNames()` on the `RectorConfigBuilder` — defaults rewrite the import to the new class and drop the now-unused one — inner-chained before the terminating `;`, unlike the void-returning `RectorConfig::importNames()`.

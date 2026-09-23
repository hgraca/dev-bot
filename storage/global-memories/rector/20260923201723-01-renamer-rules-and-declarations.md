---
date: 2026-09-23
keywords: ["rector", "renamer", "declaration", "rename-method"]
trigger-on: ["rector-rename-declaration", "rector-renamer-rules"]
---

## Rector's renamer rules disagree about rewriting declarations

Of Rector's renaming rules only `RenameMethodRector` (`Rector\Renaming\Rector\MethodCall\RenameMethodRector`) rewrites the method **declaration** as well as the call sites — its `getNodeTypes()` includes `Class_`/`Trait_`/`Interface_` alongside `MethodCall`/`NullsafeMethodCall`/`StaticCall`. `RenameStaticMethodRector` and `RenameClassRector` do **not**: they rewrite usages only (`StaticCall` / `Name` nodes), leaving `public static function make()` or `final class Widget` in place, so a rename driven by them emits broken code that references a name nothing defines. Verified against Rector 2.6.7 by editing a fixture and diffing the result. Two consequences: a "rename static method" op should use `RenameMethodRector` (it already covers static calls), and a class rename cannot be done with Rector's renamer alone — it needs the declaration and the PSR-4 filename handled separately.

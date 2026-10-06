---
date: 2026-10-06
keywords: ["php", "phpstan", "phpdoc", "codemod", "docblock"]
trigger-on: ["php-codemod-class-docblock"]
---

## A codemod adding a class-level annotation must merge into the existing docblock

When a script inserts a class-level phpdoc annotation (e.g. `@internal`) above a class, inserting a *second* docblock is wrong: PHPStan reads only the docblock immediately attached to the class, so the original one — and its `@template`, `@implements`, `@extends` — is lost, producing errors like `generics.notGeneric` ("class X is not generic") far from the insertion point. Merge into the existing docblock instead: if the line above the declaration (skipping `#[...]` attributes) is the closing `*/`, splice ` * @internal` in just before it; otherwise create a new docblock. Watch the detection: `rtrim(" */\n")` is `" */"`, not `"*/"` — the leading space defeats the comparison so the merge branch never runs. Use `trim(...) === '*/'`. Always run the project formatter afterwards (it separates phpdoc tags with a blank line) and static analysis to catch the lost-tag class of error.

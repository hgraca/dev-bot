---
date: 2026-09-29
keywords: ["php", "composer", "composer-dependency-analyser", "shadow-dependency"]
trigger-on: ["composer-shadow-dependency", "composer-dependency-analyser"]
---

## Declaring a directly-imported package beats suppressing the dependency analyser

`composer-dependency-analyser` flags a package that app code imports directly but that is present only transitively as `SHADOW_DEPENDENCY`; the tempting fix is `ignoreErrorsOnPackage('<pkg>', [ErrorType::SHADOW_DEPENDENCY])`, but the correct fix is to declare it — `composer require <pkg>` for runtime code, or `composer require --dev <pkg>` when only tests import it. Choosing the wrong section is caught: a package declared in `require` that only tests reference fails with `PROD_DEPENDENCY_ONLY_IN_DEV` (a docblock-only `use` in app code does not count as a prod usage). Two operational quirks: `composer remove <pkg>` exits non-zero with "Removal failed … may be required by another package" when the package stays installed as a transitive dep — it still strips the entry from composer.json, so chain with `;` not `&&` and follow up with `composer require --dev <pkg>`; and such a change cannot be folded into an older commit via `--fixup`/autosquash, because `composer.lock`'s content-hash is order-dependent — keep dependency-declaration changes as a tip commit.

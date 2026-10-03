---
date: 2026-10-02
keywords: ["php", "composer", "composer-dependency-analyser", "unused-dependency", "prod-dependency-only-in-dev"]
aliases: ["composer-dependency-analyser unused", "prod-dependency-only-in-dev", "dependency analyser config"]
trigger-on: ["composer-dependency-analyser-config"]
---

## composer-dependency-analyser: a production dep's error type flips when its last app-code use is removed

`shipmonk/composer-dependency-analyser` reports a production dependency used only from dev paths (tests) as `prod-dependency-only-in-dev`, but a production dependency used nowhere as `unused-dependency`. Removing the last non-test usage of a prod dep therefore changes the error _type_ for that package, and a pre-existing `ignoreErrorsOnPackage($pkg, [ErrorType::PROD_DEPENDENCY_ONLY_IN_DEV])` becomes stale — the analyser emits the new error plus a "Some ignored issues never occurred" warning for the now-unapplied ignore. The fix is to change the ignored `ErrorType` (e.g. to `UNUSED_DEPENDENCY`) rather than delete the ignore. When a package is deliberately a runtime-only prod dependency (needed by auto-instrumentation/exporter but referenced only in tests), keep it in `require` and ignore `PROD_DEPENDENCY_ONLY_IN_DEV`.

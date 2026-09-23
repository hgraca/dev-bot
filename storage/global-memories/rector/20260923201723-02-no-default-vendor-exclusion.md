---
date: 2026-09-23
keywords: ["rector", "withPaths", "vendor", "scope"]
trigger-on: ["rector-scope-paths", "rector-vendor-scan"]
---

## Rector has no default vendor exclusion — scope its paths explicitly

Giving `RectorConfig::withPaths()` a project root makes Rector descend into `vendor/`: it is not excluded by default (`PathSkipper` reads `Option::SKIP`, empty unless set) and dependency files get rewritten — observed rewriting `vendor/acme/Decoy.php` on a real run. On a large project this is a correctness problem *and* a runtime one: `core` carries ~29,886 vendor PHP files and `--clear-cache` defeats incremental reuse. Prefer listing the project's own source roots (`app/` for Laravel, `src/` for libraries — mutually exclusive) rather than the mount root, and/or add `->withSkip(['*/vendor/*', '*/node_modules/*', '*/storage/*', '*/var/*'])`. Guard it with a decoy fixture: a dependency file holding a same-named method that must survive the rename.

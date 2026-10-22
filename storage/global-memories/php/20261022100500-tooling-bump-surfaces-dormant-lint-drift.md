---
date: 2026-10-22
keywords: ["php", "phpstan", "larastan", "php-cs-fixer", "upgrade"]
trigger-on: ["dependency-upgrade", "ci-static-analysis"]
---

## A tooling dependency bump fails CI on files nobody touched

Upgrading `larastan/larastan`, `phpstan` or `friendsofphp/php-cs-fixer` as part of a framework upgrade turns CI red on code that was already there: the new version enables checks the repo was never held to (Larastan 1 → 3 brought `list<string>` covariance on `$fillable`/`$hidden`, Nova's `Builder` contract, missing returns; php-cs-fixer 3.95 enabled `new_with_parentheses`, `nullable_type_declaration`, `no_whitespace_in_empty_array` and reformatted 37 of 118 files).

Do not read this as a regression from the upgrade. Run the tool with the project's own config and, ideally, the exact version from the lock — a `ghcr.io/php-cs-fixer/php-cs-fixer` image tag can pin the release, and its `--version` tells you whether it matches. Commit the mechanical result as a separate formatting-only commit, and fix type errors at the source rather than lowering the analysis level: dropping `level: 5` to get green quietly discards years of checking.

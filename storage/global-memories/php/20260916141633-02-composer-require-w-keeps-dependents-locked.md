---
date: 2026-09-16
keywords: ["php", "composer", "composer-require", "locked-dependents"]
trigger-on: ["composer-require", "composer-dependency-conflict"]
---

## `composer require -W` is a partial update and never moves locked dependents

When `composer require -W <pkg>:<version>` fails with "X is locked to version Y and an update of this package was not requested", the cause is usually not a real constraint conflict: `require` performs a partial update, refreshing the named package and its dependencies, but never its dependents — the rooted packages that themselves require the target. Those stay frozen at their locked versions, and their own constraints then look like blockers. The fix is to edit the constraints and run a full `composer update`, which re-resolves the whole graph. Triage with `composer why-not <pkg> <version>` to see the truly constraining packages rather than trusting the conflict digest in the error, which names only the first intersecting pair.

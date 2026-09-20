---
date: 2026-09-16
keywords: ["laravel", "brick-math", "php-overlay", "dependency-conflict"]
trigger-on: ["laravel-major-upgrade", "brick-math-constraint"]
---

## Laravel 12 cannot coexist with brick/math 0.15+, and ramsey/uuid is the hidden gate

Every `laravel/framework` 12.x release constrains `brick/math` to `^0.11|^0.12|^0.13|^0.14`, while libraries that moved to brick/math 0.15+ (e.g. `get-e/php-overlay` >= 5.9 requires `^0.15.0||...`) do not intersect with that range — so installing the library forces a Laravel 13 upgrade, since the first release allowing `>=0.15` is v13.1.1. A second, easily missed gate sits behind it: `ramsey/uuid` 4.9.2 caps brick/math at `^0.14` and 4.9.3 relaxes it to `>=0.8.16 <=0.18`; with a root constraint already at `^4.9` composer can move it, but any partial update leaves it locked and the conflict looks unsolvable. Before accepting a major framework upgrade, run `composer why-not brick/math <version>` and check whether a patch release of the other constrainers lifts the ceiling.

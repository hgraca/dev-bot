---
date: 2026-11-09
keywords: ["phpstan", "phpstan-baseline", "named arguments", "ignore.unmatched"]
trigger-on: ["phpstan-baseline", "named-arguments"]
---

## Named arguments change PHPStan's message text, so baseline entries stop matching

PHPStan renders an argument error with the positional index when the call uses positional arguments
(`Parameter #1 $price of method ... expects ...`) but **without** it when the argument is passed by
name (`Parameter $price of method ... expects ...`). A `phpstan-baseline.neon` entry whose regex
expects `\#1 \$price` therefore stops matching as soon as that call switches to named arguments: the
full run reports the error unignored plus a non-ignorable `ignore.unmatched` for the stale entry.
Either keep positional arguments at such call sites, or update the baseline regex. A scoped
`phpstan analyze <path>` will not surface unmatched baseline entries — only the full analysis does.

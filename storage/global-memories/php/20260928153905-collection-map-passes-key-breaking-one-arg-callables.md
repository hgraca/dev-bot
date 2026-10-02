---
date: 2026-09-28
keywords: ["php", "collection", "array-map", "strict-types", "phpstan"]
trigger-on: ["collection-map-callable", "mb-strtolower-callable", "phpstan-argument-type-map"]
---

## Collection::map passes the key as a second argument — one-argument callables break

Laravel's `Collection::map()` invokes its callback as `$callback($value, $key)`. Passing a first-class callable of a single-argument function therefore feeds the integer key into the second parameter: `->map(mb_strtolower(...))` calls `mb_strtolower('Acme.COM', 0)` and throws `TypeError: mb_strtolower(): Argument #2 ($encoding) must be of type ?string, int given` under `declare(strict_types=1)`. `array_map` has no such problem — for a single array it passes only the value — which is why `array_map(mb_strtolower(...), $list)` is safe in the very same codebase.

PHPStan rejects the obvious repair as well. It types `Collection<(int|string), mixed>::map()` as `callable(mixed, int|string): mixed`, so `->map(static fn (string $d): string => mb_strtolower($d))` fails with `argument.type` — "Type string of parameter #1 $domain of passed callable needs to be same or wider than parameter type mixed" — even when the runtime values are always strings.

The way through is to leave the Collection behind for this kind of normalization: annotate the plucked array (`/** @var list<string> $domains */ $domains = $this->domains->pluck('domain')->all();`), then `array_map(mb_strtolower(...), $domains)` and `sort()`. Narrow first, map second.

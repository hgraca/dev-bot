---
name: php-rules
description: "PHP coding rules: strict typing, constructor promotion, type declarations, enums, comments, PHPDoc, array shapes. Read this annex when writing or reviewing PHP code."
---

# PHP Universal Rules

## When to Apply

- Writing or reviewing any PHP code
- Checking PHP type declarations, constructors, or enum conventions
- Writing PHPDoc blocks or array shape annotations

## Annex of `devbot:software-development`

This file is an annex of the `devbot:software-development` hub. Read it only when writing or reviewing PHP code. For generic craft — code-quality principles, tests-first discipline, commit protocol — see `devbot:software-development`.

## Strict Typing

- Always use `declare(strict_types=1);` at head of every `.php` file
- Always use curly braces for control structures, even for single-line bodies
- No raw `DateTime` — use Carbon

## Constructors

- Use PHP 8 constructor property promotion: `public function __construct(public GitHub $github) { }`
- Do not allow empty `__construct()` with zero parameters unless constructor is private

## Type Declarations

- Always use explicit return type declarations for methods and functions
- Use appropriate PHP type hints for all method parameters

```php
protected function isAccessible(User $user, ?string $path = null): bool
{
    ...
}
```

## Enums

- Keys in upper snake case: `FAVORITE_PERSON`, `BEST_LAKE`, `MONTHLY`

## Comments

- Prefer PHPDoc blocks over inline comments
- Never use inline comments unless logic is exceptionally complex

## PHPDoc Blocks

- Use phpstan array shapes to document arrays
- Array shapes used in several places: define as local phpstan type
- Array shapes used across files: define as custom phpstan type in owner class, import where needed
- Array shapes crossing module boundaries: convert to DTO

## PHPStan Hygiene Checks

Before accepting [FINISHED] on any PHP change, verify these:

1. **PHPUnit version check**: `./vendor/bin/phpunit --version` — if <10, use `/** @test` not `#[Test]`
2. **`fopen` + `stream_get_contents`**: Always check `fopen` for `false` separately before passing to `stream_get_contents`. Pattern:
    ```php
    $stream = fopen($url, 'r');
    if ($stream === false) { throw new \RuntimeException(...); }
    $result = stream_get_contents($stream);
    ```
3. **`match` exhaustiveness**: Always include a `default` case — `match` is exhaustive by design
4. **`null` handling**: When `levelFor()` or similar returns `?Type`, handle `null` with `?? throw` rather than letting `null` propagate
5. **`Closure::fromCallable`**: Prefer `static function` over `Closure::fromCallable` — both are equivalent but `static` is simpler

## Composer Dependency Management

When adding a PHP dependency to `composer.json`:

- MUST use `composer require` CLI tool (e.g., `composer require vendor/package:^1.2`)
- MUST NOT edit `composer.json` directly to add entries to the `require` or `require-dev` sections
- `composer require` atomically adds the entry in correct alphabetical position (respecting `sort-packages: true`), updates `composer.lock`, and validates dependency resolution — direct edits risk sort-order errors, stale lock files, and silent constraint violations

## See also

- `annexes/php/laravel.md`

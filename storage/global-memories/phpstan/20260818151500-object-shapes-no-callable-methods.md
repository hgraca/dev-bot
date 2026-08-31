---
date: 2026-08-18
keywords: ["phpstan", "object-shape", "phpdoc", "callable"]
trigger-on: ["phpstan-object-shape", "phpdoc-shape"]
---

## PHPStan 2.1 object shapes cannot declare callable methods

`/** @var object{up(): void} $x */` is a phpDoc parse error in PHPStan 2.1 ("Unexpected token '('"), and even `object{up: callable(): void}` parses but `$x->up()` still reports an undefined method — shape members are treated as properties, not methods. Property shapes DO work: `object{Type: string}`. Use them to type results of DB introspection (`SHOW COLUMNS` / `SHOW INDEX`) as `list<object{Type: string}>` instead of reaching for callable shapes.

---
date: 2026-10-15
keywords: ["php", "lazy-binding", "optional-dependency", "class_exists"]
aliases: ["unloadable class", "fatal on missing dependency", "lazy class resolution"]
trigger-on: ["php-optional-dependency-guard", "php-sdk-optional-class"]
---

## PHP resolves class and function references lazily, so a missing dependency does not make a class unloadable

A class whose body only _references_ an absent class or function still loads and instantiates: parameter and property type hints, `match` arms calling a missing class's static method, and `use function Missing\fn;` with an aliased call are all resolved at call time, not at declaration time. Only `extends`/`implements` of a missing class — or a compile-time constant expression — fails. So the claim "this class references a missing SDK class, therefore it is unloadable and will fatal" is almost always wrong, and a `class_exists()` gate added to prevent that supposed fatal is dead code. The check is a three-line script: declare such a class, instantiate it, print a line, run it with the dependency absent. Verified this way on `SentryHeartbeatReporter` (PHP 8.4) for all three constructs. The correct gate for an optional dependency is a **call-time** `function_exists`/`class_exists` guard, which is also what keeps the reference lazy.

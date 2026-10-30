---
date: 2026-10-22
keywords: ["php", "phparkitect", "rector", "ci", "config-test"]
aliases: ["matching unit violation", "testsWithoutSut", "HaveCorrespondingUnit", "AddTypeToConstRector"]
---

## A config-file test has no SUT — arkitect and Rector both object

Adding a test that asserts a **config array** (rather than a class) trips two GET-E/dev-tools CI gates at once:

1. **PHPArkitect `HaveCorrespondingUnit`** (`TestsRules::create()`): any TestCase under the `Tests\Unit` / `Tests\Integration` / `Tests\Functional` category must map to a real `App\…` class, so `Tests\Unit\Config\MessageBusConfigTest` demands `App\Config\MessageBusConfig` and fails with *"should have a matching unit named …"*. Two ways out: pass the test to the rule's exclusion parameter — `TestsRules::create(testsWithoutSut: new Orx(new IsA(MyTest::class)))` (the established pattern in these repos; `zendesk-synchronizer` already excludes `MessageBusTelemetryConfigTest` this way) — or move the test to a namespace the rule does not scan, such as `Tests\Feature` (core's `phparkitect.php` scopes its rule to `Tests\Console|Integration|Unit`). Note the rule strips a category prefix, so `Tests\Integration` is *not* a safe haven; and if you must edit `phparkitect.php`, remember it is outside Rector's scope but a fresh worktree may be missing generated dirs it lists.

2. **Rector `AddTypeToConstRector`**: `private const FOO = 'x';` must be `private const string FOO = 'x';` (PHP 8.3+ typed constants). Rector analyses only the paths its config declares — typically `['/app', '/tests']` — so `config/` and root files are never checked, and a leftover *pre-existing* Rector diff in `phparkitect.php` is not a signal that your change broke anything. Confirm scope before "fixing" an unrelated file.

Both are cheap to pre-empt: type your constants, and decide up front whether the config test belongs in `Unit` (needs `testsWithoutSut`) or `Feature` (excluded by default).

---
date: 2026-08-18
keywords: ["php", "phparkitect", "HaveCorrespondingUnit", "tests"]
trigger-on: ["phparkitect-have-corresponding-unit"]
---

## PHPArkitect HaveCorrespondingUnit requires a real src class for every test

The repo's `phparkitect.php` `HaveCorrespondingUnit` rule maps each test FQCN to a src FQCN (replace `\Test\` with `\`, strip trailing `Test`) and fails if that class does not exist. A test for a deliverable that is not a src-namespace class — e.g. a publishable package migration (anonymous class, shipped in the package `migrations/` dir) — has no corresponding unit and violates the rule. Fix: fold the test into an existing test class whose mapped SUT exists (the service provider that publishes the migration), rather than creating a standalone `tests/.../Migrations/` test class.

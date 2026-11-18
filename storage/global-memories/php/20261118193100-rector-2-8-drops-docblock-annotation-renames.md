---
date: 2026-11-18
keywords: ["php", "rector", "annotation", "engine pinning", "composer require"]
aliases: ["RenameAnnotationRector", "docblock rename stopped working", "floating engine version"]
trigger-on: ["rector", "composer-require", "refactor-engine"]
---

## Rector 2.8 stopped rewriting docblock annotations — pin the engine, and let the test fail loudly

A rule using `RenameAnnotationRector` / `RenameAnnotationByType` rewrote `@test` to `@scenario` on 2.6.x
and silently did nothing on 2.8.5, with the run still exiting 0 and reporting success. The regression
came in through a caret requirement (`composer require rector/rector:^2.6`), so a fresh provision picked
up whatever the newest minor was; nothing in the code or the tests named a version, and the e2e that
covered it skipped whenever no engine was installed — so the skip hid exactly the regression it should
have caught.

Two rules follow. Pin the engine to an exact version the shipped rules are verified against, report the
installed version (from `composer.lock`, not the constraint) from both `provision` and `doctor`, and
warn when a scratch install drifts. And make the version guard *fail* rather than skip when an engine
exists but is not the pinned one: a missing engine may skip, a wrong engine must not. A no-op apply
that returns `ok: true` is the other half of the trap — carry an explicit "did anything get written"
flag, and make it false after a rolled-back failure.

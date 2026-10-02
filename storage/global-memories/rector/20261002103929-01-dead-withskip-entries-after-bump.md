---
date: 2026-10-02
keywords: ["rector", "withSkip", "dependency-bump", "static-analysis"]
trigger-on: ["rector-with-skip", "rector-version-bump", "rector-skip-not-registered"]
---

## A Rector set-package bump can leave a `withSkip()` entry unregistered

`withSkip()` entries are matched against the rules the configured sets actually register, so a version
bump can strand one. Raising `driftingly/rector-laravel` 2.5.0 → 2.6.2 (which lifts `rector/rector` to
2.6.7) moved `Rector\Php83\Rector\ClassMethod\AddOverrideAttributeToOverriddenMethodsRector` out of
`LevelSetList::UP_TO_PHP_83`, and Rector reported `[WARNING] This skipped rule is never registered.
You can remove it from "->withSkip()"` naming that class. The same bump also activated
`IfToNullCoalescingAssignRector`, so the same dry run additionally reported `1 file with changes` and
exited **2** (see the exit-code note), failing the static-analysis gate. The warning means the skip no
longer matches any registered rule — it is inert, not harmful — so the fix is to prune the entry and
its now-unused import, then apply the newly active rules (`rector process`, not `--dry-run`). When the
config is built through a helper whose extra-skip argument defaults to `[]`, dropping the sole entry
means removing the argument entirely, not passing an empty array.

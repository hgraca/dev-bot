---
date: 2026-10-15
keywords: ["composer", "cweagans/composer-patches", "dependabot", "composer install"]
trigger-on: ["composer-patches", "dependabot-dependency-bump"]
---

## A local composer patch breaks the whole pipeline on the patched package's bump

When a repo patches a dependency with `cweagans/composer-patches` and Dependabot later bumps that same package, the patch is applied at `composer install` time. If upstream touched the patched lines, every patcher fails and `composer install` aborts:

```
- Patching <vendor/package>
##[error]No available patcher was able to apply patch <path> to <vendor/package>
In Patches.php line 288:
```

Because the patch runs during dependency installation, **every** CI job that installs dependencies dies at the same step — both a `Static analysis` and a `Unit tests` job fail identically, before any code or test runs. The red build carries no signal about the code under test.

Diagnosis: read the composer-install step of any failing job — the `Patching <package>` line followed by the patcher error is the tell. Confirm by diffing the vendor file the patch targets against the new version's source (release notes, upstream commit) to see whether upstream changed or removed the patched code.

Fix, in order of preference: (1) if upstream shipped the same fix, **delete the patch** — remove the `.patch` file, its `extra.patches` entry in `composer.json`, then refresh `composer.lock`; (2) otherwise re-port the patch onto the new upstream code. Never leave a patch pointing at lines that no longer exist.

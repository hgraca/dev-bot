---
date: 2026-09-16
keywords: ["phpunit", "display-details", "notices", "phpunit-13"]
trigger-on: ["phpunit-issue-details", "phpunit-config"]
---

## PHPUnit's "PHPUnit Notices" count needs displayDetailsOnPhpunitNotices, not displayDetailsOnTestsThatTriggerNotices

PHPUnit 10+ splits issue reporting into two independent families with separate config attributes: `displayDetailsOnTestsThatTrigger{Notices,Warnings,Errors,Deprecations}` covers issues raised by the code under test, while `displayDetailsOnPhpunit{Notices,Deprecations}` covers PHPUnit's own reports. A summary line reading "PHPUnit Notices: 120" belongs to the second family, so enabling only the `...OnTestsThatTriggerNotices` attribute prints no detail section at all — the bare count stays and the individual entries stay unattributable. Enable both families to make every reported issue list its test, message and location. Related trap: `--log-events-verbose-text` is itself deprecated in PHPUnit 13 (use `--log-events-text --with-telemetry`), so passing it injects a phantom deprecation into the very run it is diagnosing.

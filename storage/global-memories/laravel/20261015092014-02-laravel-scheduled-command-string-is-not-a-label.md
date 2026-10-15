---
date: 2026-10-15
keywords: ["laravel", "scheduler", "formatCommandString", "scheduled-task"]
aliases: ["Event::$command shape", "scheduled task command name", "artisan binary parsing"]
trigger-on: ["laravel-scheduled-task-command-parsing", "scheduled-task-labelling"]
---

## Laravel's scheduled-task command string is `<php binary> <artisan binary> <name> <parameters>` — never use the rest as a label

`Application::formatCommandString()` builds `sprintf('%s %s %s', phpBinary(), artisanBinary(), $string)`, and `ProcessUtils::escapeArgument()` quotes a word only when it needs to (Unix single quotes; Windows double quotes with backslashes doubled) — so a plain path such as `/usr/local/bin/php` stays bare. Two consequences follow. Splitting on whitespace breaks a **quoted path containing a space**; and "everything after the artisan binary" or "everything after stripping the PHP binary" still includes the parameters, which routinely carry secrets (`--token`, `--password`). Parse the two leading words as Laravel's shape — each word either bare or quoted (`(?:"[^"]*"|'[^']*'|\S+)`), either path separator, optional `.exe` — validate the first is a PHP interpreter and the second the artisan binary, then take only the third word matched against `[A-Za-z][A-Za-z0-9:_-]*`. Return nothing when that shape does not hold: a shell string that merely mentions artisan (`echo artisan report`) then yields no name rather than a bogus one, and a `->call(...)`/`->job(...)` task (`Event::$command` is null) has no command name at all. Related: `laravel/20261015090000-01-laravel-scheduled-command-runs-in-a-child-process.md` — its "strip the PHP binary" aside is not a safe label; see above.

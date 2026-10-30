---
date: 2026-10-29
keywords: ["github-actions", "composite-action", "defaults", "setup-php", "cache-extensions"]
aliases: ["Input required and not supplied", "empty with value", "action default ignored"]
trigger-on: ["github-composite-action-inputs", "workflow-call-input-defaults"]
---

## A composite action's `default:` never applies when the caller passes an empty value

`with: { cachekey: ${{ env.cachekey }} }` with no `cachekey` in `env:` sends `''`, and GitHub treats an explicitly supplied value as the argument — a declared `default:` is used only when the input is absent. The symptoms never point at the caller: `shivammathur/cache-extensions` aborts with "Input required and not supplied: key" and the failure is reported against whatever step wraps it (here, "Composer install"), while `shivammathur/setup-php` with an empty `php-version` silently installs the newest release, which then trips a lock file pinned at `php <8.5`. Fix it in the action by reading `${{ inputs.x || '<default>' }}`, or stop passing inputs the workflow has no value for; a contract test asserting that every input with a non-empty default is read through `||` catches the whole class.

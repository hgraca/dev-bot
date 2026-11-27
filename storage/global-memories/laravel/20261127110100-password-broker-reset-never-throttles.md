---
date: 2026-11-27
keywords: ["laravel", "password-reset", "PasswordBroker", "validation-error"]
aliases: ["reset throttled", "passwords.throttled", "dead reset link"]
trigger-on: ["laravel-password-reset", "form-request-error-keys"]
---

## `PasswordBroker::reset()` never returns `RESET_THROTTLED`

`Password::RESET_THROTTLED` comes only from `sendResetLink()`. The `reset()` path runs
`validateReset()`, which yields `INVALID_USER`, `INVALID_TOKEN` or the user, and then `PASSWORD_RESET`
— there is no throttle branch. A controller that maps `$status === Password::RESET_THROTTLED ? 'email' : 'token'`
therefore has an unreachable arm and a comment that lies about the flow; a test cannot cover it,
which is why the dead branch survives review.

Correct mapping for a reset form: every non-success status is a link that cannot be used, so key it
`token` and let the page replace the form with "request a new link". Throttling lives on the
_send_ screen, and `PasswordResetLinkController` usually discards that status anyway.

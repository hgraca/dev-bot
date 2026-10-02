---
date: 2026-09-28
keywords: ["laravel", "artisan", "confirm", "no-interaction", "backoffice"]
trigger-on: ["artisan-interactive-prompt", "artisan-confirm-no-interaction", "backoffice-run-command"]
---

## A confirm()-guarded command must refuse before prompting, not interpret the answer

`$this->confirm()` reaches `OutputStyle::askQuestion()`, and the interactivity decision lives *inside* Symfony's `QuestionHelper` — after the output-style call. Two consequences follow. First, in a project that surfaces console commands through a web runner appending `--no-interaction` (a backoffice "run command" page, a queue worker, a CI call), `confirm()` silently returns its default and the command "just fails" through the falsy branch; the operator never learns why. Second, in tests, Laravel's `PendingCommand` swaps in a Mockery mock of the `OutputStyle`, so `askQuestion()` is intercepted *before* any interactivity check: passing `'--no-interaction' => true` to `$this->artisan()` does not prevent the call, and the test dies with `BadMethodCallException: Received Mockery_..._OutputStyle::askQuestion(), but no expectations were specified`.

The fix for both is the same shape — test interactivity *before* asking, so the refusal is explicit and no prompt is reached:

```php
if (!$this->option('force') && !$this->input->isInteractive()) {
    $this->error('Refusing to delete without confirmation. Pass --force to delete non-interactively.');

    return self::FAILURE;
}

$confirmed = (bool) $this->option('force') || $this->confirm('...', false);
```

Test that path with `Artisan::call(...)` rather than `$this->artisan(...)`: `Artisan::call` uses the real `OutputStyle` (no mock), mirrors how a subprocess runner invokes the command, and its output is readable via `Artisan::output()`.

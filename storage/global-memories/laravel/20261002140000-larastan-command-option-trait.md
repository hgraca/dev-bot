---
date: 2026-10-02
keywords: ["laravel", "larastan", "phpstan", "artisan", "trait"]
aliases: ["console.undefinedOption", "undefinedOption", "command trait option"]
trigger-on: ["laravel-command-trait-option"]
---

## A trait that reads `$this->option()` fails Larastan when mixed into a command lacking that option

Larastan analyses a trait in the context of every class that uses it, so a shared trait calling `$this->option('owner-id')` triggers `larastan.console.undefinedOption` ("Command ... does not have option ...") on any command whose `$signature` omits that option — even when the trait's option-reading method is never invoked there. Keep option-reading helpers in a trait used only by commands that declare those options, and split an option-independent helper (e.g. a pure row-existence check) into its own trait when a command needs only that part.

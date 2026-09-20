---
date: 2026-08-31
keywords: ["phpunit", "assertAuthenticatedAs", "uuid-caster", "value-object"]
trigger-on: ["phpunit-assert-authenticated-as-value-object"]
---

## `assertAuthenticatedAs` fails when the model id is a cast value object

Laravel's `assertAuthenticatedAs($user)` compares `getAuthIdentifier()` with `assertSame` — same-instance semantics. When the model casts `id` to a value object (e.g. `'id' => [UuidCaster::class, UserId::class]` from `get-e/php-overlay`), the session-guard user and a freshly queried `$user` hold two **different `UserId` instances with equal values**, so the assertion fails ("currently authenticated user is not who was expected") even though auth is correct.

Fix: assert by value instead:

```php
$this->assertAuthenticated();
self::assertSame($user->id->getValue(), auth()->user()->id->getValue());
```

(`UserId` implements `Stringable`, so `auth()->loginUsingId($user->id)` works — only the assertion needs the value comparison.)

---
date: 2026-10-21
keywords: ["laravel", "auth-identifier", "stringable", "user-id", "value-object"]
aliases: ["getAuthIdentifier returns UserId", "is_int is_string skips UserId", "stringable auth id"]
trigger-on: ["auth-identifier", "user-id-tagging", "uuid-value-object-cast"]
---

## getAuthIdentifier() can return a Stringable value object, not just int|string

Code that guards a user id with `is_int($id) || is_string($id)` silently skips every model whose primary key is cast to a value object. A Laravel model such as `User` with `'id' => [UuidCaster::class, UserId::class]` returns a `UserId` (an `AbstractStringId` implementing `Stringable`) from `getAuthIdentifier()`, so no `user.id` attribute is emitted — no error, just missing tags, logs, or audit fields.

Accept `Stringable` alongside `int|string` and cast with `(string)`. Cover it with a test that uses the real value object (`new AuthenticatedUserStub(UserId::new())`), not only int/string stubs, because the int/string tests pass while every real user is skipped.

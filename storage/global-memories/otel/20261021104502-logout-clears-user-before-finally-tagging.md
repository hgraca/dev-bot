---
date: 2026-10-21
keywords: ["otel", "laravel", "logout", "user.id", "session-guard"]
aliases: ["logout span untagged", "Logout event listener", "session user flushed before finally"]
trigger-on: ["span-tagging-middleware", "logout-listener", "auth-events"]
---

## Logout requests lose user.id before a finally-based span tagger runs

Laravel's `SessionGuard::logout()` clears the session user and fires the `Logout` event. The request's user resolver is lazy (`fn ($guard) => Auth::guard($guard)->user()`), so by the time a global middleware's `finally` resolves `$request->user()` the user is null. A span tagger that only reads the user after `$next` therefore never tags logout requests.

Fix: register a listener for `Illuminate\Auth\Events\Logout` that tags the active span with `$event->user` — the event carries the user before it is flushed. Keep the middleware for every other path; the listener is the only hook that still sees the logout identity. Add a registration assertion (`Event::fake(); Event::assertListening(Logout::class, Listener::class)`) because a listener that is never registered fails silently.

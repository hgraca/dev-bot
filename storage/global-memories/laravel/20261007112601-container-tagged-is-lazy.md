---
date: 2026-10-07
keywords: ["laravel", "container", "di", "tagged"]
aliases: ["tagged is lazy", "eager resolution false positive"]
trigger-on: ["laravel-container-tagged"]
---

## Container::tagged() is lazy — a tagged class is not constructed until the iterable is iterated

`Illuminate\Container\Container::tagged($tag)` returns a `RewindableGenerator`; the `$this->make($abstract)` calls for the tagged classes run only when the iterable is iterated, so passing `$app->tagged('tag')` into a constructor does NOT resolve or construct those classes at that point. A code-review comment that asserts "`tagged()` constructs the registrar graph during boot" is therefore wrong unless something later iterates the generator. Verify such claims rather than accepting them: bind the suspect class (or an interface it needs) to a closure that throws, tag it under the real tag, resolve the consumer through the container, and assert it survives — construction that never happens cannot throw. The trap worth watching is the opposite — a consumer that type-hints an interface directly (eager construction), which is what actually touches globals such as `OpenTelemetry\API\Globals`.

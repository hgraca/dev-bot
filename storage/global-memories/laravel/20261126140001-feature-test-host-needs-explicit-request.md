---
date: 2026-11-26
keywords: ["laravel", "phpunit", "feature-test", "middleware"]
aliases: ["this->call host header ignored", "HTTP_HOST has no effect in a feature test"]
---

## A feature test's HTTP host cannot be set with HTTP_HOST — build the Request yourself

`$this->call()` and `$this->get()` in a Laravel feature test build the URI from the application's configured root, so passing `HTTP_HOST` or `SERVER_NAME` in the server array does not change `$request->getHost()`; middleware, route constraints and policies that key off the host therefore see `localhost` and the assertion fails only where the base URL differs — typically in CI. Pin scheme, host and path by constructing the request explicitly, `Request::create('https://portal.example.com/path', 'OPTIONS', server: [...])`, and invoking the unit under test directly (`new Middleware()->handle($request, static fn (): Response => new Response('ok'))`) instead of routing it through the test client.

---
date: 2026-08-24
keywords: ["php", "saml", "onelogin", "acs", "php-saml"]
trigger-on: ["onelogin-php-saml", "saml-acs", "saml-login"]
---

## onelogin/php-saml integration gotchas (strict mode, $_POST, destination)

When integrating `onelogin/php-saml` (v4): (1) strict mode REQUIRES a signed Response or Assertion — an unsigned response fails `processResponse` with "No Signature found" even when `wantAssertionsSigned` is false; (2) `processResponse()` reads `$_POST['SAMLResponse']` directly and does NOT accept a response argument — mirror `$_POST['SAMLResponse'] = $request->input('SAMLResponse')` before calling it; (3) validation failures are reported BOTH via `getErrors()` and by throwing `OneLogin\Saml2\Error` (e.g. "SAML Response not found", "Invalid SAML Response") — wrap processResponse in try/catch as well as checking getErrors(); (4) `Auth::login()`/`redirectTo()` with `stay=false` sends redirect headers directly and returns "never" — use `login(stay: true)` to get the URL and return `redirect()->away(...)` (testable); (5) destination validation compares the response's Destination attribute against onelogin's OWN computed self-URL (protocol + host + path), not the settings ACS URL — in CLI tests the host resolves to the container hostname, so pin `$_SERVER['HTTP_HOST']`/`REQUEST_URI` and `Utils::setSelfProtocol('https')` in tests and craft Destination from `Utils::getSelfURL()`; (6) `Utils::setSelfProtocol('https')` is needed when the framework detects the wrong protocol.

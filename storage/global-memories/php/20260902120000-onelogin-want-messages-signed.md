---
date: 2026-09-02
keywords: ["php", "saml", "onelogin", "wantMessagesSigned", "response-signature"]
trigger-on: ["onelogin-php-saml", "saml-acs"]
---

## onelogin `wantMessagesSigned` also defaults false — require response signatures against assertion re-wrapping

Like `wantAssertionsSigned`, onelogin/php-saml's `wantMessagesSigned` defaults to `false` even in strict mode (vendor `Settings.php`). With only `wantAssertionsSigned => true`, `processResponse` accepts an **unsigned response** whose assertion is signed: `SubjectConfirmationData/@InResponseTo` is not required, so a captured signed assertion can be re-wrapped in a fresh unsigned response with a new `InResponseTo` and replayed through a newly initiated correlation flow — the single-use correlation no longer binds the assertion to its original authentication. Set `'wantMessagesSigned' => true` (alongside `wantAssertionsSigned`) so only the IdP can bind an assertion to a request. Consequence for test fixtures: the response envelope must be signed too, not just the assertion (sign the `Response` element after the assertion, with the signature inserted before `Status`).

---
date: 2026-08-31
keywords: ["php", "saml", "onelogin", "wantAssertionsSigned", "acs"]
trigger-on: ["onelogin-php-saml", "saml-acs"]
---

## onelogin strict mode does not imply signed assertions — set `wantAssertionsSigned` explicitly

`onelogin/php-saml` strict mode (`'strict' => true`) does **not** require the SAML **assertion** to be signed: `wantAssertionsSigned` defaults to `false`, so a validly-signed _response_ carrying an unsigned _assertion_ is accepted. When the identity claims (givenname/surname/emailaddress) live in the assertion, that's the part you must trust — set `'wantAssertionsSigned' => true` in the `security` block of the onelogin settings. Note this complements (does not replace) the existing knowledge that strict mode requires the _response_ to be signed; both response and assertion signature requirements should be explicit for an ACS that provisions users from assertion attributes.

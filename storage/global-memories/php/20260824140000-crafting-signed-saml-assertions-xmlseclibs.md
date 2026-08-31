---
date: 2026-08-24
keywords: ["php", "saml", "xmlseclibs", "signature", "test"]
trigger-on: ["xmlseclibs", "signed-saml-assertion", "saml-test-fixture"]
---

## Crafting a schema-valid signed SAML assertion with xmlseclibs

To build a signed SAML Assertion for onelogin ACS tests: use `XMLSecurityDSig` with `setCanonicalMethod(EXC_C14N)` and `addReferenceList([$assertionNode], SHA256, ['http://www.w3.org/2000/09/xmldsig#enveloped-signature'], ['overwrite' => false, 'id_name' => 'ID'])`. The `id_name => 'ID'` option is essential: by default `addRefInternal` uses a generated lowercase `Id` attribute (XSD-invalid — saml-schema only allows uppercase `ID`) and a `#pfx...` reference URI that onelogin's `validateSign` (which sets `idKeys = ['ID']`) cannot resolve. After `sign($key)`, insert the signature with `insertSignature($assertionNode, $subjectNode)` so it sits between `saml:Issuer` and `saml:Subject` (schema element order) instead of being appended at the end. The IdP cert configured in the SP settings must be the public cert matching the signing private key.

---
date: 2026-09-18
keywords: ["entra", "saml", "federation-metadata", "appid", "signing-certificate"]
trigger-on: ["entra-saml-metadata-url", "azure-ad-appid", "saml-idp-metadata-url"]
---

## Entra's app-scoped SAML metadata needs a real Application (client) ID — a wrong GUID fails silently

Microsoft Entra's per-app federation metadata URL is `https://login.microsoftonline.com/<tenant>/federationmetadata/2007-06/federationmetadata.xml?appid=<application-client-id>`, where `appid` must be the app registration's **Application (client) ID** — a GUID. A non-GUID value (a URL, a slug, an entity ID) returns **HTTP 400**, which is the loud, obvious failure.

The dangerous case is a **well-formed but unregistered GUID**: it returns **HTTP 200** and silently falls back to the tenant's certificate set. Measured against a live tenant by counting distinct `<X509Certificate>` values: a real app's GUID returned exactly **1** dedicated signing certificate, an arbitrary GUID returned **4**, and all-zeros returned **6** — the tenant's rotating set. Because a SAML SP only validates that a signing certificate is present and parseable, the metadata sync reports success, the config reports "ready", and the failure surfaces much later as an XML-signature error at the ACS, presenting nothing like a configuration mistake.

Always verify the URL before configuring it: the response must contain exactly **one** distinct signing certificate. Get the value reliably by copying the entire URL from the app's own "App Federation Metadata Url" link (Entra → Enterprise Applications → app → Single Sign-on → SAML Certificates) rather than transcribing the GUID by hand. Remember it is per app registration: a second service provider (another instance, another environment, a staging vs production pair) needs its own app registration — or its own added Identifier + Reply URL on the shared one — not a copy of the first app's `appid`.

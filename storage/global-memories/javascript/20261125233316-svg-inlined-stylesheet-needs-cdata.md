---
date: 2026-11-25
keywords: ["javascript", "svg", "foreignObject", "xml", "cdata"]
aliases: ["inline stylesheet in svg", "ampersand breaks the export", "google fonts @import"]
---

## A stylesheet inlined into an SVG must sit in CDATA

Build a standalone SVG in the browser by copying `document.querySelector('style').textContent` into a `<style>` element and the file is invalid XML whenever the CSS contains a bare `&` — the Google Fonts `@import url(...&family=...)` that ships with the app map is enough. Chrome drops the whole document with "Unexpected token inside entity: =" and the export renders as a pink error page. Escaping is not the fix: `&amp;` inside a `url()` string changes the CSS. Wrap the text in `<style><![CDATA[...]]></style>` instead, which keeps the CSS byte-exact and the document well-formed; validate the output with `xml.etree.ElementTree` before believing a screenshot. The same trap applies to any raw-text element copied from the DOM into an SVG or XML document.

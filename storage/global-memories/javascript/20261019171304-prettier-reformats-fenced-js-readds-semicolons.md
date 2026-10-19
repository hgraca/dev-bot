---
date: 2026-10-19
keywords: ["javascript", "prettier", "markdown", "code-block", "browser-evaluate"]
aliases: ["prettier-ignore fenced block", "trailing semicolon function template", "browser_evaluate SyntaxError"]
---

## Prettier reformats fenced JS code blocks and re-adds a trailing semicolon

A fenced `js` block in Markdown is parsed and reformatted by prettier during the format-md hook. A function expression handed to a browser-evaluate tool must end at its closing `}`; prettier treats it as an expression statement and appends `;`, so `() => {…};` fails with `SyntaxError: Unexpected token ';'` once the tool wraps it. Deleting the semicolon alone is not durable — the next format run restores it. Put `<!-- prettier-ignore -->` immediately before the fence; prettier then leaves that block byte-for-byte untouched, and the documented snippet stays copy-pasteable.

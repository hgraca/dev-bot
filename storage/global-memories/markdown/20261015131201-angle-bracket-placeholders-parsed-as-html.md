---
date: 2026-10-15
keywords: ["markdown", "placeholder", "html-tag", "template"]
aliases: ["angle bracket placeholder disappears", "markdown eats <org>"]
trigger-on: ["authoring-doc-templates", "markdown-placeholders"]
---

## A bare `<placeholder>` in markdown prose is parsed as an HTML tag and disappears

Markdown passes anything shaped like `<tag>` through as raw HTML, so a template placeholder written bare in prose — `<org>`, `<repo>`, `<Project Name>` — is emitted as an unknown element and the text vanishes from the rendered page. Nothing errors and no linter flags it; the placeholder is simply gone, which is exactly the failure that survives review by eye. Wrap every placeholder in backticks (`` `<org>` ``) so it renders as inline code. Two places the rule does not bite, and one it does: inside fenced code blocks markdown does no inline parsing at all, and YAML/JSON bodies are data rather than prose, so bare placeholders are safe there — but a front-matter `description` or a table cell is still parsed (front matter is metadata, so it is inert in practice, though worth tidying). When shipping doc templates, audit mechanically instead of reading: strip inline code spans from each line (``re.sub(r"`[^`]*`", "", line)``) and flag any `<word>` left behind; the check is a few lines and catches leaks the eye misses.

---
date: 2026-05-02
keywords: ["graphify", "graph"]
---

## JavaScript regex `\Z` does not exist — silently matches literal `Z`

The `\Z` end-of-string anchor (Perl/Python) has no meaning in JavaScript regex — it's treated as literal character `Z`. In graphify.js, the section-extraction regex uses `\Z` as a fallback for end-of-content, causing sections at the end of a report (without trailing `---` or `## `) to silently fail extraction. Tests must use `---` terminators in fixtures to match real report format.
Fix: Source should replace `\Z` with `$` (with no `m` flag) or restructure the alternation. Tests work around this by including `---` terminators in test data.

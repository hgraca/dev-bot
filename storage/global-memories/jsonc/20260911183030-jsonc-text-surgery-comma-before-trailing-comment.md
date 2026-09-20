---
date: 2026-09-11
keywords: ["jsonc", "text-surgery", "comma", "comment", "json"]
trigger-on: ["jsonc-text-surgery", "comment-preserving-json-edit"]
---

## Comment-preserving JSONC text surgery: the separator comma goes before a trailing comment

When editing JSONC by text surgery (adding/removing object properties without a parse-and-dump round-trip), the separator comma belongs immediately after the value and **before** any trailing `// comment`: `"k": v, // note`. Two traps follow. First, appending a comma after the comment swallows it — the `//` runs to end-of-line, so `v // note,` parses as value + comment and the separator is missing → invalid. When emitting several added properties, only the non-last ones take a comma, and that comma must precede each property's comment. Second, to clean a dangling comma after removing the last property, scanning backwards from the closing `}` lands on the comment text, not the comma, so the comma is missed and a trailing comma remains before `}`. The robust fix for both is to anchor on the parsed property's byte spans (value_start/value_end/content_end) rather than regex or backward scans: insert the separator at `value_end`, insert new properties after `content_end`, and drop a dangling comma found just past the last remaining property's `value_end`.

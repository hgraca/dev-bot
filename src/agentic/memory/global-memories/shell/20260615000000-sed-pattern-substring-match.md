---
date: 2026-06-15
keywords: ["shell", "sed", "yaml", "grep"]
---

## sed range patterns match substrings — anchor with ^ and exact prefix

When using `sed -n '/PATTERN/,$ p'` to extract a YAML section, a simple pattern like `/volumes:/` matches `volumeMounts:` as a substring, pulling the wrong section. Always anchor YAML key patterns with `^` and the exact indentation level: use `/^      volumes:$/` not `/volumes:/`. Similarly, when counting items with `grep`, prefer `grep -c '\- name:'` over `grep -c 'name:'` to avoid matching non-list `name:` keys nested inside other blocks (e.g., `configMap.name`). Test sed ranges with `grep -n` first to verify the start line.

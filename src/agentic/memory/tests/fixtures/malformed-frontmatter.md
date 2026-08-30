---
name: malformed
description: "This file has no closing --- delimiter
---

# Malformed Frontmatter File

This file has a frontmatter opening `---` but the closing `---`
is malformed because the closing delimiter appears on the same line
as a YAML key. The `strip_yaml_frontmatter` function looks for
`\n---` anywhere after position 3, so this gets treated as various
edge cases depending on content.

Content below that should be searchable: edge case handling, malformed YAML

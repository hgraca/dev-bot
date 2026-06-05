---
name: unclosed
description: This file starts with frontmatter but never closes it
tags: [test, fixture]

# Unclosed Frontmatter

The opening --- starts the frontmatter block, but there is
no closing --- delimiter anywhere in this file.

The strip_yaml_frontmatter function should detect end == -1
and return the content unchanged.

This should be handled gracefully without crashing.

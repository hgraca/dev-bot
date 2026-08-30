---
name: devbot:documentation-rules
description: "Repository documentation conventions: file organization, README TOC, docs/ structure, splitting large files, image storage. Use this skill whenever writing documentation, creating new docs files, or updating the README — even if you do not say 'docs'."
---

# Repository Documentation

## When to Apply

- Writing or organizing repository documentation
- Creating new documentation files
- Updating README.md table of contents
- Deciding how to structure long documents

## Rules

- Text docs should be organized in `.md` files
- All docs should be organized under `docs/` folder on root
- Repo README.md must have TOC pointing to each text doc file under `docs/`
- Whenever new docs files created, README.md TOC must be updated to include them
- TOC must use indentation and enumerated sections to reflect nesting levels of documentation sections it points to
- Each subject should be self-contained in one `.md` file
- When `.md` file exceeds 200 lines and contains several sections:
    - Create folder with name of that `.md` file
    - Break up file into several files inside that folder, each new file containing one section of initial file
- Images used in documentation, should be stored under `docs/imgs/`
- After writing or editing any `.md` file, run `format-md` (built-in tool) on the file to align table columns. Add this as a post-write step — invoke `format-md path="<file>"` after every `.md` write.

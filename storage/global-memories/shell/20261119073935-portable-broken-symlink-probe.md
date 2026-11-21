---
date: 2026-11-19
keywords: ["shell", "find", "symlink", "portability", "macos"]
aliases: ["dangling symlink check", "broken link probe", "find -xtype", "BSD find"]
trigger-on: ["shell-symlink-farm-probe"]
---

## Probe broken symlinks portably: `find <dir> -type l ! -exec test -e {} \; -print`

`find -xtype l` is GNU-only, so a farm-integrity check built on it silently degrades on macOS/BSD. Neither obvious alternative covers both link kinds: `find -L <dir> -name '*.md'` **does** print a broken file link (only `-type f` filters it out), while a dangling **directory** link is never traversed at all, so it escapes every walk. The portable probe lists each broken link, file or directory:

```bash
find <dir> -type l ! -exec test -e {} \; -print   # empty output = nothing dangling
```

POSIX `find` plus `test -e` against the link path — works on GNU and BSD. Verified against a fixture holding one broken file link and one broken directory link: the portable form and GNU `-xtype l` both list both, `find -L … -type f` lists neither.

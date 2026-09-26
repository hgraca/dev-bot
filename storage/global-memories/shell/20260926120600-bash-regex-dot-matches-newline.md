---
date: 2026-09-26
keywords: ["shell", "bash", "regex", "bats"]
trigger-on: ["bash-regex-multiline-output"]
---

## Bash `=~` and bats-assert `--regexp` match across newlines

bash compiles `[[ $var =~ re ]]` without `REG_NEWLINE`, so `.` matches a newline and a multi-line `$output` is matched as one string. `refute_output --regexp 'ARGS:.*SECRET'` therefore MATCHES when `ARGS:…` is on one line and `SECRET` on another, and the refutation fails for a reason that has nothing to do with the code under test. `^`/`$` do not fix it: without `REG_NEWLINE` they anchor only the start and end of the entire string, so a per-line anchor fails to match a line that is not first or last. Assert per line instead — capture it (`line="$(printf '%s\n' "$output" | grep '^ARGS:')"`) and compare with a glob (`[[ "$line" != *"SECRET"* ]]`). The same trap applies when piping multi-line output into `grep` without `-z`. For an exact-output assertion, `assert_equal "$output" ""` is unambiguous.

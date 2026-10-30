---
date: 2026-10-30
keywords: ["git", "clone", "extraheader", "credentials", "config"]
aliases: ["clone -c is not command-scoped", "token written into .git/config"]
trigger-on: ["git-clone-credential"]
---

## `git clone -c key=value` writes that setting into the new repo's config

`-c` normally scopes a config value to the one invocation, so
`git -c http.https://host/.extraheader="Authorization: Basic …" clone <url> <dir>` looks like a safe
way to authenticate a clone without persisting the credential. It is not: **`clone` records the `-c`
settings into the newly created repository's `.git/config`**, so the header — and therefore the token —
lands on disk and outlives the command. Any later step can read it, and the whole point of avoiding a
credential in the URL is lost.

The form that actually keeps credentials transient is init + remote + fetch, where only `fetch` carries
the header and nothing writes it to config:

```bash
git init -q "$dir"
git -C "$dir" remote add origin "$url"                       # credential-free URL
git -c "http.https://host/.extraheader=$header" -C "$dir" fetch --depth 1 origin "refs/tags/$ref"
git -C "$dir" checkout -q --detach FETCH_HEAD
```

Verify with `git -C "$dir" config --get-regexp 'extraheader|url'` — you should see the URL and no
header. Two related details: scope the header to the host
(`http.https://github.com/.extraheader`, not a bare `http.extraheader`) so it cannot follow a redirect
to another origin, and mask any derived credential with `::add-mask::` in CI, because GitHub masks the
raw token but not a base64 of it.

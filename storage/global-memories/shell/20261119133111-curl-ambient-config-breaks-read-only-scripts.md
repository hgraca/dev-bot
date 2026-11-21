---
date: 2026-11-19
keywords: ["shell", "curl", "curlrc", "read-only"]
aliases: ["curl config override", "ambient request method", "disable curlrc"]
trigger-on: ["read-only-curl-script"]
---

## A read-only curl script is not read-only unless curl runs with `-q`

Every `curl` invocation reads `~/.curlrc` (and `$CURL_HOME/.curlrc`) before its own arguments, so a
config file containing `request = POST` or `data = @file` rewrites the request a script sends —
silently, with no change to the script. A probe whose every verb is a GET still arrives as a POST on
the target. Verified directly: with `request = POST` in `$HOME/.curlrc`, `curl -sS -o /dev/null -w
'%{http_code}' http://127.0.0.1:PORT/` returned 501 against Python's `http.server`; the same call
with `-q` as the first option returned 200. `-q` (`--disable`) must be curl's **first** argument — any
earlier option means the config has already been read. So write `curl -q -sS …`, and assert it in a
test that counts invocations against `curl -q -` occurrences; a grep for GET-only verbs cannot catch
this class of defect, because the verb is never in the script.

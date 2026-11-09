---
date: 2026-11-09
keywords: ["k8s", "kubectl", "jsonpath", "go-template", "field-manager"]
aliases: ["jsonpath map keys", "kubectl range map", "ssa field manager kubectl"]
---

## kubectl jsonpath cannot iterate a map — use go-template for keys

`-o jsonpath='{range $k,$v := .data}{$k}{"\n"}{end}'` fails with `unrecognized character in action: U+002C ','` — the jsonpath dialect only ranges over slices, not maps, and `{range $k := .data}` fails too. To list ConfigMap or Secret keys use `-o go-template='{{range $k,$v := .data}}{{$k}}{{"\n"}}{{end}}'`. Related trap from the same session: `kubectl apply --server-side` uses the field manager `kubectl` by default and migrates client-side-applied fields into it, so pass an explicit `--field-manager=<name>` on applies that must not adopt or prune fields owned by earlier applies — and still back the object up, since the migration's prune behaviour depends on which manager the object was last written by.

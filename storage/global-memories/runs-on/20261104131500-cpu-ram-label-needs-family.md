---
date: 2026-11-04
keywords: ["runs-on", "runner-label", "instance-family", "ram"]
aliases: ["no instance family specified", "failed to resolve runner spec", "cpu/ram label needs family"]
---

## A `cpu=`/`ram=` RunsOn label needs an explicit `family`

Dropping a named preset in favour of explicit resources fails at launch when no `family` is given:

```yaml
# FAILS in Runson "Set up runner":
# ##[error]Failed to launch runner: failed to resolve runner spec: no instance family specified
runs-on: runs-on=${{ github.run_id }}/cpu=4/ram=32/extras=s3-cache/image=my-image

# works — the family picks which instance types may satisfy cpu/ram
runs-on: runs-on=${{ github.run_id }}/cpu=4/ram=32/family=r7i+r8i/extras=s3-cache/image=my-image
```

The `runner=<preset>` labels (`runner=4cpu-linux-x64`) work without `family` because the preset
carries one. With bare `cpu=`/`ram=` you must supply it, and it has to be a family that can actually
satisfy the pair — `cpu=4/ram=32` is the r-class xlarge shape (`r7i.xlarge`, `r8i.xlarge`), so an
m- or c-class family would never match. The job dies in ~8 s, before any step runs, so it looks like
a broken workflow rather than a bad label.

To raise memory only, either keep the preset and override the resource (`runner=4cpu-linux-x64/ram=32`,
untested here) or go fully explicit with `family=`; the explicit form is what shipped.

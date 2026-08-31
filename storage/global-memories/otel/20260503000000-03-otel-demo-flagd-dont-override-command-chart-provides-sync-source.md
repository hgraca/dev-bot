Overriding flagd's `command` removes the `--uri` flag that points to the feature flag ConfigMap. Flagd crashes with "no sync implementation set". The chart's default command + init container handle this correctly.
Fix: Don't set `command` or `imageOverride` for flagd — let chart defaults work.

Overriding flagd's `command` removes the `--uri` flag that points to the feature flag ConfigMap. The chart's default command includes `--uri file:/etc/flagd/config.json` which is populated by an init container from a mounted ConfigMap.
Fix: Don't set `command` or `imageOverride` for flagd — let the chart handle it.

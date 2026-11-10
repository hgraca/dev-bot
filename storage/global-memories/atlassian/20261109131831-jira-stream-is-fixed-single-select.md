---
date: 2026-11-09
keywords: ["atlassian", "jira", "stream", "customfield_10139", "value stream"]
---

## Jira `Stream` is a fixed single-select — agents cannot add options to it

`Stream` (`customfield_10139`) is a single-select option field on this site, present on **both** Epic and Task createmeta, whose nine values (Transfers core platform, Transfers UX, Transfers Get-e efficiency, Travel partnerships, Architecture general, Hotel platform, Positioning platform, Integrations product, Integrations customer projects) are admin-managed. The Atlassian MCP exposes no operation to add an option, and a user without Jira admin permission cannot add one in the UI either — so any plan that files work under new value-stream names is unexecutable through the MCP. Read `allowedValues` from `getJiraIssueTypeMetaWithFields` before promising a grouping: either reuse an existing option (`Architecture general` is the only fit for platform engineering) or model the stream as an epic and set `Stream` on that epic instead. Discover with "add option to a custom field select list" returns unrelated focus-area and align operations, confirming no such operation exists.

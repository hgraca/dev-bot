---
date: 2026-09-01
keywords: ['php', 'enum', 'json_encode', 'json-serialize', 'api-resource']
trigger-on: ['php-enum-json-serialize', 'api-resource-enum-value']
---

## PHP backed enums are not JSON-serializable — json_encode yields `{}`, not the case value

A backed enum (`enum Status: string { case ACTIVE = 'active'; }`) has no `JsonSerializable` implementation and no public properties, so `json_encode($enum)` silently produces `{}` — no error, no value. When an API resource returns the enum object (`'status' => $this->resource->status`), clients receive `"status": {}` while tests that never assert that field stay green. Serialize explicitly with the backing value: `'status' => $this->resource->status->value`. Same applies to any value object that does implement `JsonSerializable` — it works, but returning `->getValue()` explicitly is clearer and immune to refactors that drop the interface. Add an assertion on the serialized field (`assertJsonPath('data.status', 'active')`) — the bug only surfaces when a test reads the field.

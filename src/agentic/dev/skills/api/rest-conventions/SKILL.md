---
name: devbot:rest-conventions
description: "RESTful API conventions: URL structure, HTTP methods, response envelopes, pagination, errors (RFC 9457), filtering, sorting, headers, naming, versioning. Use this skill whenever designing or reviewing API endpoints, writing controllers, defining route structures, or choosing an HTTP status code — even if you are only adding one endpoint."
---

# RESTful API Conventions

Status: Accepted | Date: April 3, 2026

## When to Apply

- Designing new API endpoints or reviewing existing ones
- Writing controllers or route definitions
- Defining response shapes, error formats, or pagination
- Reviewing API naming conventions

## URL Structure

- Pattern: `/api/v{N}/{resources}`
- Resource names: plural, lowercase, kebab-case nouns
- Resource identifiers: UUID v7
- Nested resources: max one level deep (strong parent-child ownership only)
- Deeper nesting forbidden — use filtering on child resource

```
GET    /api/v1/bookings
POST   /api/v1/bookings
GET    /api/v1/bookings/{id}
PATCH  /api/v1/bookings/{id}
PUT  /api/v1/bookings/{id}
DELETE /api/v1/bookings/{id}
GET    /api/v1/invoices/{id}/line-items
```

## HTTP Methods

| Method   | Route             | Semantics      | Idempotent | Status |
| -------- | ----------------- | -------------- | ---------- | ------ |
| `GET`    | `/resources`      | Paginated list | Yes        | `200`  |
| `POST`   | `/resources`      | Create         | No         | `201`  |
| `GET`    | `/resources/{id}` | Retrieve       | Yes        | `200`  |
| `PUT`    | `/resources/{id}` | Full update    | Yes        | `200`  |
| `PATCH`  | `/resources/{id}` | Partial update | No*        | `200`  |
| `DELETE` | `/resources/{id}` | Delete         | Yes        | `204`  |

\* Design `PATCH` handlers for idempotency where possible.

## Non-CRUD Actions

`POST /api/v1/{resources}/{id}/actions/{verb}`

- Verb in imperative mood, kebab-case
- All other URL segments must be nouns
- Body carries action-specific parameters
- `200` for state change, `202` for async

```
POST /api/v1/transfer-bookings/{id}/actions/approve
POST /api/v1/invoices/{id}/actions/finalize
```

## Response Envelope

**Single resource:**

```json
{
  "data": {
    "id": "01961c3e-7a00-7000-8000-000000000001",
    "type": "transfer-booking",
    "attributes": { "status": "confirmed", "pickup_at": "2026-04-15T10:30:00Z" }
  }
}
```

**Collection:**

```json
{
  "data": [{ "id": "...", "type": "transfer-booking", "attributes": { "...": "..." } }],
  "meta": {
    "cursor": { "next": "eyJpZCI6IjAxOTYxYzNlIn0=", "previous": null },
    "per_page": 25
  }
}
```

- `type`: kebab-case resource name
- `POST` create: `201`, `data` envelope + `Location` header with resource URL
- `DELETE`: `204 No Content`, no body

## Pagination (Cursor-Based)

| Parameter  | Description              | Default |
| ---------- | ------------------------ | ------- |
| `per_page` | Items per page (max 100) | 25      |
| `cursor`   | Opaque base64 token      | —       |

- `meta.cursor.next` is `null` when no more results
- First request omits `cursor`

## Errors — RFC 9457

Content-Type: `application/problem+json`

```json
{
  "type": "VALIDATION_ERROR",
  "title": "Validation Error",
  "status": 422,
  "detail": "The pickup moment must be in the future.",
  "errors": { "pickup_at": ["The pickup_at field must be a future date."] }
}
```

| Field      | Required | Description                                                          |
| ---------- | -------- | -------------------------------------------------------------------- |
| `type`     | Yes      | Stable, machine-readable problem identifier                          |
| `title`    | Yes      | Short human-readable summary (same for all occurrences of this type) |
| `status`   | Yes      | HTTP status code                                                     |
| `detail`   | No       | Occurrence-specific explanation                                      |
| `instance` | No       | URI identifying this occurrence                                      |
| `errors`   | No       | Field-level validation errors (extension member)                     |

## Filtering, Sorting, Searching

**Filtering:** bracketed `filter` params, AND logic

```
GET /api/v1/transfer-bookings?filter[status]=confirmed&filter[city]=amsterdam
```

- Multiple values: `?filter[status]=confirmed,pending`

**Sorting:** `sort` param, comma-separated, `-` prefix for descending

```
GET /api/v1/transfer-bookings?sort=-created_at,passenger_name
```

**Searching:** `filter[search]` param

```
GET /api/v1/transfer-bookings?filter[search]=amsterdam+airport
GET /api/v1/transfer-bookings?filter[search][custom-fields]=airport&filter[status]=confirmed
```

## Headers

**Request (required):** `Accept: application/json`, `Content-Type: application/json`, `Authorization: Bearer {token}`

**Response (required):** `Content-Type: application/json` or `application/problem+json`, `Location` on `201`

## Naming Conventions

| Concern           | Convention              | Example                      |
| ----------------- | ----------------------- | ---------------------------- |
| URL segments      | kebab-case, plural noun | `/transfer-bookings`         |
| JSON keys         | snake_case              | `pickup_at`                  |
| Query params      | snake_case              | `per_page`, `filter[status]` |
| Path params       | snake_case              | `{booking_id}`               |
| Action names      | kebab-case verb         | `/actions/mark-as-read`      |
| Problem type URIs | kebab-case              | `/problems/validation-error` |

## Versioning

- Version: positive integer (`v1`, `v2`, ...)
- New version only for breaking changes
- Maintain previous versions until consumers migrate and deprecation period passes

## YAGNI

Build APIs per these conventions, but only implement what is needed when it is needed. Not every endpoint requires all features described here.

## See also

- `devbot:architecture-rules` skill

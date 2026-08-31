---
date: 2026-08-19
keywords: ["laravel", "jsonresource", "jsonresponse", "data-wrapper", "api"]
trigger-on: ["jsonresponse-jsonresource-wrapper", "api-response-data-envelope"]
---

## Wrapping a JsonResource in new JsonResponse() drops the data envelope

`new JsonResponse(new SomeResource($model))` serializes the resource through `JsonResource::jsonSerialize()`, which returns the raw `resolve()` array — so the top-level `{"data": ...}` wrapper is absent. The wrapper is only applied when the resource is returned directly from a controller (or via `->response()`), which routes through `ResourceResponse::wrap()`. The manual `new JsonResponse(...)` therefore silently changes the API shape to a bare array/object. When the `data` envelope is intended, return the resource directly or call `->response()->setStatusCode(...)`.

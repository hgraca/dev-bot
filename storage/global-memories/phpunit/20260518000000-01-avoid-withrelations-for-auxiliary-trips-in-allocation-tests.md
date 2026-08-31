---
date: 2026-05-18
keywords: ["phpunit", "factory", "mongodb", "performance", "withRelations"]
---

## Avoid `withRelations()` for auxiliary trips — use minimal factory instead

`Trip::factory()->withRelations()->create()` is deprecated and creates a MongoDB `EstimateOption` document for every trip, adding ~0.5–1s per call. When a test helper creates auxiliary trips (e.g. `addTrip()` to seed trip counts for allocation logic), those trips only need the `transport` relation — not EstimateOption, TripPassenger, TripPoints, or TripCancellationPolicy. Replace with `Trip::factory()->create(['is_cancelled' => false])` + `factory(TripTransport::class)->create(['trip_id' => $trip->id])` + `$trip->refresh()`. Reserve `withRelations()` only for the primary trip under test that genuinely needs all relations. This pattern saved ~3–4s per test in `ChooseTransporterServiceTest` and `AllocateToSupplierServiceTest`.

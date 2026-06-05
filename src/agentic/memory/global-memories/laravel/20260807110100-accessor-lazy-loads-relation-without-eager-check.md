---
date: 2026-08-07
keywords: ["laravel", "eloquent", "accessor", "n+1", "lazy-load"]
trigger-on: ["eloquent-accessor-lazy-load", "get-attribute-lazy-load", "guest-accessor"]
---

## Custom accessors that return relations trigger N+1 when not eager-loaded

When a custom accessor like `getGuestAttribute()` calls `$this->bookingGuests->first()`, every access to `$model->guest` triggers a lazy-load of the `bookingGuests` relationship if not already loaded. Callers that receive the model without eager loading will hit this silently. Mitigations: (a) add `->loadMissing('bookingGuests')` at the call site just before access, (b) add `->with(['bookingGuests'])` to the upstream query, or (c) both for defense-in-depth when the model flows through multiple service layers.

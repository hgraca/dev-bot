---
date: 2026-09-22
keywords: ["phpunit", "factory", "faker", "flaky", "trip-factory"]
trigger-on: ["eloquent-factory-random-business-state"]
---

## A factory that randomises business-critical state makes every consumer flaky

`TripFactory::definition()` drew `is_closed` and `is_cancelled` from `faker->boolean`, and `tracking_status` from every `TrackingStatus` case. Any test consuming the factory without pinning those three therefore depended on a coin flip: `AssignedDriverObserverTest::it_notifies_the_passengers_when_the_allocation_gets_a_driver` failed on the 1-in-5 `DROPPED_OFF` draw, because `Trip::canBeClosed()` returns true for that status (with `is_closed`/`is_cancelled` false and `isConfirmed()` vacuously true for an empty `confirmationRequests` relation), so `AssignedDriverObserver::saved()` returned before calling the mocked sender and Mockery reported `send(...) should be called exactly 1 times but called 0 times`. The same failure appearing on an unrelated branch (core run 35610282637) is the tell that the flake is not the PR's own doing. Fix at the factory rather than in each test: give the state a deterministic default and let tests opt into other values — randomising a field a business rule branches on buys nothing and hides a per-test flake rate. When triaging, a proven mechanism beats a count: the draw is 1-in-5 yet the failure appeared in only 2 of 25 CI runs, which is sampling noise, not evidence against the mechanism.

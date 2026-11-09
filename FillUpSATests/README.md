# Functional tests

Select the **FillUpSA** scheme and an iPhone simulator, then choose **Product > Test** (Command-U). The existing FillUpSATests target is included in the scheme.

The suite uses Swift Testing. Parameterized tests exercise multiple fuel IDs, brand aliases, stored limits, timestamp formats, and HTTP status codes.

| Suite | Coverage |
| --- | --- |
| StationTests | Fuel IDs, brand aliases, operator precedence, regular/premium Diesel selection, missing prices, Codable persistence |
| AppStateTests | First-launch defaults, settings persistence, invalid stored values, station-limit bounds, cached history, legacy history decoding |
| FuelAPITests | Endpoint/query construction, response joins, price units, timestamps, opening hours, missing coordinates, distance order, filtering before limits, malformed data, HTTP/offline errors, cancellation |
| FuelHistoryServiceTests | History request range/order, ISO timestamps, server source, invalid dates, HTTP/decoding/transport errors |
| AppRefreshTests | Refresh results and fetch timestamp, brand exclusions, offline/cancelled refresh retaining data, stale refresh rejection, history merging and offline preservation |

Service tests inject fixed HTTP responses at the request boundary; they do not call live servers. AppState tests use unique UserDefaults suites that are removed after each case. Production initializers still default to the shared services and standard preferences. The app-host process may perform its normal launch work; test assertions do not depend on that work.

The overlapping-refresh test uses continuations to control completion order without timing delays. Original refresh tests query far from the device; collection tests inject a known device coordinate, clock and no-op geofence handler to verify local persistence without registering real geofences.

These are logic and service tests, not XCUIAutomation tests. UI behavior is checked separately through simulator interaction.

## Verification result — 9 November 2026

Build-for-testing succeeded. The expanded suite ran 105 cases: 105 passed, 0 failed, 0 skipped.

Interactive checks on iPhone 18 Pro simulator, iOS 27.2, confirmed live prices, fuel/brand switching, place search and details. The expanded verification used an Adelaide simulator location:

- Cheapest displayed five stations within 25 km at 206.5, 206.5, 207.5, 207.5 and 208.3 cents, with distance ordering for tied prices and station-specific navigation labels.
- Trends displayed populated 7D, 30D and 90D charts labelled “South Australian market average”.
- Before narrowing downloads to the selected fuel/range, read-only inspection of the app's persisted history found **10,374 server records** (1,729 per fuel), spanning 4 October 10:30 UTC through 9 November 12:30 UTC. This verifies the real paginated loader retrieved more than the REST API's default first page.
- The same persisted history contained **six device observations**, one for each fuel, recorded at 9 November 12:43:05 UTC. Local collection was therefore working while server history was already cached.
- One local observation per fuel was insufficient; the populated chart selected server data. Automated tests separately verify that adequate local coverage selects local data and avoids a download.
- No crashes or layout issues were observed on Cheapest or Trends. The injected simulator location was cleared and the interaction session closed.

Observed issue: the default 60 station markers overlap heavily on the Adelaide map, obscuring prices. This visual issue was recorded, not changed by the test work.

Not exercised interactively: station-limit editing, external navigation handoff, widgets, CarPlay, or physical-device background/geofence alerts. Local collection and populated Cheapest/Trends were verified in the simulator, not on physical hardware.

## Cheapest and history regression coverage

- CheapestStationsTests: top five within 25 km, price then distance ordering, missing/invalid fuel prices, Premium Diesel fallback, brand exclusions, missing location, request failure and cancellation.
- HistoryCollectionTests: nearby-refresh statistics persisted to isolated defaults, no collection without location or for remote searches, hourly collection independent of server samples, 90-day retention, 7/30/90-day local coverage, server request/fallback/persistence, offline preservation and retry.
- HistoryPaginationTests: fetch beyond the first 500 records and reject partial downloads when a later page fails.

Local history is sufficient when it covers at least 75% of calendar days in the selected period (minimum two days) and has an observation within 24 hours. Otherwise the app requests server history and displays server points if available; it retains local points when the request fails. Local and statewide averages are not combined. History downloads are scoped to the selected fuel and time range, with a fixed upper date across pages. Fresh coverage is persisted across relaunches and reused for 30 minutes, including smaller ranges within it. Larger ranges or a different fuel trigger their own requests. Downloads preserve other cached fuels/ranges. Startup no longer prefetches history; opening Trends requests it when needed. Background refresh requests 30 days for the preferred fuel. Expired ranges are currently refreshed in full, rather than incrementally.

Local observations are collected on successful refreshes within 5 km of the device, using fetched stations within 25 km, at most once per hour per fuel. This is foreground/use-driven collection, not an independently scheduled hourly sampler. Background refresh downloads server history.

A live Swift request through the updated service for seven days of 91 returned **335 records**, all for 91, with the newest capture at 9 November 12:30 UTC. Regression tests cover query scope, cached coverage, expiry and preservation of other fuels.

## Read-only server health check

Run from the repository root:

```sh
python3 scripts/verify_history_server.py
```

This uses the same public read key as the app, performs no writes, and checks the last 24 hours for fresh captures, all six fuel types, valid aggregates, duplicates and uninterrupted 30-minute collection. A nonzero exit means a health check failed.

On 9 November 2026 at 12:40 UTC (23:10 Adelaide), it found 282 records in 47 complete six-fuel batches. The latest capture was 12:30 UTC (23:00 Adelaide), 10 minutes old. Aggregate values and fuel coverage were valid, but the **02:00 UTC / 12:30 Adelaide capture was missing** between 01:30 and 02:30 UTC. The health check correctly failed for that gap. Server collection is active, but uninterrupted delivery is not verified. Determining the missing run's cause requires the server's scheduler/function logs; no server deployment or backfill was performed.

## Older-phone regression runs

Run the suite across the three configured older-phone profiles from the repository root:

```sh
python3 scripts/run_device_tests.py
```

The runner tests sequentially and saves a log and `.xcresult` bundle per destination plus `summary.json`. Use `--device 'FillUpSA iPhone SE 3'` (repeatable, also accepts UUIDs) to select devices, and `--results /tmp/fillup-results-new` to choose the output directory. Profiles must exist in Xcode's Devices and Simulators window. You can also select each profile in Xcode and press Command-U.

Verified through Xcode on 9 November 2026:

| Simulator profile | Result |
| --- | --- |
| FillUpSA iPhone 11 | 105 passed, 0 failed |
| FillUpSA iPhone SE 3 | 105 passed, 0 failed |
| FillUpSA iPhone 13 mini | 105 passed, 0 failed |
| iPhone 18 Pro | 105 passed, 0 failed |

Additional interactive SE 3 / 13 mini checks could not complete: the interaction tools reported connection failures, insufficient simulator resources and activation timeouts. Retrying with other simulators shut down also timed out. No small-screen screenshots were captured and these errors do not establish an app defect. All interaction sessions were closed; the matrix's automated results above remain valid.

All configured profiles use the installed iOS 27.2 runtime. The app deployment target is iOS 26.0; a working iOS 26 runtime is still needed to test the minimum OS. Older model profiles exercise screen geometry and simulator behavior, but do not emulate their physical CPU, memory pressure, battery or radio performance. Physical-device checks remain necessary before claiming broad hardware compatibility.

## Repeatable device checks

| Scenario | Expected result |
| --- | --- |
| First launch, allow or deny location | Map remains usable; without a location fix, Cheapest explains that location is unavailable |
| Refresh | Loading finishes; successful fetch replaces prices; failure retains already loaded stations |
| Fuel selector and Settings fuel picker | Selected fuel changes map results; Diesel uses Premium Diesel only when regular Diesel is absent |
| Brand filters and Show All | Disabled brands disappear; Show All restores all brands |
| Stations shown | Values are constrained to 1–100; changing the value refreshes results |
| Search station name/address, then a town | Matching stations appear; submitted place search moves the map |
| Tap station | Details show selected fuel, address and opening hours; directions opens the selected navigation app |
| Cheapest with an Adelaide location | Up to five stations within 25 km, sorted by price with distance breaking ties |
| Trends | 7D/30D/90D controls update the period; missing history displays an empty state |
| Relaunch | Fuel, excluded brands, station limit and navigation choice persist |
| Widget | Check each fuel configuration with location allowed and denied, and after refresh |
| CarPlay | Check station list, fuel selection and navigation in CarPlay |
| Background/alerts on physical device | Verify history refresh, region entry, notification permission and 12-hour alert cooldown |

Location-dependent results, external navigation, widget/CarPlay interaction and background/geofence delivery require separate runtime checks; passing the unit suite does not certify these.

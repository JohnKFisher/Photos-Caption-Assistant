# PhotoKit Scan Benchmark And Guarded Rollout Plan

## Purpose
- Compare the current AppleScript scan path against an experimental PhotoKit scan prototype.
- Prove identity safety before any pivot by checking that PhotoKit-derived asset IDs still resolve through the existing AppleScript-backed preview/export/read/write path.
- Keep the current app default unchanged during this phase.
- Gather parity and performance data before considering any broader pivot.

## Scope
- Experimental prototype covers only:
  - `count(scope:)`
  - paged `enumerate(scope:offset:limit:)`
  - `library`
  - plain `album(id:)`
- Explicit non-goals for this phase:
  - metadata reads
  - metadata writes
  - overwrite behavior
  - picker resolution
  - caption-workflow queue resolution
  - Photos lifecycle/restart readiness
  - export/acquire behavior

## Parity Gates
- No unexplained count mismatch for library or tested albums.
- No unexplained ID-order drift for `photosOrderFast`.
- No worse failure clarity than the current path.
- No material memory regression during full scans.
- No runtime default changes based on speed alone.

## Benchmark Coverage
- `count` wall time
- first asset wall time via `enumerate(offset: 0, limit: 1)`
- first page wall time
- full paged scan wall time
- page-by-page parity at multiple page sizes
- read-only identity proof on sampled PhotoKit assets
- acquisition-path proof on a smaller sampled subset
- resident-memory delta observations for full scans
- timeout incidence during full scans
- cold vs warm repeat timings

## Running The Benchmark
- Default test suite keeps the benchmark skipped.
- The app now exposes an app-hosted benchmark entry under `Diagnostics > Run Scan Benchmark`.
- The app also exposes `Diagnostics > Run Identity Write Probe` for an explicit sacrificial-asset write/restore test.
- The app-hosted benchmark now requests Photos access if needed and defaults to the first `1000` assets per scope so large libraries finish in a reasonable time.
- If the optional album sample cannot be mapped from the AppleScript album ID to a PhotoKit collection, the benchmark now reports that and continues with the whole-library comparison instead of aborting.
- The main window now includes a Diagnostics section where you can optionally override the benchmark album and enter the sacrificial/control/smart-album IDs needed for the write probe.
- Prefer the app-hosted path on this machine, because it uses the existing `Photo Description Creator.app` Photos and Automation permissions.
- Enable the real-library benchmark with:

```bash
PDC_RUN_PHOTOS_SCAN_BENCHMARK=1 swift test --filter PhotoKitScanBenchmarkTests/testGenerateLocalParityAndSpeedReportWhenEnabled
```

- Optional environment variables:
  - `PDC_BENCHMARK_PAGE_SIZES=250,128,64`
  - `PDC_BENCHMARK_WARM_ITERATIONS=1`
  - `PDC_BENCHMARK_ALBUM_ID=<album-id>`
  - `PDC_BENCHMARK_ALBUM_NAME=<album-name>`
- `PDC_BENCHMARK_MAX_ITEMS=<positive-int>`

## Current Guarded Rollout
- The app now uses the PhotoKit incremental scan path in production only when all of these are true:
  - scope is `library` or a plain `album(id:)` that PhotoKit can resolve
  - no capture-date filter is active
  - traversal order is `photosOrderFast` or `random`
- The app intentionally keeps AppleScript as the production scan path for:
  - any run with a capture-date filter
  - `oldestToNewest`, `newestToOldest`, and `cycle` traversal orders
  - `picker` and `captionWorkflow` scopes
  - any album ID the PhotoKit path cannot resolve
- AppleScript remains the source of truth for:
  - metadata reads
  - metadata writes
  - overwrite gating
  - picker resolution
  - caption-workflow stage resolution
  - Photos lifecycle/readiness handling
  - export/acquire behavior

## Interpretation Notes
- This phase measures scan/count behavior only.
- AppleScript remains the source of truth for metadata reads and writes.
- The guarded production rollout only replaces incremental scan/count in the safe scopes listed above.
- If order parity drifts but read-only identity proof stays clean, treat that as an ordering issue, not an automatic wrong-photo failure.
- The write probe is the stronger gate: it must show that the sacrificial asset is the one that changed, the control asset stayed untouched, and the original metadata was restored.
- For smart albums that remove assets once they receive a caption, disappearance after the sentinel write is acceptable only if the same asset can still be re-resolved by identity and restored correctly.
- If PhotoKit cannot resolve a requested plain album ID for the guarded rollout, the app keeps using the AppleScript scan path for that run and logs the reason.
- If the plain `swift test` route lacks Photos permission, run the same benchmark from the app menu instead of changing the default app behavior.
- For explicit deep runs, set `PDC_BENCHMARK_MAX_ITEMS=full` (or another positive integer) when using the test harness.

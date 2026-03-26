# PhotoKit Scan Benchmark Plan

## Purpose
- Compare the current AppleScript scan path against an experimental PhotoKit scan prototype.
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
- resident-memory delta observations for full scans
- timeout incidence during full scans
- cold vs warm repeat timings

## Running The Benchmark
- Default test suite keeps the benchmark skipped.
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

## Interpretation Notes
- This phase measures scan/count behavior only.
- AppleScript remains the source of truth for metadata reads and writes.
- The experimental PhotoKit path must never silently replace the current path in this phase.
- If parity drifts, treat the report as evidence for further design work, not as approval to flip behavior.

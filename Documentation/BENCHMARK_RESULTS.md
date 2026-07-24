# RC1 benchmark results

Run date: 2026-07-24

Reference environment:

- macOS 26.5.1 (25F80)
- arm64
- APFS data volume with 27 GiB free at the time of the run
- Release build
- Real one-byte files created under a generated temporary fixture

Fixture creation is recorded separately and is not included in scan time.

| Files | Directories | Fixture creation | Scan | Throughput | Peak RSS | Findings |
|---:|---:|---:|---:|---:|---:|---:|
| 10,000 | 100 | 9.52 s | 2.44 s | 4,102/s | 25.8 MiB | 4 |
| 50,000 | 200 | 70.92 s | 11.87 s | 4,211/s | 50.0 MiB | 4 |
| 100,000 | 400 | 117.25 s | 30.28 s | 3,302/s | 42.4 MiB | 4 |

All runs measured the exact requested file count, reported zero issues and kept
directory aggregation bounded at four findings.

## Reference regression thresholds

These thresholds are for this machine and fixture only. They are not a product
speed promise:

- 10,000 files: scan under 5 seconds
- 50,000 files: scan under 20 seconds
- 100,000 files: scan under 45 seconds
- Peak RSS below 150 MiB
- No count mismatch, crash or unbounded Finding growth

The first 50,000-file trial showed 410 MiB peak RSS because the benchmark
fixture generator accumulated Foundation autorelease objects. Adding a scoped
autorelease pool reduced the repeat run to 50 MiB without changing the scanner.
This invalid first measurement is retained here to explain the benchmark
correction.

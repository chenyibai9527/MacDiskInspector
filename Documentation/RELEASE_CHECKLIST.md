# 0.2.0 RC quality gate

## Automated

- `swift test` passes.
- `swift run DiskInspectorCoreVerification` passes.
- Universal Release build contains `arm64` and `x86_64`.
- App icon, privacy manifest, App Sandbox and user-selected read-only entitlement are present.
- Benchmark measures the requested unique-file count exactly.
- Deep cache fixture produces at most five aggregate findings.
- Issue details remain bounded while total issue count remains accurate.

## Performance

Run the release benchmark with 10,000, 50,000 and 100,000 one-byte files.
Record fixture creation separately from scan time. The initial RC threshold is
based on the current reference Mac and is a regression guard, not a promise for
all disks.

Reference thresholds:

- 10,000 files under 5 seconds
- 50,000 files under 20 seconds
- 100,000 files under 45 seconds
- Peak RSS below 150 MiB

## Manual

- Scan can be cancelled without stale results replacing a newer scan.
- Sorting does not visibly freeze the window.
- Scanning card width remains stable while paths change.
- Empty files show `0 B`; non-empty values below 1 KB show bytes.
- Light and dark appearance remain legible.
- Community ZIP documents Gatekeeper “Open Anyway” without asking users to
  disable Gatekeeper globally.
- No test scans user data outside generated fixtures.

The development Mac cannot satisfy the clean-user Gatekeeper gate after running
local builds. Complete that item on a clean account or another Mac.

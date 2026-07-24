# 0.2.0-rc1 acceptance report

Date: 2026-07-24

## Passed

- 18 tests in 3 suites.
- Independent core safety verifier.
- Universal `arm64` and `x86_64` Release build.
- App Sandbox and user-selected read-only entitlement.
- Privacy manifest and compiled AppIcon.
- Ad-hoc community package code-signing integrity.
- 10k, 50k and 100k real-file benchmarks.
- Exact unique-file counts and bounded directory aggregation.
- Cancellation propagation test completes in under 0.1 seconds.
- No production `Process`, `URLSession`, file deletion or file move API found.

## Performance reference

| Files | Scan | Peak RSS |
|---:|---:|---:|
| 10,000 | 2.44 s | 25.8 MiB |
| 50,000 | 11.87 s | 50.0 MiB |
| 100,000 | 30.28 s | 42.4 MiB |

See `BENCHMARK_RESULTS.md` for fixture details and limitations.

## Gatekeeper result

A quarantined, fresh-bundle-ID copy was launched through App Translocation, so
quarantine propagation was confirmed. This development Mac has already run
multiple builds and cannot prove the untouched-user “Open Anyway” flow. The
community package must still be downloaded and opened on a clean macOS account
or another Mac before public release.

Command-line `spctl` returned a non-zero assessment with a Code Signing
subsystem internal error for the ad-hoc build. The app's internal code signature
and entitlements independently verified successfully.

## Remaining manual gates

- Clean-account Gatekeeper first launch.
- macOS 13, 14, 15 and current-version launch matrix.
- Dark appearance, increased contrast and VoiceOver review.
- Long-running whole-volume scan on a disposable test volume.

RC1 is suitable for source-based testing and a clearly labelled technical
community preview. It is not yet a frictionless general-public release.

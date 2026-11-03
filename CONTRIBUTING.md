# Contributing

Read [SECURITY.md](SECURITY.md) before sharing a bug or diagnostic. Source publication and downloadable app releases have separate readiness checks.

## Develop

Use macOS with Xcode 16+ and Swift 6. Open `Package.swift` in Xcode, or run:

```sh
swift test
bash scripts/build.sh
python3 scripts/check_repository.py
python3 scripts/check_documentation.py
python3 scripts/update_readme_badges.py --check
python3 -m unittest discover -s scripts -p 'test_*.py'
bash scripts/verify-native-controls.sh --no-build
```

SwiftUI/AppKit form the app, `MakerPulseCore` holds parsing/analytics/storage and the probe is an opt-in live public-data diagnostic. Legacy target names and identity values are intentional; preserve existing libraries, preferences and Keychain access across changes.

Add meaningful regression tests for changes to parsing, auth, pagination, alert deduplication, decimal math, day boundaries and data selection. Never replace unavailable data with zero, invent original follow dates, or treat a failed/incomplete crawl as a complete baseline. Keep local-day observations distinct from UTC reports.

## Screenshots and presentation

```sh
bash scripts/capture-demo.sh
```

Only the labeled offline demo may supply tracked screenshots. Use original fictional fixtures/artwork; do not copy a live library. Inspect every image for names, messages, balances, local paths, tokens and unexpected windows. Documentation capture renders only the app's own views, never another application or the desktop.

Deck sources and optional Python dependencies are in `docs/presentation`. Those dependencies are documentation tools, not app runtime dependencies. Review PDF/PPTX text, metadata, reading order and image descriptions after regeneration.

## Pull requests

Explain the problem and resulting behavior, cite relevant validation, and include only demo screenshots. Keep changes focused. Do not add new third-party runtime dependencies, telemetry, credential imports or external data services without discussion.

CI uses manual dispatch with read-only repository permissions and no account credentials. Do not add `pull_request_target`, privileged scripts, opaque downloads or secret-bearing logs. The native control suite uses a new fictional library and unique QA bundle; it exercises the dashboard, filters, sorting, My Prints, appearance, text sizing and window/menu routing without loading Keychain or the live library. It requires a logged-in macOS desktop session.

Contributions are licensed under the repository's [MIT license](LICENSE). Third-party artwork and code require their own compatible permission and attribution.

README badges record local validation, not CI. After source changes, save fresh `swift test` and `bash scripts/build.sh` logs, then run `python3 scripts/update_readme_badges.py --write --test-log <test-log> --build-log <build-log>`. The check rejects source/version changes until evidence is regenerated. Logs stay outside the repository.

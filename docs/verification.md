# Verification

This public-facing record omits earlier private-machine paths, account identifiers and live observations. Historical versions remain a pre-publication privacy review item; replacing this file does not remove Git history.

## Local checks

```sh
swift test
bash scripts/build.sh
python3 scripts/check_repository.py
python3 scripts/check_documentation.py
python3 -m unittest discover -s scripts -p 'test_*.py'
```

Swift tests cover parsing, pagination, retry policies, SQLite persistence, quiet baselines, follower first-observed semantics, milestone/event deduplication, decimal reconciliation, calendar/DST boundaries, activity ordering, latest-check comparisons, appearance, text size, layout persistence, first-account setup, demo provenance and HTTPS origin restrictions.

The release build packages and verifies an ad-hoc signed macOS app. Local compilation is not notarization, cross-platform compatibility or a security guarantee.

The 3.6 source-preparation milestone passed **107 Swift tests**, the optimized app build/signature check and **3 repository-guard tests** locally. The documentation pass checked **40 relative links**, **16 PNG metadata containers**, and the nine-page PDF / nine-slide editable deck. Offline Vision OCR checked all **15 native media PNGs** for the selected privacy patterns with no findings. All nine PDF pages were rendered with native PDFKit and visually reviewed. Figure descriptions, tagged PDF structure, language/title metadata and external PowerPoint relationships were checked separately; this is not a PDF/UA or screen-reader certification. See [presentation verification](presentation/README.md).

## Native visuals

```sh
bash scripts/capture-demo.sh
```

The capture uses fictional original fixtures and artwork with a separate temporary library. It does not read a real profile, live database, Keychain session, private inbox or balances. Native Light/Dark screenshots cover the dashboard, Cards, Compact, history, followers, activity and menu summary. Media is visually reviewed and checked for identity/path leakage before staging.

Private isolated-library audits previously exercised native watch filters, Cards/Compact actions and persistence, identical shared observations, menu actions, pause during refresh, polling changes, window close/reopen, unchanged-refresh recency, text-size slider/persistence/reset, narrow widths and 150% text. Those private libraries, images and reports are excluded from Git.

The 3.6 native regression pass produced **95 private render images** with no reported audit issues. Controls for filters, menu actions, text size, layout persistence and unchanged-refresh behavior passed. Resolved minimum palette text contrast measured 7.56:1 in dark mode and 5.85:1 in light mode; this measures the checked palette pairs, not every rendered pixel or a full accessibility certification.

The tested **3.6 (build 21)** app was installed and reopened at the existing user Applications location. Its running executable matched the tested bundle. The single bottom Dock target, saved creator, watch choices and appearance/polling/notification/text/layout preferences were verified preserved. A fresh public profile observation was recorded after launch. Account-feed availability remains separately dependent on the saved session and upstream services.

## Visual README revision

The opening hero was replaced with a complete 1440-pixel-wide native Dashboard capture, including every section through the final history row. The documentation window bypasses physical display-height constraints; its detail viewport must contain the full content before capture succeeds. Both appearances are available. Three labeled, seven-second GIFs use native Cards/Compact and history controls, plus a fictional print increment passed through the actual latest-check comparison logic. Their combined size is under 500 KB, with static posters and reduced-motion alternatives.

GitHub's Markdown rendering endpoint accepted the final markup. An isolated browser checked image loading, changing GIF content and all three reduced-motion poster selections with external page network requests blocked. This uses GitHub-sanitized HTML and local review styling, not a claim of pixel-identical GitHub site CSS. Native images, GIF frames and the refreshed deck cover were visually inspected. Raw captures and browser profiles remain outside Git.

The revised capture code passed the optimized build and all **107 Swift tests**. Offline OCR checked **20 media PNGs** and **16 decoded GIF/browser review frames** with no selected privacy-pattern findings. The local checks passed **49 relative links**, **21 PNG metadata containers**, the three seven-second GIFs and the refreshed nine-page/nine-slide presentation. These checks supplement visual and source review; they do not prove the absence of every possible private datum.

## Verification limits

- No account is required by the unit suite or documentation demo. Neither establishes current live authenticated-feed availability.
- Notification logic is tested; delivery still depends on macOS authorization and the app running. There is no server-push service.
- The deployment target is macOS 14. Local build/UI checks used Apple Silicon and Xcode 26.0.1 / Swift 6.2. Oldest-target and Intel execution remain unverified.
- CI is explicitly manual and is not presented as a completed remote run. Pushing does not automatically consume hosted macOS runner time.
- See [security review](SECURITY_REVIEW.md) and [release readiness](RELEASE_READINESS.md) for remaining publication and distribution decisions.

## Reward reason correction — 3.7

The point ledger was already integrated; a client-side server-ID requirement incorrectly hid available reasons from balance activity. It is replaced with exact decimal reconciliation over saved observation windows and account-scoped local occurrence identities. Model incentives, print-profile incentives, boost donors/source, unknown types, and supplied incentive dates are parsed separately. Date-only incentive fields retain their UTC calendar day.

The expanded **122-test** suite covers those payloads, fractional splits, metadata-stable identities, legitimate identical boosts across pages, repeating mixed/server pages, delayed ledgers, a balance-read/crawl race, restart deduplication, pending timeouts and quiet repairs. The optimized build and isolated native checks cover reward rows in both themes at 100% and 150% text, plus existing dashboard/menu/watch/layout controls. Private cached observations were used to verify the reported issue; no private payload, identity, balance or screenshot was added to Git.

Existing balance activity is enriched in place when saved samples establish a comparison window. Original IDs/read states are preserved and old notifications are not replayed. Unknown or non-reconciling windows remain explicitly pending. Point notifications wait up to 30 minutes for matching ledger data, then notify once with the pending state; later data quietly improves saved activity. The tests exercise notification attribution/deduplication logic. They do not manufacture a real MakerWorld reward or establish a new end-to-end OS notification delivery event.

Local fingerprints describe observed entries and preserve identical-row multiplicity; they are not server transaction IDs or proof of a unique causal event. Full crawls reject changed totals and repeated mixed/server pages. The API's lack of unique IDs still limits independent verification of truly identical records.

## Dashboard sorting, charcoal/yellow design and matching icon — 3.8.1

The 127 Swift tests pass, including metric ordering, unknown-versus-zero values, deterministic ties, lifetime versus selected-window gains, and saved sort defaults. Native controls were exercised for all six sort options, both bases, range-label propagation and persistence, along with Cards/Compact, watch filters, menu actions and 150% text. Sorting does not mutate observations or watch choices. The optimized 3.8 functional build passed isolated native QA with zero reported issues; 3.8.1 changes only packaging/version and the matching original charcoal/yellow app icon. Its unsigned executable is identical to that UI-tested build. Fresh tests and optimized packaging also pass for 3.8.1.

The updated palette preserves blue latest-check NEW and violet print emphasis. Tests retain contrast checks for primary/secondary/metric text, control labels and focus contrast. Measured minimum resolved text contrast is 6.19:1 on the dark surface and 5.85:1 on the light surface. Natural point-activity reasons retain uncertainty for unmatched transactions; thumbnails are larger and Compact preserves every metric/action.

The README now introduces the workflow in plain language, places the PDF/editable deck prominently near the top, and uses readable single-column native component demos. The complete uncropped Dashboard remains available in both appearances. The three seven-second GIFs total approximately 0.54 MB and have static reduced-motion fallbacks. Six self-hosted badges distinguish local tests/build evidence from remote CI; their check rejects stale source/version claims. Five Python guard/tool tests pass.

All media was regenerated from fictional offline native data after the final UI/icon changes. Browser review uses GitHub-sanitized HTML and local review styling, checks loaded/accessible images, changing GIF content and reduced-motion posters with external page network blocked. It is not a pixel-identical GitHub CSS guarantee. The nine-page PDF and editable slide deck are structurally checked and natively rendered; PowerPoint and screen-reader execution remain unverified.

The final 3.8.1 (build 24) bundle was installed and reopened from the existing single bottom Dock target. The running signed executable matches the packaged build. Saved preferences, watch choices and prior activity IDs were verified preserved. Native application-icon and Finder-icon captures show the matching charcoal/yellow mark after a targeted stale Finder registration refresh. The monochrome menu template and status/badge behavior are retained. No permission prompt was accepted.

## Native My Prints — 3.9 (build 25)

The independent Swift read-only task integration was verified using the existing app session, without Studio/browser credential extraction or a new persistent credential grant. A complete paginated live crawl returned 81 unique cloud jobs, with supplied titles, covers, printer/plate names, start/end timestamps and estimates. The exact private cover bucket was verified; the native image pipeline loaded three real thumbnails without altering signed URLs. No real task payload or image is tracked.

All 142 Swift tests pass, including account isolation, SQLite restart, status updates, retained missing jobs, duplicates, actual-count pagination, repeat/changing/incomplete page rejection, date/search/printer/status/sort behavior, unknown values, elapsed-versus-estimated time and signed-URL origin checks. Isolated native QA reports zero issues and verifies real native filter/search/sort actions, missing-data details, light/dark layouts and 150% text alongside existing menu/dashboard/watch controls.

The tested optimized app was installed and reopened at the existing Dock target. The running binary matches the packaged build; app identity, preferences, watch choices and activity retention were verified. The installed app then imported all 81 unique account-scoped jobs into the live local library. No print commands, reprint actions or initial-import print notifications were added. Stopped codes remain grouped as canceled/failed; no exact cancellation reason or consumed-filament measurement is invented.

Packaging now strips local debug symbols before ad-hoc signing. The resulting executable has zero checked machine-home path matches and passes strict signature and exact bundle-inventory checks. Release preflight separately verifies version, architecture, extracted ZIP/DMG contents and checksums. Assets remain locally prepared until the separate historical privacy/publication decision is resolved; no notarization or fresh quarantined-download launch is claimed.

Local release preflight created version-matched arm64 ZIP and DMG assets with SHA-256 checksums and a source/build manifest. The ZIP was freshly extracted and the DMG mounted read-only; both app copies pass exact file inventory, architecture, version/build, signature and binary-equality checks. DMG integrity and both checksum entries pass. Gatekeeper's read-only assessment rejects the ad-hoc preview, as disclosed; no security setting was changed and no quarantined/public download execution is claimed.

## Dashboard range/sort pointer correction — 3.9.1

Real mouse dispatch on a private copy reproduced the user report: Today stayed selected after clicks on 24 hours and 7 days, while the underlying saved range data differed. The visible sort control's binding worked when called directly, but its pointer region was obscured. The cause was visually clipped, aspect-filled model images whose hit regions extended into the toolbar. Constraining image and card hit shapes restored pointer delivery without changing history or calculation rules.

The regression harness uses native window mouse events and compares the same selection data rendered by the dashboard. It covers repeated Today/24-hour/seven-day switches, return to Today, native popup opening and menu-item dispatch, totals versus gain ordering, both card layouts, light/dark and 150% text, using deterministic tall/ultrawide fixture artwork. Native popup tracking is canceled only inside the isolated QA harness before its normal NSMenuItem action is dispatched; no system automation permission or live user setting is required. Previous sendAction-only checks could not detect this hit-testing failure.

## Source publication preflight: 3.9.2

Version 3.9.2 build 27 passed 157 Swift tests locally and on a hosted Mac, eight Python repository-tool tests, source/privacy scans, documentation/PNG metadata checks, 10-page PDF/10-slide presentation checks, three demo GIF checks, an optimized ad-hoc build and exact bundle/signature/architecture verification. A private hosted preflight passed 48 native checks covering layout/range/sort interactions, image hit regions, My Prints controls, window/menu routing, appearance persistence and text sizing. The suite used a fresh fictional library and no saved session. A fresh QA launch now creates its own production-root window rather than relying on restored UI state.

The source-evidence badges were regenerated for this exact source. Publication uses a clean one-commit snapshot with GitHub noreply metadata while retaining the original development history privately. Source publication, private vulnerability-reporting enablement and any app binary release remain owner-controlled actions. See the current release-readiness checklist.

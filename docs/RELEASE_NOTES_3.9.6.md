# MakerGlance 3.9.6 · build 34 — local release candidate

This candidate has not been published. Apple Silicon (arm64), macOS 14 or later. **Ad-hoc signed, not Developer ID signed or notarized by Apple.**

- Restore the sidebar's original plain-button appearance and platform keyboard behavior. Remove the build-32 custom focus state, outline and key handler while preserving full-row interaction bounds and accessibility labels.
- Constrain Models cover-image and card hit regions to their visible bounds. The invisible typography bridge no longer participates in pointer hit testing. The native All models / Watched / Paused segmented control and its selection styling remain unchanged.
- Add a native Performance period menu scoped to the Dashboard performance panel. Lifetime remains the default. Day, week, month, three-month, six-month and year views show explicitly labeled net changes between actual profile snapshots.
- Add Last Calendar Month (UTC) for saved Creator Center Models daily activity. Each metric shows its returned-day coverage; missing days/fields are not fabricated zeros. Unsupported follower-count semantics remain unavailable.
- Preserve the separately requested adaptive green Cash Estimate treatment, currency, labels and calculations. Period selection does not change other histories, filters or preferences and does not request account data.

The candidate passes headless unit, optimized-build and source checks. Actual Models filter pointer reliability and the new menu's native layout, keyboard/VoiceOver behavior have not been verified end-to-end on an isolated desktop. Earlier sidebar actions and programmatic filter actions do not establish that result. No GUI fixture testing is permitted on the owner's Mac.

ZIP/DMG contents, checksums and signing status are verified separately during local packaging. The oldest supported macOS target, Intel and a quarantined downloaded launch remain untested. No security-setting change or Gatekeeper bypass is included.

See [period semantics and coverage](PERFORMANCE_PERIODS.md), [downloads and signing](DOWNLOADS.md), and [privacy](PRIVACY.md).

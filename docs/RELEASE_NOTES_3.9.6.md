# MakerGlance 3.9.6 · build 34

Apple Silicon (arm64), macOS 14 or later. **Ad-hoc signed, not Developer ID signed or notarized by Apple.** macOS may warn about or block a quarantined download.

- Restore the sidebar's original plain-button appearance and platform keyboard behavior. Remove the build-32 custom focus state, outline and key handler while preserving full-row interaction bounds and accessibility labels.
- Constrain Models cover-image and card hit regions to their visible bounds. The invisible typography bridge no longer participates in pointer hit testing. The native All models / Watched / Paused segmented control and its selection styling remain unchanged.
- Add a Performance period menu to the Dashboard. Lifetime remains the default. The 1 Day, 1 Week, 1 Month, 3 Months, 6 Months and 1 Year views report net changes between actual profile snapshots, with partial observation coverage labeled.
- Add Last Calendar Month (UTC) for daily likes, downloads, prints, boosts and saves in the saved Creator Center Models report. Each metric shows how many days the service returned. Missing values appear as unavailable, and the follower total is unavailable because the server field’s meaning has yet to be verified.
- Highlight Cash Estimate with a green accent that adapts to light and dark appearances. This is a visual change to the existing amount and currency.

To get the prior month’s daily data, open **Analytics → Creator Center → Models**, choose the first and last dates of the month under **From/Through**, then select **Load report**. The Dashboard uses the saved report. A full-month total requires a returned value for every day of that metric.

Validation covers 255 headless Swift tests, the optimized build and source checks. The ZIP and DMG are checked against the installed build. End-to-end Models filter pointer reliability and the new menu’s layout, keyboard and VoiceOver behavior remain unverified. The oldest supported macOS version and a quarantined downloaded launch also remain untested.

See [period semantics and coverage](PERFORMANCE_PERIODS.md), [downloads and signing](DOWNLOADS.md), and [privacy](PRIVACY.md).

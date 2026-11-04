# MakerGlance 3.9.3 follower links

Build 28 completes follower navigation across the app and macOS notifications.

- Click a follower's name, handle or avatar in the Followers table to open their MakerWorld profile. The existing external-link arrow remains available.
- Single-follower Activity, Dashboard and menu-bar entries retain their profile links.
- Clicking an identified single-follower macOS notification opens that person's profile. Clicks received before the library is loaded wait for the stored identity lookup.
- Older delivered notifications resolve their existing stable activity/follower IDs. Grouped follower notifications open the follower list; mixed update summaries open Activity.
- Profile URLs use one encoded handle segment on MakerWorld. Display names, grouped identities and mismatched stored identities do not select another person's profile.

The bundle, Keychain and local library identities are unchanged. This does not add permissions or change notification delivery preferences.

Validation covers the Swift tests, including notification destination and handle-safety regressions, and an optimized Apple Silicon ad-hoc build. Actual macOS notification-banner clicks and installation/relaunch require desktop access and are not claimed by unit tests or a successful build.

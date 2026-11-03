# Privacy and local storage

## Where data goes

MakerGlance stores profile/model observations, follower baseline/first-observed records, watch rules, local activity, reward observations and preferences on the Mac. It does not run a developer-operated backend, telemetry SDK, remote crash collector or server-push service.

Requests needed to fetch data go to `api.bambulab.com` and `makerworld.com`. Model/avatar thumbnails are accepted only from approved subdomains of `bblmw.com` and `bambulab.com` using HTTPS, without credentials in the image client. Links you choose to open use the system browser. Those external services have their own policies and receive ordinary connection/request information.

## Credentials

The email-code/MFA and manual own-session flows are user initiated. A session is validated against the selected creator before it is activated. No password is retained. The saved session uses macOS Keychain with the legacy service `com.t0nyz0.MakerPulse`, account `bambu-session`, and when-unlocked/device-only accessibility for newly created items.

Tokens are not written to the analytics database, repository, screenshot fixtures or diagnostic arguments. The app's API transport has no shared cookie or credential store. It uses normal system TLS validation and blocks redirects across origins, including port changes or HTTPS downgrades. Locally signed updates may require a macOS Keychain decision; no prompt should be accepted blindly.

## Files on this Mac

The legacy location is retained across the MakerGlance rename:

```text
~/Library/Application Support/MakerPulse/analytics.sqlite
```

SQLite may create adjacent WAL/SHM files. New app directories are created with user-only permissions; database and sidecar permissions are restricted to the user. Observations retain approximately one year. Profile/watch/activity state can contain sensitive personal and financial information beyond the sampled chart history.

The app also maintains a bounded thumbnail cache and a local `connection-status.json` report containing status flags, safe schema field names and error summaries. Explicit UI audit mode can create private screenshots and a report. These are not automatically uploaded, but may expose personal information if you share them.

The database is **not encrypted by MakerGlance**. macOS user access controls and any storage encryption you configure apply. Backups and caches need the same care as the original data. There is no automatic cloud synchronization or in-app secure-erasure guarantee.

## Remove or export data deliberately

Remove the saved session through Settings to delete the app's Keychain item. Quit the app before backing up or removing its support directory; include SQLite sidecars in a consistent backup. Removing a session does not delete saved analytics. Removing the database does not itself remove a saved Keychain item or thumbnail caches. The app does not currently provide a full data-export or account-switch migration flow.

## Demo and documentation

`--demo` uses a separate temporary library, original fictional identities, local artwork and in-memory historical fixtures. It skips Keychain, live polling and notifications. Documentation capture produces only explicitly labeled fictional screenshots. Demo mode does not change the real library or its credentials.

## Private print history

My Prints stores account-scoped cloud task IDs, job/model titles, supplied printer/device identifiers and names, plate context, status, dates, duration estimates and image references in the existing local SQLite library. This can reveal private projects and device information. The database is not app-encrypted; it retains user-only file permissions. A saved cloud record is kept when the service stops returning it. Disconnecting does not erase history.

Private cloud covers may have temporary signed image URLs. They stay local, are excluded from logs/repository/media, and are requested without the app bearer session. Private cover images are cached in memory, with no disk URL cache for that host. Existing public-model images can still use the documented disk cache. No Studio or browser credential store is read, and no new persistent credential grant is created by My Prints.

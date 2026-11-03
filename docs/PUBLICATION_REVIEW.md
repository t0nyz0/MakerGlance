# MakerGlance 3.9.2 publication review

Status: source preparation complete; owner approval to publish is outstanding. Version 3.9.2, build 27.

| Check | Result |
| --- | --- |
| Swift app/core tests | 157 passed locally and on a hosted Mac |
| Python repository-tool tests | 8 passed locally and on a hosted Mac |
| Native desktop regressions | 48 passed on the hosted Mac |
| Optimized app build | Passed locally and on the hosted Mac |
| Bundle verification | arm64, expected version/build, exact inventory and strict ad-hoc signature passed |
| Source/privacy checks | Current files, including untracked additions, passed |
| Public-candidate history | One new root commit, GitHub noreply authorship, no original refs or remote |
| Documentation | Local links and 24 PNG metadata containers passed |
| Presentation | 10 PDF pages, 10 slides and nine described figures passed structural/privacy checks |
| Demo animations | Three changing, seven-second GIFs and their static posters passed |

The native suite checks range and sort mouse delivery, card/compact consistency, tall/wide image hit regions, light/dark appearance, standard/150% text, model filters, My Prints controls, persistence and close/reopen/menu routing. It uses a new fictional library, replayed transport and no Keychain session. The local sandbox could not launch GUI apps; those checks were completed on the private hosted Mac instead.

The original private history remains preserved. Publishing the existing repository by simply changing its visibility would expose old personal metadata. The prepared plan keeps it as a private archive and publishes the reviewed history-free snapshot at the canonical MakerGlance repository name. Enable and verify GitHub private vulnerability reporting during the approved publication action; the security policy also provides a safe contact-request fallback.

No repository has been renamed or made public, and no release binary has been uploaded. Local preview builds remain ad-hoc signed and not notarized. Live-account behavior, Intel, the oldest macOS target and a quarantined downloaded install are separate from these source-publication checks.

See [the exact publication plan](RELEASE_READINESS.md), [source-bound local evidence](LOCAL_VALIDATION.json), [security review](SECURITY_REVIEW.md) and [release changes](RELEASE_NOTES_3.9.2.md).

The final [README review](README_REVIEW.md) checks its feature claims against implementation/test coverage and brings the app overview, feature list, connection requirements and offline demo into the main reading path. This documentation pass changes no app or verification-script source.

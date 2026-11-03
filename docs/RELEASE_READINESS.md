# Public source preparation

The owner has authorized source cleanup and validation, and has reserved final approval for any public publication. The existing GitHub repository remains private.

## Publication boundary

The existing private repository contains historical personal email metadata and machine paths. A normal visibility flip would expose that history. A force-push alone cannot establish that GitHub has removed cached old commits. The publication candidate is therefore a fresh local repository containing the reviewed current files, one new root commit and GitHub noreply authorship. It has no original Git objects, remote, historical branches or tags.

After the owner's final approval, preserve the original repository as the private `t0nyz0/MakerGlance-private-archive` and import only the clean candidate into a fresh repository at `t0nyz0/MakerGlance`. The archive rename and public repository creation are part of that final approval, not this preparation. Do not flip the original private archive to public or force-push the clean snapshot over its history.

This preparation does not rename repositories, create a public repository, change visibility or upload release binaries.

## Source checks

- Version 3.9.2, build 27 preserves the existing bundle, library and Keychain identities.
- The full Swift suite, repository-check tests, source guard, documentation links/metadata, presentation structure, demo GIF checks, optimized build and bundle verification are recorded in the current validation evidence.
- Public fixtures use fictional makers, models and balances. Documentation artwork is original project artwork.
- New untracked files are included in the source/privacy guard. Publication copies only reviewed, nonignored files and rejects symlinks and sensitive artifacts.
- The history-free candidate is rescanned after committing. Original private history, local libraries, credentials, diagnostic output, build folders and backup bundles are excluded.
- The public workflow stays manual and uses a verified immutable checkout pin with read-only repository permissions. A separate private-only preflight passed the same source checks, all 157 Swift tests, eight repository-tool tests, the optimized build and 48 native GUI checks.

## GitHub checks

The private repository had zero existing Actions runs, zero published releases, one main branch and no public forks at review time. No old workflow logs or release assets needed removal. GitHub's private vulnerability-reporting form is a public-repository feature. SECURITY.md documents that form and a safe contact-request fallback; enable and verify the private form as part of the owner-approved publication action.

## App distribution

This approval concerns source publication. Downloadable app releases still need a separate distribution decision. Local builds are Apple Silicon, ad-hoc signed and not notarized. Intel, the oldest supported macOS target and a quarantined downloaded install have not been verified. No financial actions, new account permissions or security-setting changes are part of this preparation.

See [local source validation](LOCAL_VALIDATION.json), [3.9.2 changes](RELEASE_NOTES_3.9.2.md), [security review](SECURITY_REVIEW.md) and [security reporting](../SECURITY.md).

## Current outcome

Source preparation is complete for version 3.9.2, build 27. The final source snapshot is a new local repository with one noreply-authored root commit, a matching file manifest and clean current-tree/history scans. It has no remote configured. The private GitHub validation run passed; final publication approval remains outstanding.

After publication, continue development from the clean repository. Never force-push the archived clone or its original refs into the public repository.

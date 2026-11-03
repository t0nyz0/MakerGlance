# Security policy

MakerGlance is an unofficial local macOS client for undocumented services. Security review and tests reduce risk; they do not guarantee that the app or upstream services are vulnerability-free.

## Reporting a vulnerability

Do not put session tokens, email verification codes, private messages, balances, follower identities, full database exports or unredacted diagnostic images in issues or pull requests.

Use **Security → Advisories → Report a vulnerability** when GitHub's private reporting form is available. That form sends the report privately to the maintainer. If the button is unavailable, open an issue titled **Request a private security contact** with no vulnerability details, account identifiers or attachments, and wait for a private reporting method before sharing technical details. Do not put a vulnerability report in a normal issue.

Maintainers should enable [GitHub private vulnerability reporting](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/configure-for-a-repository) when opening a public repository. GitHub provides this feature for public repositories; a `SECURITY.md` file alone does not enable it.

Provide the affected version, a minimal synthetic reproduction, expected/observed behavior and impact. Keep account identifiers and request headers out of shared logs. Do not test against someone else's account or perform financial actions.

## Scope and maintenance

There is no promised support window or security-response SLA. Review the latest source and [readiness checklist](docs/RELEASE_READINESS.md) before distribution. Undocumented API/authentication changes may require a reconnect or client update.

## Credential boundary

- Sessions are validated against the chosen profile before activation and stored in macOS Keychain. The app does not store passwords or create credentials automatically.
- API traffic uses HTTPS and system TLS validation. Redirects must preserve scheme, host and effective port; credentials are not forwarded to another origin.
- Image requests carry no Bambu session credentials and accept approved HTTPS CDN URLs. Their redirects are restricted to the same origin.
- Private account operations are read-only except user-requested authentication. The app does not redeem points, withdraw, transfer, publish models, mark server messages read or change remote notification preferences.
- Locally ad-hoc signed builds can prompt for Keychain access after updates. Do not bypass unexpected prompts or change system security settings to make a build run.

SQLite history is not encrypted by this app. See [privacy](docs/PRIVACY.md) for storage, permissions and diagnostic handling.

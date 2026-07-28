# Security Policy

## Supported version

Hypha is under active development. Security fixes target the current `main` branch; no stable release series is presently guaranteed.

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability or include sensitive evidence in public comments, logs, screenshots, or pull requests.

Use GitHub's private vulnerability-reporting flow:

https://github.com/ZenithResearch/Hypha/security/advisories/new

Public release is blocked unless that endpoint is enabled and verified during the visibility transition. If enablement fails, repository visibility must be reverted to private before release announcement or public development continues.

Include:

- affected commit or release;
- reproduction steps using disposable accounts and redacted identifiers;
- expected and observed behavior;
- impact and preconditions;
- whether passwords, access tokens, room keys, recovery material, private messages, or account identities may have been exposed.

Do not send live secrets. Replace them with `[REDACTED]` and rotate any credential that may have been disclosed.

## Security boundaries

Hypha fails closed for invalid identity signatures, unencrypted room sends, credential/store identity mismatches, unsupported registration flows, and homeserver-origin drift. Matrix networking and E2EE remain owned by the pinned Matrix Rust SDK. See `docs/security-model.md` for the current authority and non-claim boundaries.

A report acknowledgment or remediation timeline will be recorded in the private advisory. Disclosure is coordinated only after a fix and affected-user guidance are ready.

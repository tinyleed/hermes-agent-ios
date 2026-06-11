# Security Policy

Hermes Agent iOS deals with operator control surfaces for agentic workflows. Please treat security and privacy issues seriously.

## Reporting vulnerabilities

Please do not open a public issue for an active vulnerability, leaked secret, or exploitable bypass.

Report privately to the repository maintainer through GitHub contact information. Include:

- affected commit/version;
- reproduction steps;
- expected vs actual behavior;
- potential impact;
- whether any secret or private data was exposed.

## Sensitive areas

Security-sensitive changes include:

- approval, sudo, secret, and clarify request handling;
- gateway tokens and WebSocket auth;
- deep links and bootstrap URLs;
- APNs/local notification payloads;
- transcript, timeline, export, and log rendering;
- physical-device install/signing helpers.

## Secret handling policy

- Real secrets must not be committed.
- Tests must use synthetic values only.
- Sudo/secret flows should store and display redacted state, not raw values.
- Scripts should report `<redacted>`, `configured`, or `missing` instead of printing secret values.

## Supported versions

This project is early-stage. Security fixes target the default branch unless a release branch is explicitly maintained.

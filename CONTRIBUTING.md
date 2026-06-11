# Contributing

Thanks for your interest in Hermes Agent iOS.

## Development setup

Requirements:

- macOS with Xcode.
- Python 3.11+.
- Swift 6 toolchain.
- XcodeGen.

Run the full verification gate:

```zsh
./scripts/test_all.sh
```

## Workflow

- Open focused PRs.
- Keep changes small and testable.
- Add or update tests for behavior changes.
- Use deterministic fixtures for gateway/security flows.
- Do not mix broad refactors with feature work.

## Security-sensitive areas

Call out changes touching:

- gateway auth or WebSocket tokens;
- approval/sudo/secret requests;
- deep links and bootstrap artifacts;
- APNs/local notifications;
- transcript/log rendering;
- physical-device signing or install scripts.

## No secrets

Never commit real tokens, API keys, passwords, bootstrap links, private keys, or private device identifiers. Use placeholders and synthetic fixtures.

## Pull request checklist

Before opening a PR:

```zsh
git diff --check
./scripts/test_all.sh
```

In the PR, include:

- summary;
- files/areas changed;
- tests run;
- security/privacy impact, if any.

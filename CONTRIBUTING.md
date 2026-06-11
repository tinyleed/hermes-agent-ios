# Contributing

Thanks for your interest in Hermes Agent iOS.

This project uses a small-slice workflow: pick a focused issue, make one branch, prove the change with the deterministic gate, and keep security-sensitive behavior explicit.

## Development setup

### Requirements

- macOS with Xcode installed.
- Python 3.11+ available as `python3`.
- Swift 6 toolchain, normally supplied by current Xcode.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) available as `xcodegen`.
- An available iOS Simulator for app/UI build checks.

Check your local toolchain:

```zsh
sw_vers
xcodebuild -version
swift --version
python3 --version
xcodegen --version
xcrun simctl list devices available | head -40
```

If `xcodegen` is missing and you use Homebrew:

```zsh
brew install xcodegen
```

### Clone and verify

```zsh
git clone https://github.com/tinyleed/hermes-agent-ios.git
cd hermes-agent-ios
./scripts/test_all.sh
```

The full gate runs Python unit tests, fixture checks, mock gateway smoke tests, Swift contract tests, XcodeGen, and an iOS simulator build. It is the preferred proof before opening a non-trivial PR.

Useful narrower checks while developing:

```zsh
git diff --check
python3 -m unittest discover -s tests -v
python3 scripts/smoke_mock_gateway.py
python3 scripts/smoke_blocking_fixture_gateway_ws.py
swift run HermesAgentCoreContractTest
xcodegen generate
```

## Where to start

Good first contributions are usually documentation, fixture, or test improvements. Start with issues labeled [`good first issue`](https://github.com/tinyleed/hermes-agent-ios/labels/good%20first%20issue) or `P3`.

Safe first areas:

- contributor/setup documentation;
- mock gateway fixtures;
- README/docs clarity;
- small scaffold tests around existing behavior.

Avoid these as a first PR unless a maintainer explicitly scopes the issue:

- gateway auth or WebSocket token behavior;
- approval/sudo/secret redaction logic;
- physical-device signing/bootstrap flows;
- APNs/local notification behavior;
- broad SwiftUI lifecycle rewrites.

## Workflow

- Create or pick an issue first for non-trivial work.
- Open a focused branch from `main`.
- Keep changes small and testable.
- Add or update tests for behavior changes.
- Use deterministic fixtures for gateway/security flows.
- Do not mix broad refactors with feature work.
- Fill out the PR template with exact commands run.

For the maintainer/agent workflow, see [`docs/maintainer-workflow.md`](docs/maintainer-workflow.md).

## Security-sensitive areas

Call out changes touching:

- gateway auth or WebSocket tokens;
- approval/sudo/secret requests;
- deep links and bootstrap artifacts;
- APNs/local notifications;
- transcript/log rendering;
- physical-device signing or install scripts.

## No secrets

Never commit real tokens, API keys, passwords, bootstrap links, private keys, private hostnames, private screenshots, or private device identifiers. Use placeholders and synthetic fixtures.

Synthetic fixture values are allowed only when they are clearly fake and already part of the test/fixture path.

## Pull request checklist

Before opening a PR:

```zsh
git diff --check
./scripts/test_all.sh
```

In the PR, include:

- summary;
- related issue;
- files/areas changed;
- tests run;
- security/privacy impact, if any;
- screenshots/logs for UI-facing changes.

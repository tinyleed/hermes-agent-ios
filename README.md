# Hermes Agent iOS

[![CI](https://github.com/tinyleed/hermes-agent-ios/actions/workflows/ci.yml/badge.svg)](https://github.com/tinyleed/hermes-agent-ios/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Swift 6](https://img.shields.io/badge/Swift-6-orange.svg)](Package.swift)
[![iOS 17+](https://img.shields.io/badge/iOS-17%2B-lightgrey.svg)](project.yml)

**A native iPhone operator cockpit for Hermes Agent — built for mobile chat, human approvals, secret-redacted gateway control, and safe supervision of agentic workflows.**

Hermes Agent iOS keeps execution in [Hermes Agent](https://hermes-agent.nousresearch.com/) and turns the phone into the control surface: see what an agent is doing, approve risky steps, answer blocking prompts, and keep secrets out of transcripts and logs.

| Status | Focus | Safety posture |
| --- | --- | --- |
| Early-stage, simulator-first | Operator UX for mobile agent supervision | Deterministic fixtures, explicit approvals, redacted secret/sudo flows |

## Why it exists

Autonomous coding and automation agents need a good operator surface, not just a terminal. Hermes Agent iOS explores how an iPhone can provide:

- fast mobile visibility into agent runs;
- explicit approval flows for risky actions;
- secret/sudo prompts that avoid leaking values into transcripts or logs;
- native iOS affordances such as Live Activities, App Intents, sharing, and notifications;
- deterministic fixtures for safe development and review.

## Current capabilities

- SwiftUI command/chat cockpit for Hermes-backed workflows.
- Swift `HermesAgentCore` package with gateway DTOs, request builders, parsers, and reducer contracts.
- Mock gateway for local development.
- WebSocket/JSON-RPC runtime seams for session creation, prompt submission, event streaming, and blocking request handling.
- Approval, sudo, and secret blocking-card fixtures with redacted response state.
- Local simulator and contract-test gates.
- Bootstrap/helper scripts for local, simulator, and physical-device development.

## Safety model

Hermes Agent iOS treats the mobile app as an operator interface, not a place to run long-lived agents. The app should display decisions, collect operator intent, and send bounded responses back to Hermes.

Safety rules in this repo:

- Never send private user data, raw Hermes Agent chat transcripts, secrets, or screenshots to synthetic/eval lanes.
- Do not commit real tokens, passwords, API keys, bootstrap links, or private keys.
- Fixtures may use synthetic placeholder strings only.
- Sudo/secret request tests must assert redaction instead of storing raw values.
- Scripts should print configured/missing/redacted state, never secret values.
- Public docs should use placeholders for hostnames, tokens, and device identifiers.

## Repository layout

- `App/` — SwiftUI iOS app shell.
- `Sources/HermesAgentCore/` — Swift DTOs, clients, gateway runtime seams, and shared contracts.
- `Sources/HermesAgentCoreContractTest/` — executable Swift contract checks.
- `mock_gateway/` — Python local mock gateway and WebSocket fixtures.
- `docs/` — API and integration notes.
- `schemas/` — JSON schemas for gateway objects.
- `scripts/` — local test, simulator, device, and bootstrap helpers.
- `tests/` — Python scaffold/mock gateway contract tests.
- `project.yml` — XcodeGen source of truth for the Xcode project.

## Requirements

- macOS with Xcode installed.
- Python 3.11+.
- Swift 6 toolchain.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) for regenerating the Xcode project.

## Build and test

Run the full local gate:

```zsh
./scripts/test_all.sh
```

This runs Python unit tests, fixture verification, mock gateway smoke tests, Swift contract checks, XcodeGen, and an iOS simulator build.

Useful narrower checks:

```zsh
python3 -m unittest discover -s tests -v
python3 scripts/smoke_mock_gateway.py
python3 scripts/smoke_blocking_fixture_gateway_ws.py
swift run HermesAgentCoreContractTest
```

## Local mock gateway

Start the basic mock gateway:

```zsh
./scripts/run_mock_gateway.sh
```

Start the blocking WebSocket fixture gateway:

```zsh
python3 scripts/run_blocking_fixture_gateway_ws.py --port 18791
```

Then run the relevant smoke test:

```zsh
python3 scripts/smoke_blocking_fixture_gateway_ws.py
```

Expected result:

```text
OK mock blocking fixture WS: approval -> sudo -> secret -> redacted final output
```

For the full simulator/UI fixture path, see [`docs/blocking-card-fixture-flow.md`](docs/blocking-card-fixture-flow.md).

## Simulator

Regenerate/build first:

```zsh
./scripts/test_all.sh
```

Then launch the simulator helper:

```zsh
./scripts/launch_simulator.sh
```

## Project status

This project is a clean open-source release of an actively developed iOS companion for Hermes Agent. It is not yet a production App Store app. See [`ROADMAP.md`](ROADMAP.md) for current priorities.

## Contributing

Contributions are welcome. Start with [`CONTRIBUTING.md`](CONTRIBUTING.md) and [`docs/maintainer-workflow.md`](docs/maintainer-workflow.md), and treat changes around gateway auth, approval handling, deep links, bootstrap artifacts, and secret display as security-sensitive.

## Security

Please report vulnerabilities using the process in [`SECURITY.md`](SECURITY.md). Do not open public issues for active vulnerabilities or accidentally discovered secrets.

## License

MIT. See [`LICENSE`](LICENSE).

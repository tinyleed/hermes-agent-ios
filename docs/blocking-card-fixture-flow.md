# Blocking-card fixture flow

Hermes Agent iOS has a synthetic approval/sudo/secret fixture path so contributors and agents can verify blocking-card behavior without real gateway credentials, private hostnames, or physical-device bootstrap links.

The fixture proves three things:

1. the gateway emits `approval.request`, `sudo.request`, and `secret.request` events in order;
2. the app can render and resolve those requests as inline cards;
3. sudo/secret values are acknowledged as redacted state, not displayed in transcripts, status text, or logs.

## Safety rules

- Use only the synthetic values already in the fixture scripts/tests.
- Do not paste real passwords, tokens, bootstrap URLs, private hostnames, or device IDs into docs, tests, screenshots, or PR logs.
- Expected success text may mention `redacted`; it must not show the raw fixture value.
- Stop before swapping this flow to a live gateway or physical-device bootstrap path.

## Fast WebSocket fixture smoke

Run this first when changing gateway event ordering, request payloads, or redaction behavior:

```zsh
python3 scripts/smoke_blocking_fixture_gateway_ws.py
```

Expected output:

```text
OK mock blocking fixture WS: approval -> sudo -> secret -> redacted final output
```

What this checks:

- starts an in-process local mock gateway on `127.0.0.1` with an ephemeral port;
- fetches the synthetic dashboard token;
- opens a WebSocket session;
- submits a synthetic prompt;
- responds to approval, sudo, and secret requests;
- asserts the final message is the fixture success text;
- scans the transcript/summary for secret-like output.

## Long-running local fixture gateway

Use this when a developer or agent needs a reachable fixture gateway process:

```zsh
python3 scripts/run_blocking_fixture_gateway_ws.py --host 127.0.0.1 --port 18791
```

The launcher prints:

```text
Hermes Agent mock blocking fixture gateway listening on http://127.0.0.1:18791
```

The default token is synthetic and exposed by the mock dashboard page. Treat it as fixture-only; do not reuse this pattern with live credentials in public logs.

## Simulator UI fixture path

The UI tests include a DEBUG-only fixture mode that renders approval/sudo/secret cards without requiring a live gateway:

```text
HERMES_AGENT_UI_TEST_BLOCKING_FIXTURES=1
HERMES_AGENT_UI_TEST_RESET_CHAT=1
```

The relevant UI tests are in `UITests/HermesAgentPhysicalLiveChatUITests.swift`:

- `testSafeBlockingCardFixturesRenderApprovalSudoAndSecretCards`
- `testSafeBlockingCardFixturesCanBeResolvedWithoutSecretRendering`

Those tests expect:

- `Approval required` and `Approve safe fixture command?` render;
- `Sudo password required` renders;
- `Secret required` renders with the variable label `HERMES_AGENT_IOS_FAKE_FIXTURE_SECRET`;
- tapping `Approve`, `Submit Password`, and `Submit Secret` records `Value redacted.` status;
- no `password=`, `token=`, or raw `fixture-redacted-value` text appears.

Run the full gate before merging changes:

```zsh
./scripts/test_all.sh
```

## Optional manual simulator command

If you need to run only the fixture UI tests locally, first regenerate the project if needed:

```zsh
xcodegen generate
```

Then run the selected tests against an available iOS simulator:

```zsh
HERMES_AGENT_UI_TEST_BLOCKING_FIXTURES=1 \
HERMES_AGENT_UI_TEST_RESET_CHAT=1 \
xcodebuild test \
  -project "Hermes Agent iOS.xcodeproj" \
  -scheme "Hermes Agent iOS" \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:Hermes_Agent_iOS_UI_Tests/HermesAgentPhysicalLiveChatUITests/testSafeBlockingCardFixturesRenderApprovalSudoAndSecretCards \
  -only-testing:Hermes_Agent_iOS_UI_Tests/HermesAgentPhysicalLiveChatUITests/testSafeBlockingCardFixturesCanBeResolvedWithoutSecretRendering
```

If your local simulator name differs, list devices with:

```zsh
xcrun simctl list devices available
```

## PR checklist for this flow

For changes touching blocking cards, include this in the PR:

```md
Verification:
- `python3 scripts/smoke_blocking_fixture_gateway_ws.py`
- `./scripts/test_all.sh`

Safety:
- no live gateway token, private hostname, bootstrap URL, password, or private device ID was used;
- approval/sudo/secret responses still render only redacted state.
```

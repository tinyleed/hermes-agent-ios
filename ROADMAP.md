# Roadmap

Hermes Agent iOS is early-stage. The project prioritizes safe operator control, deterministic testing, and mobile-native surfaces for Hermes Agent.

## Now

- Stabilize the Hermes gateway-backed chat runtime.
- Prove approval/sudo/secret request-response loops against safe mock/live gateway fixtures.
- Keep simulator-first verification green.
- Preserve strict secret redaction in transcripts, status text, logs, and bootstrap helpers.

## Next

- Physical iPhone proof for gateway-backed blocking requests.
- APNs/local notification path for approval prompts.
- More complete remote session history and resume UX.
- Contributor-friendly setup docs and first public issues.

## Later

- Hosted/public gateway auth planning.
- OAuth or ticket-mode connection model for hosted deployments.
- Broader iOS-native workflows: Shortcuts, share extension polish, Live Activity refinements.
- Security review hardening for approval, deep-link, and bootstrap paths.

## Non-goals for now

- Running long-lived agents on-device.
- Sending private user data, raw session transcripts, or secrets to synthetic/eval lanes.
- Hosted multi-user gateway support before the local/private gateway model is stable.

# Roadmap

Hermes Agent iOS is early-stage. The project prioritizes safe operator control, deterministic testing, and mobile-native surfaces for Hermes Agent.

## Now

- Stabilize the Hermes gateway-backed chat runtime.
- Layer APNs/local notification delivery on top of the proven simulator and physical-device approval/sudo/secret blocking loop.
- Keep simulator-first verification green.
- Preserve strict secret redaction in transcripts, status text, logs, and bootstrap helpers.

## Next

- Contributor-safe repeatable physical-device harness for gateway-backed blocking requests.
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

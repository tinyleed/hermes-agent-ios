# Roadmap

Status: **shelved**.

Hermes Agent iOS explored a native iPhone operator cockpit for Hermes Agent: mobile chat, human approvals, secret-redacted gateway control, APNs/local notification paths, and safe supervision of agentic workflows. Active development is now paused/shelved; this roadmap is retained as historical context.

## Historical focus before shelving

- Stabilize the Hermes gateway-backed chat runtime.
- Layer APNs/local notification delivery on top of the proven simulator and physical-device approval/sudo/secret blocking loop.
- Keep simulator-first verification green.
- Preserve strict secret redaction in transcripts, status text, logs, and bootstrap helpers.

## No active roadmap

There are no active implementation priorities while the project is shelved.

Do not treat the existing GitHub issue backlog as a live queue unless the maintainer explicitly reopens the project and defines a differentiated scope.

## Historical next candidates

These were useful directions before shelving, but are not current work:

- Contributor-safe repeatable physical-device harness for gateway-backed blocking requests.
- APNs/local notification path for approval prompts.
- More complete remote session history and resume UX.
- Contributor-friendly setup docs and first public issues.
- Hosted/public gateway auth planning.
- OAuth or ticket-mode connection model for hosted deployments.
- Broader iOS-native workflows: Shortcuts, share extension polish, Live Activity refinements.
- Security review hardening for approval, deep-link, and bootstrap paths.

## Non-goals

- Running long-lived agents on-device.
- Sending private user data, raw session transcripts, or secrets to synthetic/eval lanes.
- Hosted multi-user gateway support before the local/private gateway model is stable.

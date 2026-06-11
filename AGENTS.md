# Hermes Agent iOS Agent Workflow

This repository is developed in small, verified slices. Prefer contract-first changes and deterministic mock gateway tests before UI or device work.

## Default loop

1. Inspect minimal state: `git status`, `git diff --stat`, `STATUS.md`, and `ROADMAP.md`.
2. Pick exactly one small slice.
3. Prefer direct file/patch work for mechanical edits.
4. Use a short-lived coding worker only when the slice is non-trivial.
5. Use read-only review for risky diffs: SwiftUI lifecycle/state, session/auth/token handling, networking, deep links, bootstrap artifacts, or multi-file behavior.
6. Verify with real commands before reporting success.
7. Stop after the slice is green or clearly blocked.

## Security rules

- Do not commit real secrets, tokens, bootstrap links, private keys, or private device identifiers.
- Use synthetic fixture values only.
- never use `OPENAI_SHARED_EVALS_API_KEY` for private data, live Hermes Agent chats, secrets, screenshots, raw session transcripts, or maintainer-local context.
- Do not print secret values from scripts; print configured/missing/redacted state.
- Treat approval, sudo, secret, gateway auth, APNs, and deep-link handling as security-sensitive.

## iOS-specific order

1. Contract/schema/fixture first.
2. Parser/runtime tests second.
3. Fake gateway smoke third.
4. SwiftUI integration fourth.
5. Simulator build/smoke fifth.
6. Physical device proof only for device-only behavior: notifications, keychain, LAN/HTTPS bootstrap, APNs, Live Activities, or signing.

## Verification commands

Preferred full gate:

```zsh
./scripts/test_all.sh
```

Use narrower commands for early checks, then run the full gate before commit/PR.

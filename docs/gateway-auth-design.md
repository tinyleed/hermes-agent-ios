# Hermes Gateway Auth — Design Note

**Status:** Draft · Issue #6  
**Date:** 2026-06-11  
**Scope:** Design only. No implementation, no credential changes, no runtime behavior changes.

---

## Context

The iOS app currently authenticates to the Hermes gateway by appending a static bearer token as a URL query parameter on the WebSocket upgrade request:

```
wss://<host>/api/ws?token=<sessionToken>
```

This works for a single operator on a trusted local network but has known weaknesses and will not extend cleanly to physical-device LAN bootstrap, APNs-driven reconnect, or any future hosted/shared gateway. This note compares three auth paths and defines the security constraints and open questions that must be resolved before any path is implemented.

---

## Current state

**Code location:** `Sources/HermesAgentCore/HermesGatewayRemoteConnection.swift`

- `HermesGatewayRemoteConnection` holds `baseURL: URL` and `sessionToken: String`.
- The static helper `webSocketURL(baseURL:sessionToken:)` appends `?token=<percent-encoded token>` to form the WebSocket URL.
- No token rotation, expiry, or revocation is modelled.
- Token provisioning is manual (user enters it in the app).

**Key weakness:** Query-string tokens appear in server access logs, HTTP proxy logs, Xcode debugger URL dumps, and crash reports. They also survive URL copy/paste, making accidental disclosure likely.

---

## Option comparison

| | **A — Local private gateway (current)** | **B — Ticket-mode bootstrap** | **C — Hosted / OAuth-style** |
|---|---|---|---|
| **Description** | Static token in WebSocket query string. Operator manually copies token into app. | Server generates a short-lived, single-use ticket. App deep-links or scans QR to bootstrap, then exchanges ticket for a durable per-device token stored in Keychain. | Full OAuth 2.0 / PKCE flow against an identity provider. Refresh token rotation. Multi-user. |
| **Auth carrier** | URL query string | Initial: URL query string or deep link. Post-exchange: `Authorization: Bearer` header. | `Authorization: Bearer` header; refresh via HTTPS. |
| **Token lifetime** | Indefinite (manual revocation only) | Ticket: seconds to minutes. Durable device token: configurable, revocable server-side. | Access token: minutes. Refresh token: days, rotated on use. |
| **Secret surface** | Token in URL → server logs, proxy logs, debugger, crash reports | Ticket in URL one time only; durable token never in URL after exchange | No long-lived secret in URL at any point |
| **Operator friction** | High: manual copy-paste, no rotation | Low: scan QR / tap deep link once | Low after IdP setup; high to operate IdP |
| **Infrastructure required** | None beyond existing gateway | Ticket endpoint on gateway (`POST /auth/ticket/exchange`) | Identity provider, HTTPS everywhere, token introspection endpoint |
| **Multi-user / multi-device** | No | Possible with device-scoped tokens | Yes |
| **Readiness for physical device** | Works on LAN; risky on untrusted networks | Safer on LAN; works over HTTPS for remote | Requires hosted infra |
| **Redaction / approval boundary impact** | None (auth is pre-connection) | None — approval/sudo/secret flows unchanged | None — auth layer is orthogonal to operator approval semantics |
| **When to adopt** | Already in use; harden header usage now | When physical-device or multi-device bootstrap is needed | When a hosted, multi-user gateway exists |

---

## Near-term improvement to Option A

Before moving to ticket mode, one low-cost hardening step is worth doing separately:

**Move token from URL query string to `Authorization` header.**

`URLSession.webSocketTask(with:)` has a `URLRequest`-accepting overload. Changing `HermesGatewayRemoteConnection.webSocketURL` to instead produce a `URLRequest` with an `Authorization: Bearer <redacted>` header eliminates the primary log-leakage risk without changing the auth model.

This is a small, backward-compatible change to `HermesGatewayRemoteConnection` and `HermesGatewayRPCClient`. It should be tracked as a separate implementation issue.

---

## Threat model

The following threats apply across all paths. Option-specific notes are marked.

| Threat | Applies to | Mitigation |
|---|---|---|
| Token captured from URL in server/proxy logs | A (high risk), B during ticket phase (low risk) | Move to `Authorization` header (A near-term); ticket is single-use (B) |
| Token replay from intercepted WebSocket URL | A, B during ticket phase | TLS everywhere; short ticket TTL (B) |
| Token persisted in app memory, logs, or crash reports | A, B, C | Never log token; store only in Keychain; redact in all UI and export paths |
| Rogue deep link bootstrap to malicious gateway | B, C | Validate deep-link host against pinned or user-confirmed domain; show confirmation UI before persisting |
| SSRF via user-supplied `baseURL` | A, B | Scheme allowlist (`http`/`https`) already enforced; add host validation for non-LAN origins when remote gateway is introduced |
| Physical device theft with persisted Keychain token | A, B, C | Token should require device unlock (Keychain `kSecAttrAccessibleWhenUnlocked`); server-side revocation endpoint needed |
| Token exfiltration via transcript / log rendering | A, B, C | `HermesRemoteSessionSummary.displayIdentity` already redacts token-bearing titles; extend to all log and export paths |
| Approval/sudo/secret bypass via malicious gateway | A, B, C | Auth is pre-connection; approval semantics are enforced by the app UI and gateway independently; connecting to a wrong gateway does not bypass app-side approval logic, but does give the attacker control of what requests the app sees — operator must verify gateway identity |
| Man-in-the-middle on LAN (local gateway) | A | TLS with certificate pinning or user-presented fingerprint for non-localhost connections |

---

## Non-goals for this design note

- No implementation of any auth path.
- No changes to current `sessionToken` query-string behavior.
- No OAuth provider selection or integration contract.
- No handling of multi-user or multi-operator scenarios.
- No changes to approval, sudo, secret, or clarify request-response semantics.
- No hosted gateway deployment or infrastructure planning.

---

## Security constraints (any future implementation must satisfy)

1. Token must never appear in any log line, transcript render, export, or crash report.
2. Token must be stored in Keychain with at minimum `kSecAttrAccessibleWhenUnlocked`.
3. Deep-link bootstrap must display the target hostname and require an explicit operator confirmation tap before persisting any credential.
4. Ticket TTL must be enforced server-side; a replayed ticket must be rejected.
5. Durable device token must be revocable server-side without requiring app reinstall.
6. Any gateway auth change must leave `approval`, `sudo`, `secret`, and `clarify` blocking-request semantics and redaction behavior entirely unchanged.
7. Tests must use synthetic token values only; real tokens must never appear in fixtures, test assertions, or CI logs.

---

## Open questions

1. **Header vs. query string (near-term):** Should the `Authorization: Bearer` header change be bundled with the first physical-device bootstrap slice, or shipped earlier as a standalone hardening step?

2. **Ticket delivery:** For ticket-mode bootstrap, is a deep link (`hermes://connect?ticket=<value>`) or a QR code the right delivery surface for the iOS operator? QR avoids Universal Link infrastructure; deep link integrates with iOS App Clips and Shortcuts.

3. **Ticket endpoint ownership:** Does the ticket endpoint live on the existing Hermes gateway process, or as a lightweight sidecar? This affects whether mock_gateway needs to gain a `/auth/ticket/exchange` route before Option B can be tested.

4. **Certificate validation on LAN:** The current `http://` scheme is allowed for local development. Should LAN HTTPS with a self-signed cert (trust-on-first-use fingerprint) be the physical-device baseline, or should we require a real certificate from the outset?

5. **Token rotation:** If a durable device token is issued post-ticket-exchange, what is its TTL and rotation strategy? Silent rotation (send new token in response header) or explicit re-auth?

6. **Revocation UX:** If a token is revoked server-side, what should the iOS app show? Blocking error screen, silent re-auth prompt, or APNs-delivered logout push?

7. **Multi-device:** Is a single operator expected to run the app on multiple iOS devices simultaneously against the same gateway? If yes, ticket-mode must issue per-device tokens rather than a single shared token.

---

## Recommended sequencing

```
Now:   Harden Option A — move token to Authorization header (separate issue)
Next:  Design and prototype Option B ticket-mode bootstrap for physical-device LAN use
Later: Re-evaluate Option C only when a hosted gateway is being planned
```

This sequencing matches the current ROADMAP priorities: stabilize the local gateway model before physical-device work, and defer hosted/OAuth planning until the local model is proven.

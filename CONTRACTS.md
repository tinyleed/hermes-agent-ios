# Hermes Agent iOS Contracts

This file records compact contracts that workers can use without loading long chat history.

## Development principle

Every live Hermes/iOS feature should start from a small contract or fixture before SwiftUI integration.

## Hermes Desktop remote gateway WebSocket

The current Mac mini/desktop-compatible token-mode connection builds a WebSocket URL from a base dashboard/gateway URL and a token:

- `https://host:port` -> `wss://host:port/api/ws?token=<redacted>`
- `http://host:port` -> `ws://host:port/api/ws?token=<redacted>`

Tokens must never be printed in logs, scripts, test output, screenshots, or committed artifacts.

## JSON-RPC methods currently expected by iOS

### `session.create`

Creates or resumes a live Hermes gateway chat runtime session. Existing runtime code owns this path.

### `prompt.submit`

Submits a prompt to the active Hermes runtime session. Existing runtime code owns this path.

### `session.list`

Purpose: list recent stored Hermes sessions for Chat History.

Request shape:

```json
{
  "method": "session.list",
  "params": { "limit": 10 }
}
```

Response shape accepted by iOS:

```json
{
  "sessions": [
    {
      "id": "stored-session-id",
      "title": "Optional title",
      "message_count": 37,
      "updated_at": 1780000000
    }
  ]
}
```

Accepted aliases:

- id: `id`, `session_id`, `stored_session_id`
- timestamp: `updated_at`, `last_active`, `started_at`, `created_at`
- message count: `message_count` or count of `messages`

### `session.resume`

Purpose: resume a stored Hermes session and hydrate the iOS chat transcript.

Request shape:

```json
{
  "method": "session.resume",
  "params": { "session_id": "stored-session-id" }
}
```

Response shape accepted by iOS:

```json
{
  "session_id": "runtime-session-id",
  "stored_session_id": "stored-session-id",
  "messages": [
    { "id": "message-id", "role": "user", "content": "hello" },
    { "id": "message-id", "role": "assistant", "content": "hi" }
  ]
}
```

Accepted aliases:

- stored id: `stored_session_id`, `session_key`, `resumed`
- message content: `content`, `body`, `text`

Structured content should degrade to compact display placeholders such as `[image]`, `[audio]`, or `[structured content]`.

## Event stream expectation

SSE/WebSocket events should render directly as timeline/chat state where possible. The model should only be used for interpretation, triage, or expensive action.

## Verification strategy

- Contract/parser behavior before UI.
- Mock gateway/fake fixtures before live gateway.
- Full `./scripts/test_all.sh` before commit/PR.

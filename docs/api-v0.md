# Hermes Agent iOS API v0

Fake-first contract for the v0.1 command + approval loop.

## POST /v0/messages

Creates a thread, assistant approval-card message, run, and approval request.

### Request

```json
{
  "text": "run status check"
}
```

### Response: 201

```json
{
  "thread": { "id": "thread_...", "lane": "hermes-agent" },
  "message": { "role": "assistant", "kind": "approval_card" },
  "run": { "status": "waiting_for_approval" },
  "approval": { "status": "pending", "riskTier": 1 }
}
```

## GET /v0/approvals

Lists pending approvals.

### Response: 200

```json
{
  "approvals": []
}
```

## GET /v0/threads/{threadId}/messages

Returns thread metadata plus ordered messages for the thread.

### Response: 200

```json
{
  "thread": { "id": "thread_...", "lane": "hermes-agent" },
  "messages": [
    { "kind": "approval_card" },
    { "kind": "command_result" }
  ]
}
```

### Response: 404

```json
{
  "error": "thread_not_found"
}
```

## POST /v0/approvals/{approvalId}/approve

Approves a pending approval and completes the run.

### Response: 200

```json
{
  "approval": { "status": "approved" },
  "run": { "status": "done" },
  "result": { "kind": "command_result" }
}
```

## POST /v0/approvals/{approvalId}/reject

Rejects a pending approval and cancels the run.

### Response: 200

```json
{
  "approval": { "status": "rejected" },
  "run": { "status": "cancelled" },
  "result": { "kind": "command_result" }
}
```

## Safety

The mock gateway is local-only and has no real Hermes side effects. It exists to let SwiftUI consume stable field names before real Gateway integration.

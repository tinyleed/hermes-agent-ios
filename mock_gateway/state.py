from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any
from uuid import uuid4


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def new_id(prefix: str) -> str:
    return f"{prefix}_{uuid4().hex[:12]}"


@dataclass
class GatewayState:
    threads: dict[str, dict[str, Any]] = field(default_factory=dict)
    messages: dict[str, dict[str, Any]] = field(default_factory=dict)
    runs: dict[str, dict[str, Any]] = field(default_factory=dict)
    approvals: dict[str, dict[str, Any]] = field(default_factory=dict)
    notification_tokens: dict[str, dict[str, Any]] = field(default_factory=dict)

    def register_notification_token(self, payload: dict[str, Any]) -> dict[str, Any]:
        timestamp = now_iso()
        device_id = str(payload.get("deviceId", "ios-device")).strip() or "ios-device"
        record = {
            "id": new_id("notification_token"),
            "deviceId": device_id,
            "platform": str(payload.get("platform", "ios")),
            "tokenState": "redacted_present" if payload.get("tokenRedacted") else "missing",
            "environment": str(payload.get("environment", "development")),
            "enrolledDeveloperProgram": bool(payload.get("enrolledDeveloperProgram", False)),
            "apnsAvailable": bool(payload.get("enrolledDeveloperProgram", False)),
            "createdAt": timestamp,
        }
        self.notification_tokens[device_id] = record
        return {"notificationToken": record, "apnsGate": "developer_program_required" if not record["apnsAvailable"] else "ready"}

    def create_command(self, text: str) -> dict[str, Any]:
        timestamp = now_iso()
        thread_id = new_id("thread")
        run_id = new_id("run")
        approval_id = new_id("approval")
        message_id = new_id("msg")

        thread = {
            "id": thread_id,
            "title": text[:48] or "Hermes Agent command",
            "lane": "hermes-agent",
            "createdAt": timestamp,
            "updatedAt": timestamp,
            "projectId": None,
        }
        run = {
            "id": run_id,
            "threadId": thread_id,
            "title": "Mock Hermes command run",
            "lane": "hermes-agent",
            "status": "waiting_for_approval",
            "currentStep": "Awaiting approval",
            "risk": "low",
            "startedAt": timestamp,
            "updatedAt": timestamp,
            "artifactIds": [],
            "approvalIds": [approval_id],
        }
        approval = {
            "id": approval_id,
            "runId": run_id,
            "title": "Approve mock command",
            "description": f"Allow Hermes Agent mock gateway to complete command: {text}",
            "riskTier": 1,
            "scope": ["mock_gateway_state"],
            "reason": "Exercise the v0.1 command + approval loop",
            "rollback": "No real side effects; local mock state only",
            "actions": ["approve_once", "reject", "explain"],
            "status": "pending",
            "createdAt": timestamp,
        }
        message = {
            "id": message_id,
            "threadId": thread_id,
            "role": "assistant",
            "kind": "approval_card",
            "body": "Approval required before completing mock command.",
            "card": {"approvalId": approval_id, "runId": run_id},
            "createdAt": timestamp,
        }

        self.threads[thread_id] = thread
        self.runs[run_id] = run
        self.approvals[approval_id] = approval
        self.messages[message_id] = message

        return {"thread": thread, "message": message, "run": run, "approval": approval}

    def pending_approvals(self) -> list[dict[str, Any]]:
        return [approval for approval in self.approvals.values() if approval["status"] == "pending"]

    def thread_messages(self, thread_id: str) -> dict[str, Any] | None:
        thread = self.threads.get(thread_id)
        if thread is None:
            return None
        messages = [
            message
            for message in sorted(self.messages.values(), key=lambda item: item["createdAt"])
            if message["threadId"] == thread_id
        ]
        return {"thread": thread, "messages": messages}

    def decide_approval(self, approval_id: str, decision: str) -> dict[str, Any] | None:
        approval = self.approvals.get(approval_id)
        if approval is None:
            return None

        timestamp = now_iso()
        run = self.runs[approval["runId"]]
        if decision == "approve":
            approval["status"] = "approved"
            run["status"] = "done"
            run["currentStep"] = "Completed"
            result = {
                "id": new_id("msg"),
                "threadId": run["threadId"],
                "role": "assistant",
                "kind": "command_result",
                "body": "Mock command completed after approval.",
                "card": {"runId": run["id"]},
                "createdAt": timestamp,
            }
            self.messages[result["id"]] = result
        elif decision == "reject":
            approval["status"] = "rejected"
            run["status"] = "cancelled"
            run["currentStep"] = "Rejected by user"
            result = {
                "id": new_id("msg"),
                "threadId": run["threadId"],
                "role": "assistant",
                "kind": "command_result",
                "body": "Mock command cancelled after rejection.",
                "card": {"runId": run["id"]},
                "createdAt": timestamp,
            }
            self.messages[result["id"]] = result
        else:
            raise ValueError(f"Unsupported decision: {decision}")

        run["updatedAt"] = timestamp
        return {"approval": approval, "run": run, "result": result}

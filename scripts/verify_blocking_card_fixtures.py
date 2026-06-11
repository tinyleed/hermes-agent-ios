#!/usr/bin/env python3
"""Verify safe Hermes Desktop blocking-card event fixtures for Hermes Agent iOS.

This is an offline proof gate for the iOS inline blocking-card path. It uses
synthetic Desktop-style JSON-RPC event frames for approval/sudo/secret requests
and validates that the fixtures contain only metadata needed to render cards —
never real passwords, token values, or secret values.
"""

from __future__ import annotations

import json
import re
import sys
from dataclasses import dataclass
from typing import Any

FORBIDDEN_PAYLOAD_KEYS = {
    "password",
    "passwd",
    "secret",
    "secret_value",
    "token",
    "api_key",
    "authorization",
    "bearer",
    "value",
}

FORBIDDEN_TEXT_RE = re.compile(
    r"(sk-[A-Za-z0-9]{12,}|ghp_[A-Za-z0-9_]{12,}|xox[baprs]-|Bearer\s+[A-Za-z0-9._-]+|password\s*=|token\s*=)",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class BlockingFixture:
    name: str
    event_type: str
    expected_prompt_fragment: str
    frame: dict[str, Any]


FIXTURES: tuple[BlockingFixture, ...] = (
    BlockingFixture(
        name="approval-safe-delete-fixture",
        event_type="approval.request",
        expected_prompt_fragment="Approve safe fixture command?",
        frame={
            "jsonrpc": "2.0",
            "method": "event",
            "params": {
                "type": "approval.request",
                "session_id": "session_fixture_cards",
                "payload": {
                    "request_id": "approval-fixture-001",
                    "command": "printf 'HERMES_AGENT_APPROVAL_FIXTURE_OK' > /tmp/hermes-agent-ios-approval-fixture",
                    "description": "Approve safe fixture command?",
                    "risk_tier": "1",
                    "scope": "local_tmp_path,fixture_only",
                    "reason": "Exercise approval card rendering without destructive side effects.",
                    "rollback": "Remove /tmp/hermes-agent-ios-approval-fixture if created.",
                    "choices": "once,deny",
                },
            },
        },
    ),
    BlockingFixture(
        name="sudo-metadata-only-fixture",
        event_type="sudo.request",
        expected_prompt_fragment="Sudo password required",
        frame={
            "jsonrpc": "2.0",
            "method": "event",
            "params": {
                "type": "sudo.request",
                "session_id": "session_fixture_cards",
                "payload": {
                    "request_id": "sudo-fixture-001",
                    "prompt": "Sudo password required for a fake fixture command.",
                    "command": "id -un",
                    "reason": "Exercise sudo card chrome only; do not submit a password.",
                    "scope": "fixture_only,no_privileged_execution",
                },
            },
        },
    ),
    BlockingFixture(
        name="secret-metadata-only-fixture",
        event_type="secret.request",
        expected_prompt_fragment="Provide fake fixture secret",
        frame={
            "jsonrpc": "2.0",
            "method": "event",
            "params": {
                "type": "secret.request",
                "session_id": "session_fixture_cards",
                "payload": {
                    "request_id": "secret-fixture-001",
                    "env_var": "HERMES_AGENT_IOS_FAKE_FIXTURE_SECRET",
                    "prompt": "Provide fake fixture secret; UI must not persist or echo the value.",
                    "reason": "Exercise secret card metadata without carrying a secret value.",
                    "scope": "fixture_only,redacted_value",
                },
            },
        },
    ),
)


def flatten_strings(value: Any) -> list[str]:
    if isinstance(value, str):
        return [value]
    if isinstance(value, dict):
        out: list[str] = []
        for key, child in value.items():
            out.append(str(key))
            out.extend(flatten_strings(child))
        return out
    if isinstance(value, list):
        out: list[str] = []
        for child in value:
            out.extend(flatten_strings(child))
        return out
    return []


def payload_from_frame(frame: dict[str, Any]) -> dict[str, Any]:
    params = frame.get("params")
    if not isinstance(params, dict):
        raise AssertionError("Frame missing params object")
    payload = params.get("payload")
    if not isinstance(payload, dict):
        raise AssertionError("Frame missing payload object")
    return payload


def validate_fixture(fixture: BlockingFixture) -> dict[str, str]:
    frame = fixture.frame
    if frame.get("method") != "event":
        raise AssertionError(f"{fixture.name}: expected JSON-RPC event method")
    params = frame.get("params")
    if not isinstance(params, dict) or params.get("type") != fixture.event_type:
        raise AssertionError(f"{fixture.name}: event type mismatch")

    payload = payload_from_frame(frame)
    payload_keys = {str(key).lower() for key in payload}
    forbidden_present = payload_keys & FORBIDDEN_PAYLOAD_KEYS
    # `env_var` and prompts may use the word SECRET as a label; raw secret-bearing
    # value keys are forbidden.
    if forbidden_present:
        raise AssertionError(f"{fixture.name}: forbidden secret-bearing keys present: {sorted(forbidden_present)}")

    serialized = json.dumps(frame, sort_keys=True)
    if FORBIDDEN_TEXT_RE.search(serialized):
        raise AssertionError(f"{fixture.name}: fixture text looks secret-bearing")

    request_id = payload.get("request_id")
    if not isinstance(request_id, str) or not request_id:
        raise AssertionError(f"{fixture.name}: missing request_id")

    prompt_text = " ".join(
        str(payload.get(key, ""))
        for key in ("question", "prompt", "description", "command")
    )
    if fixture.expected_prompt_fragment not in prompt_text:
        raise AssertionError(f"{fixture.name}: prompt fragment not found")

    return {
        "name": fixture.name,
        "event": fixture.event_type,
        "request_id": request_id,
        "session_id": str(params.get("session_id", "")),
        "value_state": "metadata-only/redacted",
    }


def validate_all() -> list[dict[str, str]]:
    summaries = [validate_fixture(fixture) for fixture in FIXTURES]
    seen = {item["event"] for item in summaries}
    required = {"approval.request", "sudo.request", "secret.request"}
    missing = required - seen
    if missing:
        raise AssertionError(f"Missing blocking fixture events: {sorted(missing)}")
    return summaries


def main() -> int:
    try:
        summaries = validate_all()
    except AssertionError as exc:
        print(f"FAIL blocking-card fixture verification: {exc}", file=sys.stderr)
        return 1

    print("OK blocking-card fixtures: approval/sudo/secret metadata-only events verified")
    for item in summaries:
        print(
            f"- {item['event']}: request_id={item['request_id']} "
            f"session_id={item['session_id']} value={item['value_state']}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

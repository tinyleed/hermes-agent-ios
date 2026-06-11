#!/usr/bin/env python3
"""Synthetic-only smoke/eval for the shared OpenAI API lane.

This script is intentionally narrow:
- it sends only hard-coded synthetic Hermes gateway fixtures;
- it never reads repo files, Hermes memory, Obsidian notes, screenshots, or live transcripts;
- real API calls require HERMES_AGENT_SHARED_OPENAI_ALLOW=synthetic-only.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from typing import Any

API_URL = "https://api.openai.com/v1/responses"
DEFAULT_MODEL = "gpt-5.4-mini"
ALLOW_ENV = "HERMES_AGENT_SHARED_OPENAI_ALLOW"
KEY_ENV = "OPENAI_SHARED_EVALS_API_KEY"
REQUIRED_ALLOW_VALUE = "synthetic-only"

SYNTHETIC_FIXTURE: dict[str, Any] = {
    "fixture_name": "synthetic-hermes-gateway-ui-safety-v1",
    "source": "synthetic-only; no live user/session data",
    "events": [
        {
            "type": "session.list.result",
            "sessions": [
                {
                    "id": "sess_fake_001",
                    "title": "Synthetic planning run",
                    "updated_at": "2026-01-01T12:00:00Z",
                    "message_count": 4,
                }
            ],
        },
        {
            "type": "session.resume.result",
            "session_id": "sess_fake_001",
            "messages": [
                {"role": "user", "content": "Synthetic request with no private data."},
                {"role": "assistant", "content": "Synthetic response with no secrets."},
            ],
        },
        {
            "type": "approval.request",
            "request_id": "approval_fake_001",
            "risk": "medium",
            "summary": "Allow synthetic command execution?",
            "command_preview": "python3 scripts/example_synthetic_check.py",
            "secret_policy": "no tokens, credentials, or private paths included",
        },
        {
            "type": "message.delta",
            "content_delta": "Synthetic streaming text for UI fixture coverage.",
        },
    ],
}

SYSTEM_PROMPT = """You are evaluating a synthetic Hermes Agent iOS Hermes gateway fixture.
Return compact markdown with:
- safety verdict: safe / unsafe
- whether the fixture is useful for UI/contract coverage
- missing cases worth adding
- any secret-leak risk
Do not ask for real user data. Do not request credentials. Keep the answer under 250 words.
""".strip()


def build_payload(model: str) -> dict[str, Any]:
    return {
        "model": model,
        "input": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {
                "role": "user",
                "content": "Evaluate this synthetic-only fixture:\n"
                + json.dumps(SYNTHETIC_FIXTURE, indent=2, sort_keys=True),
            },
        ],
    }


def extract_text(response: dict[str, Any]) -> str:
    parts: list[str] = []
    for item in response.get("output", []):
        for content in item.get("content", []):
            if content.get("type") in {"output_text", "text"} and content.get("text"):
                parts.append(content["text"])
    if parts:
        return "\n".join(parts).strip()
    if response.get("output_text"):
        return str(response["output_text"]).strip()
    return json.dumps(response, indent=2, sort_keys=True)


def call_openai(payload: dict[str, Any], api_key: str) -> dict[str, Any]:
    body = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        API_URL,
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        error_body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"OpenAI API HTTP {exc.code}: {error_body}") from exc


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the synthetic payload and do not call OpenAI.",
    )
    args = parser.parse_args(argv)

    payload = build_payload(args.model)

    if args.dry_run:
        print("DRY RUN — no OpenAI API call made.")
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 0

    allow_value = os.getenv(ALLOW_ENV, "")
    if allow_value != REQUIRED_ALLOW_VALUE:
        print(
            f"Refusing shared OpenAI call: set {ALLOW_ENV}={REQUIRED_ALLOW_VALUE!r} "
            "after confirming the payload is synthetic-only.",
            file=sys.stderr,
        )
        return 2

    api_key = os.getenv(KEY_ENV, "")
    if not api_key:
        print(f"Missing {KEY_ENV}; no API call made.", file=sys.stderr)
        return 2

    result = call_openai(payload, api_key)
    print(extract_text(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

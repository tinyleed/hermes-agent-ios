#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
import threading
import time
from pathlib import Path
from urllib.request import urlopen

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))
sys.path.insert(0, str(REPO_ROOT / "scripts"))

from mock_gateway.ws_fixture import (  # noqa: E402
    DEFAULT_FINAL_TEXT,
    DEFAULT_TOKEN,
    BlockingFixtureRunState,
    make_blocking_fixture_gateway,
)
from smoke_hermes_gateway_ws import MinimalWebSocket, rpc, ws_url_from_base  # noqa: E402

TOKEN_RE = re.compile(r'window\.__HERMES_SESSION_TOKEN__\s*=\s*"([^"]+)"')
FORBIDDEN_OUTPUT = (
    "fixture-redacted-value",
    "password=",
    "token=",
    "api_key=",
    "super-secret-fixture",
)


def notification(method: str, params: dict) -> str:
    return json.dumps({"jsonrpc": "2.0", "method": method, "params": params}, separators=(",", ":"))


def read_frame(ws: MinimalWebSocket, deadline: float) -> dict:
    while time.monotonic() < deadline:
        text = ws.recv_text()
        if text is None:
            raise AssertionError("websocket closed before fixture completed")
        frame = json.loads(text)
        return frame
    raise AssertionError("timed out waiting for websocket frame")


def wait_for_event(ws: MinimalWebSocket, event_type: str, deadline: float, transcript: list[str]) -> dict:
    while time.monotonic() < deadline:
        frame = read_frame(ws, deadline)
        transcript.append(json.dumps(frame, sort_keys=True))
        params = frame.get("params") if frame.get("method") == "event" else None
        if isinstance(params, dict) and params.get("type") == event_type:
            return frame
    raise AssertionError(f"timed out waiting for {event_type}")


def wait_for_response(ws: MinimalWebSocket, response_id: str, deadline: float, transcript: list[str]) -> dict:
    while time.monotonic() < deadline:
        frame = read_frame(ws, deadline)
        transcript.append(json.dumps(frame, sort_keys=True))
        if frame.get("id") == response_id:
            return frame
    raise AssertionError(f"timed out waiting for response {response_id}")


def fetch_token(base_url: str) -> str:
    with urlopen(base_url + "/", timeout=5) as response:  # nosec: local test server only
        html = response.read().decode("utf-8", errors="replace")
    match = TOKEN_RE.search(html)
    if not match:
        raise AssertionError("mock dashboard did not expose a gateway token")
    return match.group(1)


def assert_secret_safe(transcript: list[str], summary: dict) -> None:
    rendered = "\n".join(transcript + [json.dumps(summary, sort_keys=True)])
    lower = rendered.lower()
    for forbidden in FORBIDDEN_OUTPUT:
        assert forbidden.lower() not in lower, f"forbidden secret-like output rendered: {forbidden}"
    assert "redacted_present" in rendered


def run_smoke(port: int = 0) -> str:
    state = BlockingFixtureRunState()
    server = make_blocking_fixture_gateway(("127.0.0.1", port), state=state, token=DEFAULT_TOKEN)
    actual_port = server.server_address[1]
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    ws = None
    try:
        base_url = f"http://127.0.0.1:{actual_port}"
        token = fetch_token(base_url)
        assert token == DEFAULT_TOKEN
        ws = MinimalWebSocket(ws_url_from_base(base_url, token), timeout=10)
        ws.connect()
        deadline = time.monotonic() + 20
        transcript: list[str] = []

        ws.send_text(rpc("session.create", {"cols": 96}, "create-1"))
        created = wait_for_response(ws, "create-1", deadline, transcript)
        session_id = created["result"]["session_id"]
        assert session_id == state.session_id

        ws.send_text(rpc("prompt.submit", {"session_id": session_id, "text": "exercise safe blocking cards"}, "prompt-1"))
        submitted = wait_for_response(ws, "prompt-1", deadline, transcript)
        assert submitted["result"]["accepted"] is True

        approval = wait_for_event(ws, "approval.request", deadline, transcript)
        assert approval["params"]["payload"]["request_id"] == state.approval_request_id
        ws.send_text(notification("approval.respond", {"session_id": session_id, "choice": "once", "all": False}))

        sudo = wait_for_event(ws, "sudo.request", deadline, transcript)
        assert sudo["params"]["payload"]["request_id"] == state.sudo_request_id
        ws.send_text(notification("sudo.respond", {"request_id": state.sudo_request_id, "password": "super-secret-fixture-password"}))

        secret = wait_for_event(ws, "secret.request", deadline, transcript)
        assert secret["params"]["payload"]["request_id"] == state.secret_request_id
        ws.send_text(notification("secret.respond", {"request_id": state.secret_request_id, "value": "super-secret-fixture-token"}))

        complete = wait_for_event(ws, "message.complete", deadline, transcript)
        assert complete["params"]["payload"]["text"] == DEFAULT_FINAL_TEXT
        summary = state.response_summary()
        assert [response["kind"] for response in summary["responses"]] == ["approval", "sudo", "secret"]
        assert_secret_safe(transcript, summary)
        return "OK mock blocking fixture WS: approval -> sudo -> secret -> redacted final output"
    finally:
        if ws is not None:
            ws.close()
        server.shutdown()
        thread.join(timeout=2)
        server.server_close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=0)
    args = parser.parse_args()
    print(run_smoke(port=args.port))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

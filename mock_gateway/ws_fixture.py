from __future__ import annotations

import base64
import hashlib
import json
import socket
from dataclasses import dataclass, field
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import parse_qs, urlparse

GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
DEFAULT_TOKEN = "hermes-agent-mock-gateway-token"
DEFAULT_FINAL_TEXT = "HERMES_AGENT_MOCK_BLOCKING_GATEWAY_DONE — approval, sudo, and secret responses accepted; values redacted."


@dataclass
class BlockingFixtureRunState:
    session_id: str = "session_mock_blocking_cards"
    stored_session_id: str = "stored_mock_blocking_cards"
    approval_request_id: str = "approval-mock-001"
    sudo_request_id: str = "sudo-mock-001"
    secret_request_id: str = "secret-mock-001"
    final_text: str = DEFAULT_FINAL_TEXT
    responses: list[dict[str, Any]] = field(default_factory=list)

    def record_response(self, kind: str, request_id: str | None = None, session_id: str | None = None) -> None:
        self.responses.append(
            {
                "kind": kind,
                "request_id": request_id,
                "session_id": session_id,
                "value_state": "redacted_present",
            }
        )

    def response_summary(self) -> dict[str, Any]:
        return {"responses": list(self.responses), "finalText": self.final_text}


class BlockingFixtureWebSocket:
    def __init__(self, sock: socket.socket, state: BlockingFixtureRunState):
        self.sock = sock
        self.state = state

    def send_json(self, payload: dict[str, Any]) -> None:
        self.send_text(json.dumps(payload, sort_keys=True))

    def send_rpc_result(self, request_id: Any, result: dict[str, Any]) -> None:
        self.send_json({"jsonrpc": "2.0", "id": request_id, "result": result})

    def send_event(self, event_type: str, payload: dict[str, Any]) -> None:
        self.send_json(
            {
                "jsonrpc": "2.0",
                "method": "event",
                "params": {
                    "type": event_type,
                    "session_id": self.state.session_id,
                    "payload": payload,
                },
            }
        )

    def send_approval_request(self) -> None:
        self.send_event(
            "approval.request",
            {
                "request_id": self.state.approval_request_id,
                "command": "printf 'HERMES_AGENT_APPROVAL_MOCK_OK' > /tmp/hermes-agent-ios-mock-approval",
                "description": "Approve safe mock gateway fixture command?",
                "risk_tier": 1,
                "scope": "mock_gateway_state,fixture_only",
                "reason": "Exercise the WebSocket approval request/response loop without side effects.",
                "rollback": "Remove /tmp/hermes-agent-ios-mock-approval if created.",
                "choices": "once,deny",
            },
        )

    def send_sudo_request(self) -> None:
        self.send_event(
            "sudo.request",
            {
                "request_id": self.state.sudo_request_id,
                "prompt": "Sudo password required for a safe mock gateway fixture.",
                "command": "id -un",
                "reason": "Exercise the WebSocket sudo response path; the submitted value must remain redacted.",
                "scope": "fixture_only,no_privileged_execution",
            },
        )

    def send_secret_request(self) -> None:
        self.send_event(
            "secret.request",
            {
                "request_id": self.state.secret_request_id,
                "env_var": "HERMES_AGENT_IOS_FAKE_MOCK_GATEWAY_SECRET",
                "prompt": "Provide fake fixture secret for mock gateway; output must not echo it.",
                "reason": "Exercise the WebSocket secret response path with metadata only.",
                "scope": "fixture_only,redacted_value",
            },
        )

    def send_final_response(self) -> None:
        self.send_event("message.complete", {"text": self.state.final_text})

    def serve(self) -> None:
        self.send_event("gateway.ready", {"text": "Mock blocking-card gateway ready"})
        while True:
            text = self.recv_text()
            if text is None:
                return
            try:
                frame = json.loads(text)
            except json.JSONDecodeError:
                continue
            method = frame.get("method")
            params = frame.get("params") or {}
            request_id = frame.get("id")

            if method == "session.create":
                self.send_rpc_result(
                    request_id,
                    {"session_id": self.state.session_id, "stored_session_id": self.state.stored_session_id},
                )
            elif method == "prompt.submit":
                self.send_rpc_result(request_id, {"accepted": True})
                self.send_event("message.start", {"text": ""})
                self.send_approval_request()
            elif method == "approval.respond":
                self.state.record_response("approval", session_id=str(params.get("session_id", "")))
                self.send_sudo_request()
            elif method == "sudo.respond":
                self.state.record_response("sudo", request_id=str(params.get("request_id", "")))
                self.send_sudo_redacted_ack()
                self.send_secret_request()
            elif method == "secret.respond":
                self.state.record_response("secret", request_id=str(params.get("request_id", "")))
                self.send_secret_redacted_ack()
                self.send_final_response()
            else:
                if request_id is not None:
                    self.send_json(
                        {
                            "jsonrpc": "2.0",
                            "id": request_id,
                            "error": {"code": -32601, "message": "method_not_found"},
                        }
                    )

    def send_sudo_redacted_ack(self) -> None:
        self.send_event("message.delta", {"text": "Mock sudo response accepted. Value redacted.\n"})

    def send_secret_redacted_ack(self) -> None:
        self.send_event("message.delta", {"text": "Mock secret response accepted. Value redacted.\n"})

    def recv_exact(self, length: int) -> bytes:
        data = b""
        while len(data) < length:
            chunk = self.sock.recv(length - len(data))
            if not chunk:
                raise ConnectionError("websocket closed")
            data += chunk
        return data

    def recv_text(self) -> str | None:
        try:
            header = self.recv_exact(2)
        except ConnectionError:
            return None
        opcode = header[0] & 0x0F
        masked = bool(header[1] & 0x80)
        length = header[1] & 0x7F
        if length == 126:
            length = int.from_bytes(self.recv_exact(2), "big")
        elif length == 127:
            length = int.from_bytes(self.recv_exact(8), "big")
        mask = self.recv_exact(4) if masked else b""
        payload = self.recv_exact(length) if length else b""
        if masked:
            payload = bytes(byte ^ mask[index % 4] for index, byte in enumerate(payload))
        if opcode == 8:
            return None
        if opcode == 9:
            self.send_frame(payload, opcode=10)
            return self.recv_text()
        if opcode != 1:
            return ""
        return payload.decode("utf-8")

    def send_text(self, text: str) -> None:
        self.send_frame(text.encode("utf-8"), opcode=1)

    def send_frame(self, payload: bytes, opcode: int = 1) -> None:
        first = 0x80 | opcode
        length = len(payload)
        if length < 126:
            header = bytes([first, length])
        elif length < (1 << 16):
            header = bytes([first, 126]) + length.to_bytes(2, "big")
        else:
            header = bytes([first, 127]) + length.to_bytes(8, "big")
        self.sock.sendall(header + payload)


class BlockingFixtureGatewayHandler(BaseHTTPRequestHandler):
    server_version = "HermesAgentMockGatewayWS/0.1"

    def log_message(self, format: str, *args: Any) -> None:  # noqa: A002 - stdlib signature
        return

    @property
    def fixture_state(self) -> BlockingFixtureRunState:
        return self.server.fixture_state  # type: ignore[attr-defined]

    @property
    def fixture_token(self) -> str:
        return self.server.fixture_token  # type: ignore[attr-defined]

    def do_GET(self) -> None:  # noqa: N802 - stdlib hook
        parsed = urlparse(self.path)
        if parsed.path in {"", "/"}:
            self.send_dashboard()
            return
        if parsed.path == "/api/ws" and self.headers.get("Upgrade", "").lower() == "websocket":
            token = (parse_qs(parsed.query).get("token") or [""])[0]
            if token != self.fixture_token:
                self.send_error(HTTPStatus.UNAUTHORIZED, "invalid token")
                return
            self.upgrade_to_websocket()
            return
        if parsed.path == "/debug/responses":
            self.send_json(HTTPStatus.OK, self.fixture_state.response_summary())
            return
        self.send_error(HTTPStatus.NOT_FOUND, "not found")

    def send_dashboard(self) -> None:
        body = (
            "<!doctype html><title>Hermes Agent Mock Gateway</title>"
            f"<script>window.__HERMES_SESSION_TOKEN__ = \"{self.fixture_token}\";</script>"
            "<main>Hermes Agent mock blocking-card gateway ready.</main>"
        ).encode("utf-8")
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_json(self, status: HTTPStatus, payload: dict[str, Any]) -> None:
        body = json.dumps(payload, sort_keys=True).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def upgrade_to_websocket(self) -> None:
        key = self.headers.get("Sec-WebSocket-Key", "")
        accept = base64.b64encode(hashlib.sha1((key + GUID).encode("ascii")).digest()).decode("ascii")
        self.send_response(HTTPStatus.SWITCHING_PROTOCOLS)
        self.send_header("Upgrade", "websocket")
        self.send_header("Connection", "Upgrade")
        self.send_header("Sec-WebSocket-Accept", accept)
        self.end_headers()
        BlockingFixtureWebSocket(self.connection, self.fixture_state).serve()


class BlockingFixtureGatewayServer(ThreadingHTTPServer):
    fixture_state: BlockingFixtureRunState
    fixture_token: str


def make_blocking_fixture_gateway(
    address: tuple[str, int],
    state: BlockingFixtureRunState | None = None,
    token: str = DEFAULT_TOKEN,
) -> BlockingFixtureGatewayServer:
    server = BlockingFixtureGatewayServer(address, BlockingFixtureGatewayHandler)
    server.fixture_state = state or BlockingFixtureRunState()
    server.fixture_token = token
    return server

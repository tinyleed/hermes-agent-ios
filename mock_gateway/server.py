from __future__ import annotations

import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import urlparse

from .state import GatewayState


def make_server(address: tuple[str, int], state: GatewayState | None = None) -> ThreadingHTTPServer:
    gateway_state = state or GatewayState()

    class Handler(BaseHTTPRequestHandler):
        server_version = "HermesAgentMockGateway/0.1"

        def log_message(self, format: str, *args: Any) -> None:  # noqa: A002 - stdlib signature
            return

        def _read_json(self) -> dict[str, Any]:
            length = int(self.headers.get("Content-Length", "0"))
            if length == 0:
                return {}
            raw = self.rfile.read(length).decode("utf-8")
            return json.loads(raw)

        def _send_json(self, status: int, payload: dict[str, Any]) -> None:
            body = json.dumps(payload, sort_keys=True).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_POST(self) -> None:  # noqa: N802 - stdlib hook
            path = urlparse(self.path).path
            if path == "/v0/messages":
                request = self._read_json()
                text = str(request.get("text", "")).strip()
                self._send_json(201, gateway_state.create_command(text))
                return

            if path == "/v0/notification-tokens":
                request = self._read_json()
                self._send_json(202, gateway_state.register_notification_token(request))
                return

            if path.startswith("/v0/approvals/"):
                parts = path.strip("/").split("/")
                if len(parts) == 4 and parts[0] == "v0" and parts[1] == "approvals":
                    approval_id = parts[2]
                    action = parts[3]
                    if action in {"approve", "reject"}:
                        result = gateway_state.decide_approval(approval_id, action)
                        if result is None:
                            self._send_json(404, {"error": "approval_not_found"})
                        else:
                            self._send_json(200, result)
                        return

            self._send_json(404, {"error": "not_found"})

        def do_GET(self) -> None:  # noqa: N802 - stdlib hook
            path = urlparse(self.path).path
            if path == "/v0/approvals":
                self._send_json(200, {"approvals": gateway_state.pending_approvals()})
                return
            if path.startswith("/v0/threads/"):
                parts = path.strip("/").split("/")
                if len(parts) == 4 and parts[0] == "v0" and parts[1] == "threads" and parts[3] == "messages":
                    result = gateway_state.thread_messages(parts[2])
                    if result is None:
                        self._send_json(404, {"error": "thread_not_found"})
                    else:
                        self._send_json(200, result)
                    return
            self._send_json(404, {"error": "not_found"})

    return ThreadingHTTPServer(address, Handler)


def main() -> None:
    server = make_server(("127.0.0.1", 8787))
    print("Hermes Agent mock gateway listening on http://127.0.0.1:8787")
    server.serve_forever()


if __name__ == "__main__":
    main()

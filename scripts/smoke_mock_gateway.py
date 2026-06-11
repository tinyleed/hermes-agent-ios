#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
import threading
from http.client import HTTPConnection
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))

from mock_gateway.server import make_server


def request(port: int, method: str, path: str, body: dict | None = None):
    conn = HTTPConnection("127.0.0.1", port, timeout=5)
    payload = json.dumps(body).encode("utf-8") if body is not None else None
    headers = {"Content-Type": "application/json"} if body is not None else {}
    conn.request(method, path, body=payload, headers=headers)
    response = conn.getresponse()
    raw = response.read().decode("utf-8")
    conn.close()
    return response.status, json.loads(raw)


def main() -> None:
    server = make_server(("127.0.0.1", 0))
    port = server.server_address[1]
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        status, created = request(port, "POST", "/v0/messages", {"text": "smoke command"})
        assert status == 201, (status, created)
        approval_id = created["approval"]["id"]
        status, approvals = request(port, "GET", "/v0/approvals")
        assert status == 200 and len(approvals["approvals"]) == 1, (status, approvals)
        status, decided = request(port, "POST", f"/v0/approvals/{approval_id}/approve")
        assert status == 200 and decided["run"]["status"] == "done", (status, decided)
        print("OK mock gateway smoke: command -> pending approval -> approved -> run done")
    finally:
        server.shutdown()
        thread.join(timeout=2)
        server.server_close()


if __name__ == "__main__":
    main()

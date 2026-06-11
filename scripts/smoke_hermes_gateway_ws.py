#!/usr/bin/env python3
"""Secret-safe Hermes dashboard /api/ws smoke test.

This validates the Hermes Desktop-style WebSocket path used by Hermes Agent iOS:
remote dashboard base URL + session token -> /api/ws -> JSON-RPC session.create
and, optionally, prompt.submit streaming events.

The script intentionally never prints bearer/session token values.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
import secrets
import socket
import ssl
import sys
import time
from dataclasses import dataclass
from typing import Any
from urllib.parse import urlencode, urlparse, urlunparse
from urllib.request import Request, urlopen


TOKEN_RE = re.compile(r'window\.__HERMES_SESSION_TOKEN__\s*=\s*"([^"]+)"')


@dataclass
class SmokeResult:
    base_url: str
    ws_scheme: str
    ready_seen: bool
    session_id: str | None
    prompt_submitted: bool
    prompt_completed: bool
    event_types: list[str]
    assistant_chars: int
    tool_event_count: int


def _env_first(*names: str) -> str:
    for name in names:
        value = os.environ.get(name, "").strip()
        if value:
            return value
    return ""


def normalize_base_url(value: str) -> str:
    if not value:
        raise SystemExit("Missing base URL. Pass --base-url or set HERMES_DESKTOP_REMOTE_URL.")
    parsed = urlparse(value if "://" in value else f"http://{value}")
    if parsed.scheme not in {"http", "https"}:
        raise SystemExit(f"Unsupported base URL scheme: {parsed.scheme}")
    if not parsed.netloc:
        raise SystemExit("Base URL must include a host")
    return urlunparse((parsed.scheme, parsed.netloc, parsed.path.rstrip("/"), "", "", ""))


def fetch_injected_token(base_url: str, timeout: float) -> str:
    req = Request(base_url + "/", headers={"User-Agent": "hermes-agent-ios-ws-smoke/1"})
    try:
        with urlopen(req, timeout=timeout) as resp:  # nosec: operator-provided local/LAN URL
            html = resp.read(2_000_000).decode("utf-8", errors="replace")
    except Exception as exc:
        raise SystemExit(f"Could not fetch dashboard HTML for token bootstrap: {type(exc).__name__}: {exc}")
    match = TOKEN_RE.search(html)
    if not match:
        raise SystemExit(
            "No injected session token found in dashboard HTML. "
            "Set HERMES_DESKTOP_REMOTE_TOKEN or HERMES_AGENT_IOS_HERMES_GATEWAY_WS_TOKEN."
        )
    return match.group(1)


def ws_url_from_base(base_url: str, token: str) -> str:
    parsed = urlparse(base_url)
    scheme = "wss" if parsed.scheme == "https" else "ws"
    query = urlencode({"token": token})
    return urlunparse((scheme, parsed.netloc, "/api/ws", "", query, ""))


class MinimalWebSocket:
    def __init__(self, ws_url: str, timeout: float = 20.0):
        self.ws_url = ws_url
        self.timeout = timeout
        self.sock: socket.socket | ssl.SSLSocket | None = None

    def connect(self) -> None:
        parsed = urlparse(self.ws_url)
        if parsed.scheme not in {"ws", "wss"}:
            raise RuntimeError(f"Unsupported WS scheme: {parsed.scheme}")
        host = parsed.hostname or ""
        port = parsed.port or (443 if parsed.scheme == "wss" else 80)
        raw = socket.create_connection((host, port), timeout=self.timeout)
        if parsed.scheme == "wss":
            raw = ssl.create_default_context().wrap_socket(raw, server_hostname=host)
        raw.settimeout(self.timeout)
        self.sock = raw
        key = base64.b64encode(secrets.token_bytes(16)).decode()
        path = parsed.path or "/"
        if parsed.query:
            path += "?" + parsed.query
        host_header = host if parsed.port is None else f"{host}:{port}"
        request = (
            f"GET {path} HTTP/1.1\r\n"
            f"Host: {host_header}\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\n"
            "User-Agent: hermes-agent-ios-ws-smoke/1\r\n"
            "\r\n"
        )
        raw.sendall(request.encode("ascii"))
        header = self._read_until(b"\r\n\r\n")
        first_line = header.split(b"\r\n", 1)[0].decode("ascii", errors="replace")
        if " 101 " not in first_line:
            safe = header.decode("utf-8", errors="replace").split("\r\n\r\n", 1)[0]
            raise RuntimeError(f"WebSocket upgrade failed: {safe}")
        expected = base64.b64encode(
            hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()
        ).decode()
        if expected not in header.decode("ascii", errors="ignore"):
            raise RuntimeError("WebSocket upgrade missing expected accept key")

    def _read_until(self, marker: bytes) -> bytes:
        assert self.sock is not None
        data = b""
        while marker not in data:
            chunk = self.sock.recv(4096)
            if not chunk:
                break
            data += chunk
        return data

    def send_text(self, text: str) -> None:
        assert self.sock is not None
        payload = text.encode("utf-8")
        header = bytearray([0x81])
        length = len(payload)
        if length < 126:
            header.append(0x80 | length)
        elif length < 65536:
            header.extend([0x80 | 126, (length >> 8) & 0xFF, length & 0xFF])
        else:
            header.append(0x80 | 127)
            header.extend(length.to_bytes(8, "big"))
        mask = secrets.token_bytes(4)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        self.sock.sendall(bytes(header) + mask + masked)

    def recv_text(self) -> str | None:
        assert self.sock is not None
        while True:
            first = self.sock.recv(2)
            if not first:
                return None
            opcode = first[0] & 0x0F
            masked = bool(first[1] & 0x80)
            length = first[1] & 0x7F
            if length == 126:
                length = int.from_bytes(self._recv_exact(2), "big")
            elif length == 127:
                length = int.from_bytes(self._recv_exact(8), "big")
            mask = self._recv_exact(4) if masked else b""
            payload = self._recv_exact(length) if length else b""
            if masked:
                payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
            if opcode == 0x1:
                return payload.decode("utf-8", errors="replace")
            if opcode == 0x8:
                return None
            if opcode == 0x9:
                self._send_pong(payload)
                continue

    def _recv_exact(self, n: int) -> bytes:
        assert self.sock is not None
        chunks = []
        remaining = n
        while remaining:
            chunk = self.sock.recv(remaining)
            if not chunk:
                raise RuntimeError("socket closed while reading frame")
            chunks.append(chunk)
            remaining -= len(chunk)
        return b"".join(chunks)

    def _send_pong(self, payload: bytes) -> None:
        assert self.sock is not None
        header = bytearray([0x8A])
        length = len(payload)
        header.append(0x80 | length)
        mask = secrets.token_bytes(4)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        self.sock.sendall(bytes(header) + mask + masked)

    def close(self) -> None:
        if self.sock is not None:
            try:
                self.sock.close()
            finally:
                self.sock = None


def rpc(method: str, params: dict[str, Any], rid: str) -> str:
    return json.dumps({"jsonrpc": "2.0", "id": rid, "method": method, "params": params}, separators=(",", ":"))


def event_type(frame: dict[str, Any]) -> str | None:
    if frame.get("method") != "event":
        return None
    raw_params = frame.get("params")
    params: dict[str, Any] = raw_params if isinstance(raw_params, dict) else {}
    t = params.get("type")
    return t if isinstance(t, str) else None


def payload_text(payload: Any) -> str:
    if not isinstance(payload, dict):
        return ""
    chunks = []
    for key in ("delta", "text", "content", "message", "output"):
        value = payload.get(key)
        if isinstance(value, str):
            chunks.append(value)
    return "".join(chunks)


def run_smoke(base_url: str, token: str, prompt: str | None, timeout: float) -> SmokeResult:
    ws_url = ws_url_from_base(base_url, token)
    ws = MinimalWebSocket(ws_url, timeout=min(timeout, 20.0))
    ready_seen = False
    session_id = None
    prompt_submitted = False
    prompt_completed = False
    event_types: list[str] = []
    assistant_chars = 0
    tool_event_count = 0
    deadline = time.monotonic() + timeout
    try:
        ws.connect()
        # Initial gateway.ready can arrive before or after the first request.
        ws.send_text(rpc("session.create", {"title": "Hermes Agent iOS WS smoke", "cols": 100}, "create-1"))
        while time.monotonic() < deadline:
            text = ws.recv_text()
            if text is None:
                break
            frame = json.loads(text)
            et = event_type(frame)
            if et:
                event_types.append(et)
                if et == "gateway.ready":
                    ready_seen = True
                params = frame.get("params") if isinstance(frame.get("params"), dict) else {}
                payload = params.get("payload")
                if isinstance(et, str) and et.startswith("tool."):
                    tool_event_count += 1
                assistant_chars += len(payload_text(payload))
                if prompt and et in {"message.complete", "response.complete"}:
                    prompt_completed = True
                    break
                continue
            if frame.get("id") == "create-1":
                if "error" in frame:
                    raise RuntimeError(f"session.create failed: {frame['error']}")
                result = frame.get("result") or {}
                session_id = result.get("session_id")
                if not prompt:
                    break
                ws.send_text(rpc("prompt.submit", {"session_id": session_id, "text": prompt}, "prompt-1"))
                continue
            if frame.get("id") == "prompt-1":
                if "error" in frame:
                    raise RuntimeError(f"prompt.submit failed: {frame['error']}")
                prompt_submitted = True
                continue
        return SmokeResult(
            base_url=base_url,
            ws_scheme=urlparse(ws_url).scheme,
            ready_seen=ready_seen,
            session_id=session_id,
            prompt_submitted=prompt_submitted,
            prompt_completed=prompt_completed,
            event_types=event_types,
            assistant_chars=assistant_chars,
            tool_event_count=tool_event_count,
        )
    finally:
        ws.close()


def main() -> int:
    parser = argparse.ArgumentParser(description="Secret-safe Hermes /api/ws smoke test")
    parser.add_argument("--base-url", default=_env_first("HERMES_AGENT_IOS_HERMES_GATEWAY_BASE_URL", "HERMES_DESKTOP_REMOTE_URL", "HERMES_GATEWAY_BASE_URL", "HERMES_DASHBOARD_URL"))
    parser.add_argument("--token", default=_env_first("HERMES_AGENT_IOS_HERMES_GATEWAY_WS_TOKEN", "HERMES_DESKTOP_REMOTE_TOKEN", "HERMES_GATEWAY_WS_TOKEN", "HERMES_DASHBOARD_SESSION_TOKEN"))
    parser.add_argument("--prompt", default="Reply with exactly HERMES_AGENT_IOS_WS_SMOKE_OK. Do not use tools.")
    parser.add_argument("--no-prompt", action="store_true", help="Only validate WS auth + session.create")
    parser.add_argument("--timeout", type=float, default=90.0)
    args = parser.parse_args()

    base_url = normalize_base_url(args.base_url)
    token = args.token.strip() or fetch_injected_token(base_url, timeout=10.0)
    prompt = None if args.no_prompt else args.prompt
    result = run_smoke(base_url, token, prompt=prompt, timeout=args.timeout)

    print("Hermes gateway WS smoke: ok")
    print(f"Base URL: {result.base_url}")
    print(f"WebSocket scheme: {result.ws_scheme}")
    print("Token: <redacted>")
    print(f"gateway.ready: {result.ready_seen}")
    print(f"session.create: {'ok' if result.session_id else 'missing'}")
    if prompt:
        print(f"prompt.submit: {'ok' if result.prompt_submitted else 'missing'}")
        print(f"prompt completed event: {result.prompt_completed}")
    print(f"event types: {', '.join(result.event_types[:20]) or 'none'}")
    print(f"assistant chars observed: {result.assistant_chars}")
    print(f"tool events observed: {result.tool_event_count}")

    if not result.session_id:
        return 1
    if prompt and (not result.prompt_submitted or not result.prompt_completed):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

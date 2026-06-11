#!/usr/bin/env python3
from __future__ import annotations

import argparse
import signal
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))

from mock_gateway.ws_fixture import DEFAULT_TOKEN, BlockingFixtureRunState, make_blocking_fixture_gateway  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description="Run the local Hermes Agent blocking-card WebSocket fixture gateway.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8791)
    parser.add_argument("--token", default=DEFAULT_TOKEN)
    args = parser.parse_args()

    server = make_blocking_fixture_gateway((args.host, args.port), state=BlockingFixtureRunState(), token=args.token)
    actual_host, actual_port = server.server_address[:2]
    print(f"Hermes Agent mock blocking fixture gateway listening on http://{actual_host}:{actual_port}", flush=True)

    def stop(_signum, _frame):
        server.shutdown()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        server.serve_forever()
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

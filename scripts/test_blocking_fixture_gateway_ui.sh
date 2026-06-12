#!/usr/bin/env bash
set -euo pipefail

PORT="${HERMES_AGENT_BLOCKING_FIXTURE_PORT:-9119}"
BASE_URL="http://127.0.0.1:${PORT}"
LOG_FILE="${TMPDIR:-/tmp}/hermes-agent-blocking-fixture-gateway-ui.log"

cleanup() {
  if [[ -n "${SERVER_PID:-}" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
    sleep 0.5
    if kill -0 "$SERVER_PID" 2>/dev/null; then
      kill -9 "$SERVER_PID" 2>/dev/null || true
    fi
    wait "$SERVER_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

python3 scripts/run_blocking_fixture_gateway_ws.py --host 127.0.0.1 --port "$PORT" >"$LOG_FILE" 2>&1 &
SERVER_PID=$!

for _ in {1..50}; do
  if curl -fsS "$BASE_URL/" >/dev/null 2>&1; then
    break
  fi
  sleep 0.2
done

curl -fsS "$BASE_URL/" >/dev/null

HERMES_AGENT_UI_TEST_HERMES_GATEWAY_BASE_URL="$BASE_URL" \
xcodebuild test \
  -project "Hermes Agent iOS.xcodeproj" \
  -scheme "Hermes Agent iOS" \
  -destination 'platform=iOS Simulator,name=Ananke iPhone 17' \
  -only-testing:"Hermes Agent iOS UI Tests/HermesAgentPhysicalLiveChatUITests/testMockGatewayBackedBlockingCardsResumeToRedactedFinalOutput" \
  CODE_SIGNING_ALLOWED=NO

python3 - "$BASE_URL" <<'PY'
import json
import sys
from urllib.request import urlopen

base_url = sys.argv[1]
summary = json.loads(urlopen(base_url + "/debug/responses", timeout=5).read().decode("utf-8"))
kinds = [item.get("kind") for item in summary.get("responses", [])]
if kinds != ["approval", "sudo", "secret"]:
    raise SystemExit(f"unexpected response sequence: {kinds}")
rendered = json.dumps(summary, sort_keys=True).lower()
for forbidden in ("mock-sudo-fixture-password", "mock-secret-fixture-token", "password=", "token="):
    if forbidden in rendered:
        raise SystemExit(f"forbidden secret-like value in response summary: {forbidden}")
print("OK UI mock gateway blocking loop: approval -> sudo -> secret -> redacted final output")
PY

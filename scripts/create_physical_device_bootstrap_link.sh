#!/usr/bin/env bash
set -euo pipefail

# Create a local bootstrap artifact for configuring a physical iPhone build.
# The artifact contains the secret-bearing hermes-agent-ios://hermes-api link; stdout never prints the token.

ENV_FILE="${HERMES_ENV_FILE:-$HOME/.hermes/.env}"
OUTPUT_DIR="${HERMES_AGENT_IOS_BOOTSTRAP_DIR:-/tmp/hermes-agent-ios}"
OUTPUT_HTML="$OUTPUT_DIR/bootstrap.html"
OUTPUT_URL="$OUTPUT_DIR/bootstrap.url"
OUTPUT_QR="$OUTPUT_DIR/bootstrap.png"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Hermes env file not found: $ENV_FILE" >&2
  exit 1
fi

read_env_var() {
  local key="$1"
  local default_value="${2:-}"
  local line value
  line=$(grep -E "^${key}=" "$ENV_FILE" | tail -1 || true)
  if [[ -z "$line" ]]; then
    printf '%s' "$default_value"
    return 0
  fi
  value="${line#*=}"
  value="${value%$'\r'}"
  if [[ "$value" == \"*\" && "$value" == *\" ]]; then
    value="${value:1:${#value}-2}"
  elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
    value="${value:1:${#value}-2}"
  fi
  printf '%s' "$value"
}

detect_lan_host() {
  if [[ -n "${HERMES_AGENT_IOS_DEVICE_HOST:-}" ]]; then
    printf '%s' "$HERMES_AGENT_IOS_DEVICE_HOST"
    return 0
  fi
  for iface in en0 en1 bridge100; do
    local found
    found=$(ipconfig getifaddr "$iface" 2>/dev/null || true)
    if [[ -n "$found" ]]; then
      printf '%s' "$found"
      return 0
    fi
  done
  hostname -I 2>/dev/null | awk '{print $1}' || true
}

API_SERVER_KEY="$(read_env_var API_SERVER_KEY)"
if [[ -z "$API_SERVER_KEY" ]]; then
  echo "API_SERVER_KEY is missing in $ENV_FILE" >&2
  exit 1
fi

API_SERVER_PORT="$(read_env_var API_SERVER_PORT 8642)"
HERMES_API_PUBLIC_BASE_URL="${HERMES_API_PUBLIC_BASE_URL:-$(read_env_var HERMES_API_PUBLIC_BASE_URL)}"
HERMES_GATEWAY_REMOTE_BASE_URL="${HERMES_AGENT_IOS_HERMES_GATEWAY_REMOTE_BASE_URL:-${HERMES_DESKTOP_REMOTE_URL:-$(read_env_var HERMES_GATEWAY_REMOTE_BASE_URL)}}"
HERMES_GATEWAY_WS_TOKEN="${HERMES_AGENT_IOS_HERMES_GATEWAY_WS_TOKEN:-${HERMES_DESKTOP_REMOTE_TOKEN:-$(read_env_var HERMES_GATEWAY_WS_TOKEN)}}"
if [[ -z "$HERMES_GATEWAY_REMOTE_BASE_URL" ]]; then
  HERMES_GATEWAY_REMOTE_BASE_URL="${HERMES_DESKTOP_REMOTE_URL:-$(read_env_var HERMES_DESKTOP_REMOTE_URL)}"
fi
if [[ -z "$HERMES_GATEWAY_WS_TOKEN" ]]; then
  HERMES_GATEWAY_WS_TOKEN="${HERMES_DASHBOARD_SESSION_TOKEN:-$(read_env_var HERMES_DASHBOARD_SESSION_TOKEN)}"
fi
if [[ -z "$HERMES_API_PUBLIC_BASE_URL" ]]; then
  LAN_HOST="$(detect_lan_host)"
  if [[ -z "$LAN_HOST" ]]; then
    echo "Could not detect LAN host. Set HERMES_AGENT_IOS_DEVICE_HOST or HERMES_API_PUBLIC_BASE_URL." >&2
    exit 1
  fi
  HERMES_API_PUBLIC_BASE_URL="http://${LAN_HOST}:${API_SERVER_PORT}"
fi

mkdir -p "$OUTPUT_DIR"

python3 - "$HERMES_API_PUBLIC_BASE_URL" "$API_SERVER_KEY" "$HERMES_GATEWAY_REMOTE_BASE_URL" "$HERMES_GATEWAY_WS_TOKEN" "$OUTPUT_HTML" "$OUTPUT_URL" <<'PY'
import html
import pathlib
import sys
import urllib.parse

base_url, token, gateway_base_url, gateway_token, html_path, url_path = sys.argv[1:]
query = {
    "base_url": base_url,
    "token": token,
}
if gateway_base_url.strip():
    query["gateway_base_url"] = gateway_base_url
if gateway_token.strip():
    query["gateway_ws_token"] = gateway_token
bootstrap_url = "hermes-agent-ios://hermes-api?" + urllib.parse.urlencode(query)

html_content = f"""<!doctype html>
<html lang=\"en\">
<head>
  <meta charset=\"utf-8\">
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
  <title>Hermes Agent iOS Hermes Bootstrap</title>
  <style>
    body {{ font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 2rem; line-height: 1.45; }}
    code {{ word-break: break-all; }}
    a.button {{ display: inline-block; padding: 0.8rem 1rem; border-radius: 12px; background: #111827; color: white; text-decoration: none; }}
  </style>
</head>
<body>
  <h1>Hermes Agent iOS Hermes Bootstrap</h1>
  <p>Open this file on the iPhone, then tap the button. The link configures the Hermes API base URL and bearer token inside the app.</p>
  <p><a class=\"button\" href=\"{html.escape(bootstrap_url, quote=True)}\">Configure Hermes Agent iOS</a></p>
  <p>Hermes API URL: <code>{html.escape(base_url)}</code></p>
  <p>Hermes gateway URL: <code>{html.escape(gateway_base_url) if gateway_base_url.strip() else '&lt;not configured&gt;'}</code></p>
  <p>Bearer token: <code>&lt;redacted&gt;</code></p>
  <p>Gateway token: <code>&lt;redacted&gt;</code></p>
</body>
</html>
"""
pathlib.Path(html_path).write_text(html_content)
pathlib.Path(url_path).write_text(bootstrap_url)
PY

if command -v qrencode >/dev/null 2>&1; then
  qrencode -o "$OUTPUT_QR" "$(cat "$OUTPUT_URL")"
  QR_STATUS="$OUTPUT_QR"
else
  QR_STATUS="qrencode not installed; HTML link created only"
fi

echo "Created Hermes Agent iOS physical-device bootstrap artifacts in $OUTPUT_DIR"
echo "Hermes API URL: $HERMES_API_PUBLIC_BASE_URL"
echo "Hermes gateway URL: ${HERMES_GATEWAY_REMOTE_BASE_URL:-<not configured>}"
echo "Bearer token: <redacted>"
echo "Gateway token: <redacted>"
echo "Bootstrap HTML: $OUTPUT_HTML"
echo "Bootstrap URL file: $OUTPUT_URL"
echo "Bootstrap QR: $QR_STATUS"

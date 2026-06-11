#!/usr/bin/env bash
set -euo pipefail

# Verify that the Mac mini Hermes API server is reachable over the same LAN/HTTPS URL
# a physical iPhone will use. Reads secrets from ~/.hermes/.env but never prints them.

ENV_FILE="${HERMES_ENV_FILE:-$HOME/.hermes/.env}"
CAPABILITIES_PATH="/v1/capabilities"

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
}

API_SERVER_KEY="$(read_env_var API_SERVER_KEY)"
if [[ -z "$API_SERVER_KEY" ]]; then
  echo "API_SERVER_KEY is missing in $ENV_FILE" >&2
  exit 1
fi

API_SERVER_HOST="$(read_env_var API_SERVER_HOST 127.0.0.1)"
API_SERVER_PORT="$(read_env_var API_SERVER_PORT 8642)"
HERMES_API_PUBLIC_BASE_URL="${HERMES_API_PUBLIC_BASE_URL:-$(read_env_var HERMES_API_PUBLIC_BASE_URL)}"
LAN_HOST="$(detect_lan_host)"

if [[ -z "$HERMES_API_PUBLIC_BASE_URL" ]]; then
  if [[ -z "$LAN_HOST" ]]; then
    echo "Could not detect LAN host. Set HERMES_AGENT_IOS_DEVICE_HOST or HERMES_API_PUBLIC_BASE_URL." >&2
    exit 1
  fi
  HERMES_API_PUBLIC_BASE_URL="http://${LAN_HOST}:${API_SERVER_PORT}"
fi

if [[ "$API_SERVER_HOST" == "127.0.0.1" || "$API_SERVER_HOST" == "localhost" ]]; then
  echo "Hermes API appears localhost-bound via API_SERVER_HOST=$API_SERVER_HOST. Set API_SERVER_HOST=0.0.0.0 and restart gateway for physical-device LAN access." >&2
fi

probe_url="${HERMES_API_PUBLIC_BASE_URL%/}${CAPABILITIES_PATH}"
response_file="$(mktemp)"
curl_config="$(mktemp)"
trap 'rm -f "$response_file" "$curl_config"' EXIT
chmod 600 "$curl_config"
{
  printf 'silent\n'
  printf 'show-error\n'
  printf 'max-time = 5\n'
  printf '%s\n' "header = \"Authorization: Bearer ${API_SERVER_KEY}\""
  printf 'output = "%s"\n' "$response_file"
  printf 'write-out = "%%{http_code}"\n'
} > "$curl_config"

http_code=$(curl --config "$curl_config" "$probe_url" || true)

if [[ "$http_code" == "200" ]]; then
  echo "LAN Hermes API reachable: $HERMES_API_PUBLIC_BASE_URL"
  echo "Capabilities endpoint: $CAPABILITIES_PATH -> HTTP 200"
  echo "Bearer token: <redacted>"
  echo "HERMES_API_PUBLIC_BASE_URL=$HERMES_API_PUBLIC_BASE_URL"
  exit 0
fi

echo "LAN Hermes API probe failed: $HERMES_API_PUBLIC_BASE_URL ($CAPABILITIES_PATH -> HTTP ${http_code:-000})" >&2
echo "Bearer token: <redacted>" >&2
if [[ -n "$LAN_HOST" ]]; then
  echo "Suggested public URL after binding gateway to LAN: http://${LAN_HOST}:${API_SERVER_PORT}" >&2
fi
exit 1

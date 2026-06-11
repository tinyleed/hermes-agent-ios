#!/usr/bin/env bash
set -euo pipefail

# Inject local Hermes API settings into the Hermes Agent iOS simulator app defaults.
# Secrets are read from ~/.hermes/.env and are never printed.

APP_BUNDLE_ID="com.tinyleed.hermes-agent-ios"
DEVICE_NAME="${HERMES_AGENT_IOS_SIM_DEVICE_NAME:-Hermes Agent iPhone 17}"
ENV_FILE="${HERMES_ENV_FILE:-$HOME/.hermes/.env}"

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

API_SERVER_KEY="$(read_env_var API_SERVER_KEY)"
if [[ -z "$API_SERVER_KEY" ]]; then
  echo "API_SERVER_KEY is missing in $ENV_FILE" >&2
  exit 1
fi

API_SERVER_HOST="$(read_env_var API_SERVER_HOST 127.0.0.1)"
API_SERVER_PORT="$(read_env_var API_SERVER_PORT 8642)"
SIMULATOR_API_SERVER_HOST="$API_SERVER_HOST"
if [[ "$SIMULATOR_API_SERVER_HOST" == "0.0.0.0" || "$SIMULATOR_API_SERVER_HOST" == "::" ]]; then
  SIMULATOR_API_SERVER_HOST="127.0.0.1"
fi
HERMES_API_BASE_URL="$(read_env_var HERMES_API_BASE_URL)"
if [[ -z "$HERMES_API_BASE_URL" ]]; then
  HERMES_API_BASE_URL="http://${SIMULATOR_API_SERVER_HOST}:${API_SERVER_PORT}"
fi

DEVICE="${1:-}"
if [[ -z "$DEVICE" ]]; then
  DEVICE=$(xcrun simctl list devices booted | awk -F'[()]' -v name="$DEVICE_NAME" '$0 ~ name {print $2; exit}')
fi
if [[ -z "$DEVICE" ]]; then
  DEVICE=$(xcrun simctl list devices booted | awk -F'[()]' 'NR > 1 && /Booted/ {print $2; exit}')
fi
if [[ -z "$DEVICE" ]]; then
  echo "No booted simulator found. Run scripts/launch_simulator.sh first or pass a simulator UDID." >&2
  exit 1
fi

xcrun simctl spawn "$DEVICE" defaults write com.tinyleed.hermes-agent-ios hermesAPIBaseURL "$HERMES_API_BASE_URL"
xcrun simctl spawn "$DEVICE" defaults write com.tinyleed.hermes-agent-ios hermesBearerToken "$API_SERVER_KEY"

HERMES_GATEWAY_BASE_URL="${HERMES_AGENT_IOS_HERMES_GATEWAY_BASE_URL:-${HERMES_DESKTOP_REMOTE_URL:-$(read_env_var HERMES_GATEWAY_BASE_URL)}}"
HERMES_GATEWAY_WS_URL="${HERMES_AGENT_IOS_HERMES_GATEWAY_WS_URL:-$(read_env_var HERMES_GATEWAY_WS_URL)}"
HERMES_GATEWAY_WS_TOKEN="${HERMES_AGENT_IOS_HERMES_GATEWAY_WS_TOKEN:-${HERMES_DESKTOP_REMOTE_TOKEN:-$(read_env_var HERMES_GATEWAY_WS_TOKEN)}}"
if [[ -n "$HERMES_GATEWAY_BASE_URL" ]]; then
  xcrun simctl spawn "$DEVICE" defaults write com.tinyleed.hermes-agent-ios hermesGatewayRemoteBaseURL "$HERMES_GATEWAY_BASE_URL"
  xcrun simctl spawn "$DEVICE" defaults delete com.tinyleed.hermes-agent-ios hermesGatewayWebSocketURL 2>/dev/null || true
fi
if [[ -n "$HERMES_GATEWAY_WS_URL" ]]; then
  xcrun simctl spawn "$DEVICE" defaults write com.tinyleed.hermes-agent-ios hermesGatewayWebSocketURL "$HERMES_GATEWAY_WS_URL"
fi
if [[ -n "$HERMES_GATEWAY_WS_TOKEN" ]]; then
  xcrun simctl spawn "$DEVICE" defaults write com.tinyleed.hermes-agent-ios hermesGatewayWebSocketToken "$HERMES_GATEWAY_WS_TOKEN"
fi

echo "Configured Hermes API defaults for $APP_BUNDLE_ID on simulator $DEVICE"
echo "Hermes API URL: $HERMES_API_BASE_URL"
if [[ -n "$HERMES_GATEWAY_BASE_URL" ]]; then
  echo "Hermes gateway remote base URL: configured"
elif [[ -n "$HERMES_GATEWAY_WS_URL" ]]; then
  echo "Hermes gateway WebSocket URL: configured"
else
  echo "Hermes gateway WebSocket URL: not configured"
fi
echo "Bearer token: <redacted>"
echo "Gateway WebSocket token: <redacted>"

#!/usr/bin/env bash
set -euo pipefail

# Run the signed physical-device build inside the logged-in Aqua/Terminal session.
# Hermes background tool sessions can inspect/install artifacts, but macOS may block
# private-key access for codesign there. This runner delegates only the signing build
# to Terminal.app and waits for a status file, keeping secrets out of stdout.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_ROOT="${HERMES_AGENT_IOS_AQUA_RUN_ROOT:-/tmp/hermes-agent-ios/aqua-signing-runner}"
RUN_ID="$(date +%Y%m%d-%H%M%S)-$$"
RUN_DIR="$RUN_ROOT/$RUN_ID"
COMMAND_FILE="$RUN_DIR/build.command"
LOG_FILE="$RUN_DIR/physical-device-build.log"
STATUS_FILE="$RUN_DIR/status"
TIMEOUT_SECONDS="${HERMES_AGENT_IOS_AQUA_BUILD_TIMEOUT_SECONDS:-900}"
DEVELOPMENT_TEAM="${HERMES_AGENT_IOS_DEVELOPMENT_TEAM:-}"
ALLOW_GENERIC="${HERMES_AGENT_IOS_ALLOW_GENERIC_DEVICE_BUILD:-0}"
PUBLIC_BASE_URL="${HERMES_API_PUBLIC_BASE_URL:-}"
DEVICE_ID="${HERMES_AGENT_IOS_DEVICE_ID:-}"

cd "$ROOT_DIR"
mkdir -p "$RUN_DIR"

if [[ -z "$DEVELOPMENT_TEAM" ]]; then
  DEVELOPMENT_TEAM="$(python3 - "$ROOT_DIR/project.yml" <<'PY'
from pathlib import Path
import re, sys
text = Path(sys.argv[1]).read_text(errors='ignore')
match = re.search(r'\bDEVELOPMENT_TEAM:\s*([A-Z0-9]+)', text)
print(match.group(1) if match else '')
PY
)"
fi

if [[ -z "$DEVELOPMENT_TEAM" ]]; then
  echo "HERMES_AGENT_IOS_DEVELOPMENT_TEAM is not set and no DEVELOPMENT_TEAM was found in project.yml" >&2
  exit 2
fi

shell_quote() {
  python3 - "$1" <<'PY'
import shlex, sys
print(shlex.quote(sys.argv[1]))
PY
}

ROOT_Q="$(shell_quote "$ROOT_DIR")"
LOG_Q="$(shell_quote "$LOG_FILE")"
STATUS_Q="$(shell_quote "$STATUS_FILE")"
TEAM_Q="$(shell_quote "$DEVELOPMENT_TEAM")"
ALLOW_Q="$(shell_quote "$ALLOW_GENERIC")"
PUBLIC_Q="$(shell_quote "$PUBLIC_BASE_URL")"
DEVICE_Q="$(shell_quote "$DEVICE_ID")"

cat >"$COMMAND_FILE" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd $ROOT_Q
export HERMES_AGENT_IOS_DEVELOPMENT_TEAM=$TEAM_Q
export HERMES_AGENT_IOS_ALLOW_GENERIC_DEVICE_BUILD=$ALLOW_Q
export HERMES_API_PUBLIC_BASE_URL=$PUBLIC_Q
export HERMES_AGENT_IOS_DEVICE_ID=$DEVICE_Q
mkdir -p /tmp/hermes-agent-ios
{
  echo "[aqua-signing-runner] started: \$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "[aqua-signing-runner] root: $ROOT_Q"
  echo "[aqua-signing-runner] development team: <configured>"
  set +e
  ./scripts/prepare_physical_device_handoff.sh
  status=\$?
  set -e
  printf '%s\n' "\$status" >$STATUS_Q
  exit "\$status"
} >$LOG_Q 2>&1
EOF
chmod 700 "$COMMAND_FILE"

# Terminal.app is the deliberate Aqua lane. Do not use launchctl/asuser here; those
# can still land in a Background audit context from Hermes.
osascript - "$COMMAND_FILE" <<'OSA'
on run argv
  set commandPath to item 1 of argv
  tell application "Terminal"
    do script "/bin/bash " & quoted form of commandPath
  end tell
end run
OSA

echo "Aqua signing build dispatched."
echo "Run directory: $RUN_DIR"
echo "Build log: $LOG_FILE"
echo "Waiting for Aqua build status..."

start_epoch="$(date +%s)"
while [[ ! -f "$STATUS_FILE" ]]; do
  now_epoch="$(date +%s)"
  elapsed=$((now_epoch - start_epoch))
  if (( elapsed > TIMEOUT_SECONDS )); then
    echo "Timed out after ${TIMEOUT_SECONDS}s waiting for Aqua signing build." >&2
    echo "Partial log excerpt:" >&2
    tail -80 "$LOG_FILE" >&2 2>/dev/null || true
    exit 124
  fi
  sleep 5
done

status="$(tr -d '[:space:]' <"$STATUS_FILE")"
if [[ "$status" != "0" ]]; then
  echo "Aqua signing build failed with status $status. Log excerpt:" >&2
  tail -120 "$LOG_FILE" >&2 2>/dev/null || true
  exit "$status"
fi

APP_PATH="$(find /tmp/hermes-agent-ios/DerivedData-PhysicalDevice/Build/Products -path '*iphoneos/*.app' -maxdepth 4 -type d | head -1 || true)"
APPEX_PATHS=""

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "Aqua build succeeded but no iPhoneOS app artifact was found." >&2
  exit 3
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH" >/dev/null
while IFS= read -r appex_path; do
  [[ -z "$appex_path" ]] && continue
  codesign --verify --deep --strict --verbose=2 "$appex_path" >/dev/null
  APPEX_PATHS+="$appex_path"$'\n'
done < <(find "$APP_PATH" -path '*.appex' -maxdepth 4 -type d)

echo "Aqua signing build succeeded."
echo "App artifact: $APP_PATH"
if [[ -n "$APPEX_PATHS" ]]; then
  printf '%s' "$APPEX_PATHS" | while IFS= read -r appex_path; do
    [[ -n "$appex_path" ]] && echo "Embedded extension: $appex_path"
  done
fi
echo "codesign verification: OK"

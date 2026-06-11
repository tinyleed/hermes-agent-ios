#!/usr/bin/env bash
set -euo pipefail

# Install and launch the latest signed Hermes Agent iOS physical-device artifact.
# The bootstrap URL is secret-bearing; never print it or raw devicectl JSON.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${HERMES_AGENT_IOS_DERIVED_DATA:-/tmp/hermes-agent-ios/DerivedData-PhysicalDevice}"
BOOTSTRAP_URL_FILE="${HERMES_AGENT_IOS_BOOTSTRAP_URL_FILE:-/tmp/hermes-agent-ios/bootstrap.url}"
INSTALL_JSON="/tmp/hermes-agent-ios/device-install.json"
LAUNCH_JSON="/tmp/hermes-agent-ios/device-launch.json"
INSTALL_LOG="/tmp/hermes-agent-ios/device-install.log"
LAUNCH_LOG="/tmp/hermes-agent-ios/device-launch.log"
BUNDLE_ID="com.tinyleed.hermes-agent-ios"
DEVICE_ID="${HERMES_AGENT_IOS_DEVICE_ID:-}"

cd "$ROOT_DIR"
mkdir -p /tmp/hermes-agent-ios

redact_log() {
  python3 - "$@" <<'PY'
from pathlib import Path
import os, re, sys
sources = []
if len(sys.argv) > 1 and Path(sys.argv[1]).exists():
    text = Path(sys.argv[1]).read_text(errors='ignore')
else:
    text = sys.stdin.read()
secret_values = []
env = Path(os.environ.get('HERMES_ENV_FILE', str(Path.home()/'.hermes/.env')))
if env.exists():
    for line in env.read_text(errors='ignore').splitlines():
        if line.startswith('API_SERVER_KEY='):
            value = line.split('=', 1)[1].strip().strip('"').strip("'")
            if value:
                secret_values.append(value)
            break
bootstrap = Path(os.environ.get('HERMES_AGENT_IOS_BOOTSTRAP_URL_FILE', '/tmp/hermes-agent-ios/bootstrap.url'))
if bootstrap.exists():
    value = bootstrap.read_text(errors='ignore').strip()
    if value:
        secret_values.append(value)
for value in secret_values:
    text = text.replace(value, '<redacted>')
text = re.sub(r'(token=)[^&\s"\']+', r'\1<redacted>', text)
text = re.sub(r'(Authorization: Bearer\s+)[^\s"\']+', r'\1<redacted>', text)
print(text.rstrip())
PY
}

find_app_path() {
  find "$DERIVED_DATA/Build/Products" -path '*iphoneos/*.app' -maxdepth 4 -type d | head -1 || true
}

first_physical_iphone_id() {
  local devicectl_id
  devicectl_id="$(xcrun devicectl list devices 2>/dev/null | python3 -c '
import re, sys
for line in sys.stdin:
    if "iPhone" not in line or "available" not in line:
        continue
    match = re.search(r"([0-9A-Fa-f-]{36})", line)
    if match:
        print(match.group(1))
        raise SystemExit(0)
raise SystemExit(1)
' || true)"
  if [[ -n "$devicectl_id" ]]; then
    printf '%s\n' "$devicectl_id"
    return 0
  fi
  xcrun xctrace list devices 2>/dev/null \
    | python3 -c '
import re, sys
in_simulators = False
in_offline_devices = False
for line in sys.stdin:
    if line.startswith("== Simulators =="):
        in_simulators = True
        in_offline_devices = False
    elif line.startswith("== Devices Offline =="):
        in_simulators = False
        in_offline_devices = True
    elif line.startswith("== Devices =="):
        in_simulators = False
        in_offline_devices = False
    if in_simulators or in_offline_devices or "iPhone" not in line:
        continue
    match = re.search(r"\(([0-9A-Fa-f-]{36}|[0-9A-Fa-f-]{24,40})\)", line)
    if match:
        print(match.group(1))
        raise SystemExit(0)
raise SystemExit(1)
'
}

APP_PATH="$(find_app_path)"
if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "No signed iPhoneOS .app artifact found under $DERIVED_DATA" >&2
  echo "Run scripts/prepare_physical_device_handoff.sh first." >&2
  exit 2
fi

if [[ ! -f "$BOOTSTRAP_URL_FILE" ]]; then
  echo "Missing bootstrap URL file: $BOOTSTRAP_URL_FILE" >&2
  echo "Run scripts/create_physical_device_bootstrap_link.sh first." >&2
  exit 3
fi

if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="$(first_physical_iphone_id || true)"
fi
if [[ -z "$DEVICE_ID" ]]; then
  echo "No connected physical iPhone detected. Unlock/trust the iPhone and retry." >&2
  exit 4
fi

BOOTSTRAP_URL="$(python3 - "$BOOTSTRAP_URL_FILE" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).read_text().strip())
PY
)"

if [[ -z "$BOOTSTRAP_URL" ]]; then
  echo "Bootstrap URL file is empty: $BOOTSTRAP_URL_FILE" >&2
  exit 5
fi

echo "Verifying signed app artifact..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH" >/dev/null

echo "Installing Hermes Agent iOS on physical iPhone..."
set +e
xcrun devicectl device install app \
  --device "$DEVICE_ID" \
  --quiet \
  --json-output "$INSTALL_JSON" \
  --log-output "$INSTALL_LOG" \
  "$APP_PATH" >"$INSTALL_LOG.stdout" 2>"$INSTALL_LOG.stderr"
install_status=$?
set -e
if [[ "$install_status" -ne 0 ]]; then
  echo "Install failed. Redacted devicectl output:" >&2
  redact_log "$INSTALL_LOG.stdout" >&2 || true
  redact_log "$INSTALL_LOG.stderr" >&2 || true
  redact_log "$INSTALL_LOG" >&2 || true
  exit "$install_status"
fi

echo "Launching Hermes Agent iOS with redacted bootstrap payload URL..."
echo "Bearer token: <redacted>"
set +e
xcrun devicectl device process launch \
  --device "$DEVICE_ID" \
  --quiet \
  --terminate-existing \
  --payload-url "$BOOTSTRAP_URL" \
  --json-output "$LAUNCH_JSON" \
  --log-output "$LAUNCH_LOG" \
  "$BUNDLE_ID" >"$LAUNCH_LOG.stdout" 2>"$LAUNCH_LOG.stderr"
launch_status=$?
set -e
if [[ "$launch_status" -ne 0 ]]; then
  echo "Launch failed. Redacted devicectl output:" >&2
  redact_log "$LAUNCH_LOG.stdout" >&2 || true
  redact_log "$LAUNCH_LOG.stderr" >&2 || true
  redact_log "$LAUNCH_LOG" >&2 || true
  exit "$launch_status"
fi

python3 - "$INSTALL_JSON" "$LAUNCH_JSON" <<'PY'
import json, sys
install = json.load(open(sys.argv[1]))
launch = json.load(open(sys.argv[2]))
apps = install.get('result', {}).get('installedApplications', [])
bundle = apps[0].get('bundleID', '<unknown>') if apps else '<unknown>'
pid = launch.get('result', {}).get('process', {}).get('processIdentifier', '<unknown>')
print(f"Installed bundle: {bundle}")
print(f"Launched process id: {pid}")
print("Bootstrap payload URL: <redacted>")
print("Device install/launch ready.")
PY

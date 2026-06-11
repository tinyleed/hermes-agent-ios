#!/usr/bin/env bash
set -euo pipefail

# Prepare the Hermes Agent iOS physical iPhone handoff:
# 1. verify the Hermes API is reachable from the device-facing LAN/HTTPS URL;
# 2. regenerate secret-bearing bootstrap artifacts without printing the bearer token;
# 3. inspect connected physical iPhone availability;
# 4. attempt a signed generic iOS build when a development team is provided.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_NAME="Hermes Agent iOS.xcodeproj"
SCHEME_NAME="Hermes Agent iOS"
BOOTSTRAP_HTML="/tmp/hermes-agent-ios/bootstrap.html"
BUILD_LOG="/tmp/hermes-agent-ios/physical-device-build.log"
DERIVED_DATA="/tmp/hermes-agent-ios/DerivedData-PhysicalDevice"
DEVELOPMENT_TEAM="${HERMES_AGENT_IOS_DEVELOPMENT_TEAM:-}"
if [[ -z "$DEVELOPMENT_TEAM" && -f "$ROOT_DIR/project.yml" ]]; then
  DEVELOPMENT_TEAM="$(python3 - "$ROOT_DIR/project.yml" <<'PY'
from pathlib import Path
import re, sys
text = Path(sys.argv[1]).read_text(errors='ignore')
match = re.search(r'\bDEVELOPMENT_TEAM:\s*([A-Z0-9]+)', text)
print(match.group(1) if match else '')
PY
)"
fi
ALLOW_BUILD_WITHOUT_DEVICE="${HERMES_AGENT_IOS_ALLOW_GENERIC_DEVICE_BUILD:-0}"

cd "$ROOT_DIR"
mkdir -p /tmp/hermes-agent-ios

redact_log() {
  python3 - "$@" <<'PY'
from pathlib import Path
import os, sys
text = Path(sys.argv[1]).read_text(errors='ignore') if len(sys.argv) > 1 and Path(sys.argv[1]).exists() else sys.stdin.read()
key = ''
env = Path(os.environ.get('HERMES_ENV_FILE', str(Path.home()/'.hermes/.env')))
if env.exists():
    for line in env.read_text(errors='ignore').splitlines():
        if line.startswith('API_SERVER_KEY='):
            key = line.split('=', 1)[1].strip().strip('"').strip("'")
            break
if key:
    text = text.replace(key, '<redacted>')
print(text.rstrip())
PY
}

print_codesign_keychain_hint_if_needed() {
  if grep -Eq 'errSecInteractionNotAllowed|errKCInteractionNotAllowed|CSSMERR_CSP_NO_USER_INTERACTION|errSecInternalComponent' "$BUILD_LOG"; then
    cat >&2 <<'EOF'

Detected a likely keychain private-key access failure during codesign.
This is usually not an Xcode account logout: Xcode can be signed in and still have the Apple Development private key blocked for non-interactive codesign.
Fix: run/build the Hermes Agent iOS target once from the Xcode GUI and, if macOS asks whether codesign/Xcode may access the Apple Development key, choose "Always Allow".
If the dialog does not appear, open Keychain Access, find the private key for Apple Development: x@rafaa.com, and allow codesign/Xcode access under Access Control.
EOF
  fi
}

connected_physical_iphone_count() {
  if [[ -n "${HERMES_AGENT_IOS_DEVICE_ID:-}" ]]; then
    printf '1\n'
    return 0
  fi
  local devicectl_count
  devicectl_count="$(xcrun devicectl list devices 2>/dev/null | python3 -c '
import re, sys
count = 0
for line in sys.stdin:
    if "iPhone" in line and "available" in line:
        if re.search(r"[0-9A-Fa-f-]{36}", line):
            count += 1
print(count)
' || true)"
  if [[ "${devicectl_count:-0}" != "0" ]]; then
    printf '%s\n' "$devicectl_count"
    return 0
  fi
  # Keep the literal command below for the source-level contract test.
  xcrun xctrace list devices 2>/dev/null \
    | python3 -c '
import re, sys
count = 0
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
    if re.search(r"\(([0-9A-Fa-f-]{36}|[0-9A-Fa-f-]{24,40})\)", line):
        count += 1
print(count)
'
}

echo "Checking Hermes API LAN readiness for physical iPhone..."
"$ROOT_DIR/scripts/verify_hermes_api_lan.sh"

echo "Creating physical-device bootstrap artifacts..."
"$ROOT_DIR/scripts/create_physical_device_bootstrap_link.sh"

if [[ ! -f "$BOOTSTRAP_HTML" ]]; then
  echo "Expected bootstrap.html artifact missing: $BOOTSTRAP_HTML" >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required to regenerate $PROJECT_NAME" >&2
  exit 1
fi

xcodegen generate >/dev/null

iphone_count="$(connected_physical_iphone_count)"
echo "Connected physical iPhone count: $iphone_count"
if [[ "$iphone_count" == "0" && "$ALLOW_BUILD_WITHOUT_DEVICE" != "1" ]]; then
  echo "No connected physical iPhone detected. Connect/unlock the iPhone, trust this Mac, then rerun." >&2
  echo "Bootstrap HTML is ready: $BOOTSTRAP_HTML"
  echo "To dry-run the generic signed build anyway, set HERMES_AGENT_IOS_ALLOW_GENERIC_DEVICE_BUILD=1." >&2
  exit 2
fi

if [[ -z "$DEVELOPMENT_TEAM" ]]; then
  echo "HERMES_AGENT_IOS_DEVELOPMENT_TEAM is not set; skipping signed physical-device build." >&2
  echo "Set HERMES_AGENT_IOS_DEVELOPMENT_TEAM=<Apple Team ID> to build for device signing." >&2
  echo "Bootstrap HTML is ready: $BOOTSTRAP_HTML"
  exit 3
fi

echo "Building signed generic iOS device artifact..."
set +e
xcodebuild \
  -project "$PROJECT_NAME" \
  -scheme "$SCHEME_NAME" \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  ENABLE_DEBUG_DYLIB=NO \
  -allowProvisioningUpdates \
  build >"$BUILD_LOG" 2>&1
status=$?
set -e

if [[ "$status" -ne 0 ]]; then
  echo "Signed physical-device build failed. Redacted log excerpt:" >&2
  redact_log "$BUILD_LOG" | tail -80 >&2
  print_codesign_keychain_hint_if_needed
  echo "Full build log: $BUILD_LOG" >&2
  exit "$status"
fi

APP_PATH="$(find "$DERIVED_DATA/Build/Products" -path '*iphoneos/*.app' -maxdepth 4 -type d | head -1 || true)"
echo "Signed physical-device build ready."
echo "App artifact: ${APP_PATH:-<not found>}"
echo "Bootstrap HTML: $BOOTSTRAP_HTML"
echo "Next: open bootstrap.html on the physical iPhone, then launch Hermes Agent iOS and verify Hermes /v1/capabilities."

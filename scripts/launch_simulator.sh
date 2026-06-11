#!/usr/bin/env bash
set -euo pipefail

APP_PATH=$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*Build/Products/Debug-iphonesimulator/Hermes Agent iOS.app' -type d | sort | tail -1)
if [[ -z "${APP_PATH}" ]]; then
  echo "Hermes Agent iOS.app not found. Run ./scripts/test_all.sh first." >&2
  exit 1
fi

RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-26-5"
DEVICE_NAME="Hermes Agent iPhone 17"
DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-17"

DEVICE=$(xcrun simctl list devices available | awk -F'[()]' -v name="$DEVICE_NAME" '$0 ~ name {print $2; exit}')
if [[ -z "${DEVICE}" ]]; then
  DEVICE=$(xcrun simctl create "$DEVICE_NAME" "$DEVICE_TYPE" "$RUNTIME")
fi

echo "DEVICE=${DEVICE}"
echo "APP_PATH=${APP_PATH}"

xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl install "$DEVICE" "$APP_PATH"
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ "${HERMES_AGENT_IOS_SKIP_HERMES_BOOTSTRAP:-}" != "1" ]]; then
  "$SCRIPT_DIR/bootstrap_simulator_hermes_api.sh" "$DEVICE"
fi
xcrun simctl launch "$DEVICE" com.tinyleed.hermes-agent-ios

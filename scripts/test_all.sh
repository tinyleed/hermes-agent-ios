#!/usr/bin/env bash
set -euo pipefail

python3 -m unittest discover -s tests -v
python3 scripts/verify_blocking_card_fixtures.py
python3 scripts/smoke_mock_gateway.py
python3 scripts/smoke_blocking_fixture_gateway_ws.py
swift run HermesAgentCoreContractTest
xcodegen generate
xcodebuild \
  -project "Hermes Agent iOS.xcodeproj" \
  -scheme "Hermes Agent iOS" \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build \
  -quiet

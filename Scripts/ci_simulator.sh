#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'Not run: iOS Simulator requires macOS with Xcode.' >&2
  exit 2
fi
mkdir -p artifacts
# Simulator-only identifier, not an Apple registration or production identity.
proof_bundle_id='com.example.nidaa.simulatorproof'
xcodebuild -project NidaaProof.xcodeproj \
  -scheme NidaaProof-Local -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData \
  NIDAA_BUNDLE_ID="$proof_bundle_id" PRODUCT_BUNDLE_IDENTIFIER="$proof_bundle_id" \
  DEVELOPMENT_TEAM='' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' CODE_SIGN_ENTITLEMENTS='' \
  build 2>&1 | tee artifacts/xcodebuild.log

xcrun simctl list devices available -j > artifacts/devices.json
proof_udid="$(python3 Scripts/select_simulator.py artifacts/devices.json)"
cleanup() { xcrun simctl shutdown "$proof_udid" >/dev/null 2>&1 || true; }
trap cleanup EXIT
proof_state="$(python3 - "$proof_udid" <<'PY'
import json, sys
with open('artifacts/devices.json') as f: groups = json.load(f)['devices']
print(next(d['state'] for ds in groups.values() for d in ds if d['udid'] == sys.argv[1]))
PY
)"
if [[ "$proof_state" != Booted ]]; then xcrun simctl boot "$proof_udid"; fi
xcrun simctl bootstatus "$proof_udid" -b
xcrun simctl install "$proof_udid" DerivedData/Build/Products/Debug-iphonesimulator/NidaaProof.app
xcrun simctl launch "$proof_udid" "$proof_bundle_id" | tee artifacts/launch.log
# Allow initial rendering; this is not a notification or interaction test.
sleep 5
xcrun simctl io "$proof_udid" screenshot artifacts/iphone-proof.png
printf '%s\n' 'Simulator launch and screenshot completed. Physical features NOT TESTED.' > artifacts/simulator-result.txt

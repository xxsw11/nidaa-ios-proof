#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo 'Simulator requires macOS'; exit 2; }
mkdir -p artifacts
proof_bundle_id='com.example.nidaa.simulatorproof'
xcrun simctl list devices available -j > artifacts/devices.json
proof_udid="$(python3 Scripts/select_simulator.py artifacts/devices.json)"
cleanup() { xcrun simctl shutdown "$proof_udid" >/dev/null 2>&1 || true; }
trap cleanup EXIT
xcrun simctl boot "$proof_udid" 2>/dev/null || true
xcrun simctl bootstatus "$proof_udid" -b
# UI-test bundle requires a distinct identifier; its target derives .uitests from NIDAA_BUNDLE_ID.
common=(-project NidaaProof.xcodeproj -scheme NidaaProof-Local -sdk iphonesimulator
  -destination "platform=iOS Simulator,id=$proof_udid" -derivedDataPath DerivedData
  ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES NIDAA_BUNDLE_ID="$proof_bundle_id" DEVELOPMENT_TEAM='' CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' CODE_SIGN_ENTITLEMENTS='')
set +e
xcodebuild "${common[@]}" -configuration Debug -parallel-testing-enabled NO \
  -resultBundlePath artifacts/LocalExperience.xcresult test 2>&1 | tee artifacts/xcode-ui-tests.log
test_status=${PIPESTATUS[0]}
set -e
if [[ -d artifacts/LocalExperience.xcresult ]]; then
  xcrun xcresulttool export attachments --path artifacts/LocalExperience.xcresult --output-path artifacts/screenshots || true
  xcrun xcresulttool get test-results summary --path artifacts/LocalExperience.xcresult > artifacts/ui-summary.json || true
fi
[[ "$test_status" == 0 ]] || exit "$test_status"
# Verify Release compilation with all Debug/Simulator authentication bypasses excluded.
xcodebuild "${common[@]}" -configuration Release build 2>&1 | tee artifacts/xcode-release.log
printf '%s\n' 'Local simulation UI tests and Release build completed. No notifications sent. Physical-device validation deferred: no Apple devices.' > artifacts/simulator-result.txt

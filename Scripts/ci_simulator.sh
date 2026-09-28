#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo 'Simulator requires macOS'; exit 2; }
mkdir -p artifacts
# Preserve earlier native evidence outside this invocation's evidence directory.
# xcodebuild requires a new result bundle; a failed run must not inherit old passes.
previous_evidence=".nidaa-simulator-history/$(uuidgen)"
for previous in artifacts/LocalExperience.xcresult artifacts/screenshots artifacts/ui-summary.json \
  artifacts/xcode-ui-tests.log artifacts/xcode-release.log artifacts/simulator-result.txt \
  artifacts/ui-test-names.txt artifacts/ui-selection.txt artifacts/disposable-simulator.txt artifacts/simulator-template.txt; do
  if [[ -e "$previous" ]]; then
    mkdir -p "$previous_evidence"
    mv "$previous" "$previous_evidence/"
  fi
done
proof_bundle_id='com.example.nidaa.simulatorproof'
xcrun simctl list devices available -j > artifacts/devices.json
python3 Scripts/select_simulator.py artifacts/devices.json --template > artifacts/simulator-template.txt
proof_device_type="$(sed -n '1p' artifacts/simulator-template.txt)"
proof_runtime="$(sed -n '2p' artifacts/simulator-template.txt)"
proof_device_name="NIDAA-Disposable-$(uuidgen)"
proof_udid="$(xcrun simctl create "$proof_device_name" "$proof_device_type" "$proof_runtime")"
printf '%s\n' "$proof_device_name" "$proof_udid" "$proof_device_type" "$proof_runtime" > artifacts/disposable-simulator.txt
cleanup() {
  # Only the device created by this invocation is owned by this script.
  xcrun simctl shutdown "$proof_udid" >/dev/null 2>&1 || true
  xcrun simctl delete "$proof_udid" >/dev/null 2>&1 || true
}
trap cleanup EXIT
xcrun simctl boot "$proof_udid" 2>/dev/null || true
xcrun simctl bootstatus "$proof_udid" -b
# UI-test bundle requires a distinct identifier; its target derives .uitests from NIDAA_BUNDLE_ID.
common=(-project NidaaProof.xcodeproj -scheme NidaaProof-Local -sdk iphonesimulator
  -destination "platform=iOS Simulator,id=$proof_udid" -derivedDataPath DerivedData
  ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES NIDAA_BUNDLE_ID="$proof_bundle_id" DEVELOPMENT_TEAM='' CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' CODE_SIGN_ENTITLEMENTS='')
test_selection=()
case "${NIDAA_UI_SUITE:-all}" in
  integration) test_selection=(-only-testing:NidaaUITests/IntegrationUITests) ;;
  local-a|local-b)
    python3 - "$NIDAA_UI_SUITE" > artifacts/ui-test-names.txt <<'PY'
import pathlib, re, sys
names = sorted(re.findall(r'func (test\w+)\(', pathlib.Path('UITests/LocalExperienceUITests.swift').read_text()))
assert len(names) == 17, 'Update explicit UI shard inventory when tests change'
print('\n'.join(names[0 if sys.argv[1] == 'local-a' else 1::2]))
PY
    while IFS= read -r name; do test_selection+=("-only-testing:NidaaUITests/LocalExperienceUITests/$name"); done < artifacts/ui-test-names.txt
    ;;
  all) ;;
  *) echo 'Unknown UI test suite'; exit 2 ;;
esac
printf '%s\n' "UI suite: ${NIDAA_UI_SUITE:-all}" "${test_selection[@]}" > artifacts/ui-selection.txt
set +e
xcodebuild "${common[@]}" -configuration Debug -parallel-testing-enabled NO \
  "${test_selection[@]}" -resultBundlePath artifacts/LocalExperience.xcresult test 2>&1 | tee artifacts/xcode-ui-tests.log
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

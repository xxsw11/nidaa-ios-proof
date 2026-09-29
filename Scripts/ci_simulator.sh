#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo 'Simulator requires macOS'; exit 2; }
proof_evidence="${NIDAA_SIMULATOR_EVIDENCE_DIR:-artifacts}"
case "$proof_evidence" in artifacts|PrivateEvidence/native-review-*) ;; *) echo 'Unexpected evidence directory'; exit 2 ;; esac
mkdir -p "$proof_evidence"
# Preserve earlier native evidence outside this invocation's evidence directory.
# xcodebuild requires a new result bundle; a failed run must not inherit old passes.
previous_evidence=".nidaa-simulator-history/$(uuidgen)"
for previous in "$proof_evidence/LocalExperience.xcresult" "$proof_evidence/screenshots" "$proof_evidence/ui-summary.json" \
  "$proof_evidence/xcode-ui-tests.log" "$proof_evidence/xcode-release.log" "$proof_evidence/simulator-result.txt" \
  "$proof_evidence/ui-test-names.txt" "$proof_evidence/ui-selection.txt" "$proof_evidence/disposable-simulator.txt" "$proof_evidence/simulator-template.txt"; do
  if [[ -e "$previous" ]]; then
    mkdir -p "$previous_evidence"
    mv "$previous" "$previous_evidence/"
  fi
done
proof_bundle_id='com.example.nidaa.simulatorproof'
xcrun simctl list devices available -j > "$proof_evidence/devices.json"
python3 Scripts/select_simulator.py "$proof_evidence/devices.json" --template > "$proof_evidence/simulator-template.txt"
proof_device_type="$(sed -n '1p' "$proof_evidence/simulator-template.txt")"
proof_runtime="$(sed -n '2p' "$proof_evidence/simulator-template.txt")"
proof_device_name="NIDAA-Disposable-$(uuidgen)"
proof_udid="$(xcrun simctl create "$proof_device_name" "$proof_device_type" "$proof_runtime")"
printf '%s\n' "$proof_device_name" "$proof_udid" "$proof_device_type" "$proof_runtime" > "$proof_evidence/disposable-simulator.txt"
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
    python3 - "$NIDAA_UI_SUITE" > "$proof_evidence/ui-test-names.txt" <<'PY'
import pathlib, re, sys
names = sorted(re.findall(r'func (test\w+)\(', pathlib.Path('UITests/LocalExperienceUITests.swift').read_text()))
assert len(names) == 17, 'Update explicit UI shard inventory when tests change'
print('\n'.join(names[0 if sys.argv[1] == 'local-a' else 1::2]))
PY
    while IFS= read -r name; do test_selection+=("-only-testing:NidaaUITests/LocalExperienceUITests/$name"); done < "$proof_evidence/ui-test-names.txt"
    ;;
  autofill) test_selection=(-only-testing:NidaaUITests/AutoFillUITests) ;;
  live) test_selection=(-only-testing:NidaaUITests/NativeIntegrationUITests) ;;
  all) test_selection=(-skip-testing:NidaaUITests/NativeIntegrationUITests) ;;
  *) echo 'Unknown UI test suite'; exit 2 ;;
esac
printf '%s\n' "UI suite: ${NIDAA_UI_SUITE:-all}" "${test_selection[@]}" > "$proof_evidence/ui-selection.txt"
set +e
xcodebuild "${common[@]}" -configuration Debug -parallel-testing-enabled NO \
  "${test_selection[@]}" -resultBundlePath "$proof_evidence/LocalExperience.xcresult" test 2>&1 | tee "$proof_evidence/xcode-ui-tests.log"
test_status=${PIPESTATUS[0]}
set -e
if [[ -d "$proof_evidence/LocalExperience.xcresult" ]]; then
  xcrun xcresulttool export attachments --path "$proof_evidence/LocalExperience.xcresult" --output-path "$proof_evidence/screenshots" || true
  xcrun xcresulttool get test-results summary --path "$proof_evidence/LocalExperience.xcresult" > "$proof_evidence/ui-summary.json" || true
fi
[[ "$test_status" == 0 ]] || exit "$test_status"
# Verify Release compilation with all Debug/Simulator authentication bypasses excluded.
xcodebuild "${common[@]}" -configuration Release build 2>&1 | tee "$proof_evidence/xcode-release.log"
printf '%s\n' 'Local simulation UI tests and Release build completed. No notifications sent. Physical-device validation deferred: no Apple devices.' > "$proof_evidence/simulator-result.txt"

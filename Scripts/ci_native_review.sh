#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
suite="${1:?Choose integration, autofill or live}"
case "$suite" in integration|autofill|live) ;; *) exit 2 ;; esac
private_evidence="PrivateEvidence/native-review-$suite-$(uuidgen)"
mkdir -p "$private_evidence"
chmod 700 "$private_evidence"
export NIDAA_SIMULATOR_EVIDENCE_DIR="$private_evidence"
export NIDAA_UI_SUITE="$suite"
if [[ "$suite" == live ]]; then
  : "${NIDAA_FIXTURE_CAPABILITY:?Live suite requires the private runtime fixture}"
  # Apple documents TEST_RUNNER_ forwarding to the runner, not the tested app.
  export TEST_RUNNER_NIDAA_FIXTURE_CAPABILITY="$NIDAA_FIXTURE_CAPABILITY"
fi
# Raw XCTest logs/recordings can contain typed credentials. They never reach CI
# stdout or published artifacts. Only the allowlisted export below is published.
set +e
bash Scripts/ci_simulator.sh > "$private_evidence/driver-private.log" 2>&1
status=$?
set -e
python3 Scripts/export_native_review.py "$private_evidence" "$suite" "$status"
exit "$status"

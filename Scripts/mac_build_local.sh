#!/bin/bash
set -eu
cd "$(dirname "$0")/.."
if [ "$(uname -s)" != Darwin ]; then echo "Not tested: Xcode requires macOS."; exit 2; fi
if [ ! -f Config/Developer.xcconfig ]; then echo "Set your own Bundle ID and Team in Config/Developer.xcconfig first."; exit 2; fi
swift test --package-path ProofCore
# Compile only, without installing or notifying a device. No account changes are permitted by this script.
xcodebuild -project NidaaProof.xcodeproj -scheme NidaaProof-Local -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build

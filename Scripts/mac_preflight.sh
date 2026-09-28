#!/bin/bash
set -eu
cd "$(dirname "$0")/.."
if [ "$(uname -s)" != Darwin ]; then echo "Not tested: macOS is required."; exit 2; fi
sw_vers
xcode-select -p
xcodebuild -version
xcrun --find swift
plutil -lint App/Info.plist Config/APNs.entitlements NidaaProof.xcodeproj/project.pbxproj
xcodebuild -list -project NidaaProof.xcodeproj
# Read-only device inventory. No installation, notification or sound.
xcrun devicectl list devices
echo "Local signing inventory (do not share raw output publicly):"
security find-identity -v -p codesigning
echo "Stop here if device/window confirmation is missing. No notification has been requested."

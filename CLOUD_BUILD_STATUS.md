# Cloud verification — native local experience

Current branch: `codex/native-local-experience`, based on latest inspected main `113fc4daf93f6ee7400e08976b2bd7369ad13580`.

## Current verification

[Second run](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36368817158), source `c8386b7ccf2cca91667e219ec2fd9c7d47494dab`: Passed: 13 Python tests, 30 Swift core tests on macOS, 8 XCTest UI tests on iPhone 16 Pro / iOS 18.5 Simulator, and Release build. Xcode 16.4 / Swift 6.1.2 on macOS 15.7.9. All 18 screenshots reviewed. Found and corrected a stale silence message after closure and added a screenshot animation wait; final refinement verification is next.

[First run](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36368351156), source `0ff422da4af5c0805e401d2640d88c60908371d1`: 13 Python and 30 Swift tests passed; iOS test build failed before UI execution because the app requested x86_64 and arm64 while its local Swift package produced the active arm64 slice. Fixed the simulator invocation to use the runner architecture consistently. Also corrected Arabic appearance-mode encoding and tightened fresh-auth clock handling before the second run.

## Previous source-preparation stage

[Run 36365231025](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36365231025), source `7064472506873bab449449921f1d129b308793b9`, passed 8 Python and 10 Swift tests, built and launched the previous technical proof using Xcode 16.4 / SDK 18.5. That previous screenshot was a technical screen, not this new interface.

## Evidence boundaries

Standard public `macos-15` runner. Swift core tests execute on macOS; XCTest UI runs on iPhone Simulator. Release is compiled after UI success. Screenshots must come from XCTest attachments and be reviewed before claiming visual acceptance. Artifact retention is seven days; retain local copies for the delivery.

No notification, APNs send, real biometric hardware, physical iPhone, sound routing, Bluetooth, flashlight, silent-mode bypass or Critical Alert is tested. Physical testing is deferred because no Apple devices are available, and is not a prerequisite for this stage. Debug Simulator authentication is explicitly simulated.

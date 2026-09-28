# Cloud verification — complete local stage

Final executable source: `0412c2404bb4bcce3ed462504d93689264aef0a7`.
[Verified run 36370598960](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36370598960) — **Passed** on 2026-09-28.

| Check | Actual result |
|---|---|
| Python packaging and offline-payload tests on runner | 13 passed |
| Swift core tests on macOS | 30 passed, zero failures |
| XCTest UI on iPhone 16 Pro / iOS 18.5 Simulator | 8 passed, zero failures/skips |
| Debug app and UI-test build | Passed |
| Release app build | Passed |
| Native screenshots reviewed | 22 original XCTest PNGs; see QA/NATIVE_VISUAL_REVIEW.md |

Environment: standard public macos-15 runner, macOS 15.7.9, Xcode 16.4, Swift 6.1.2, iPhoneSimulator SDK 18.5, arm64. No signing account or secrets. AppIntents metadata and XCTest support-library stripping warnings are nonblocking; no AppIntents feature was added.

The later delivery commit updates documentation, the inventory and local QA records only; executable app, project, tests, scripts and configuration remain identical to the tested commit above. No extra runtime success is inferred from documentation changes.

Physical iPhone validation is deferred because no Apple devices are available. No notification was sent. APNs, real biometric hardware, audio/Bluetooth, Focus, silent-mode bypass, flashlight and Critical Alerts remain untested/not enabled. Debug Simulator authentication is simulated and clearly labeled.

Artifacts are retained for seven days on GitHub; delivery includes original screenshots and relevant logs locally. Screenshots are exported from XCTest, renamed without pixel changes, and have recorded SHA-256 values in the delivery provenance file.

## Earlier attempts and preparation history

### Earlier native-stage record

Current branch: `codex/native-local-experience`, based on latest inspected main `113fc4daf93f6ee7400e08976b2bd7369ad13580`.

## Current verification

[Third run](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36369819686), source `857cf53cabca64fc4ac5bac9ef3fabc28876421c`: Passed (13 Python, 30 Swift, 8 iOS UI, Release build). Reviewed its refined screenshots; status-bar overlap during large-text scrolling and light-preview corner clipping prompted a final focused layout correction and new evidence capture.


[Second run](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36368817158), source `c8386b7ccf2cca91667e219ec2fd9c7d47494dab`: Passed: 13 Python tests, 30 Swift core tests on macOS, 8 XCTest UI tests on iPhone 16 Pro / iOS 18.5 Simulator, and Release build. Xcode 16.4 / Swift 6.1.2 on macOS 15.7.9. All 18 screenshots reviewed. Found and corrected a stale silence message after closure and added a screenshot animation wait; final refinement verification is next.

[First run](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36368351156), source `0ff422da4af5c0805e401d2640d88c60908371d1`: 13 Python and 30 Swift tests passed; iOS test build failed before UI execution because the app requested x86_64 and arm64 while its local Swift package produced the active arm64 slice. Fixed the simulator invocation to use the runner architecture consistently. Also corrected Arabic appearance-mode encoding and tightened fresh-auth clock handling before the second run.

## Previous source-preparation stage

[Run 36365231025](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36365231025), source `7064472506873bab449449921f1d129b308793b9`, passed 8 Python and 10 Swift tests, built and launched the previous technical proof using Xcode 16.4 / SDK 18.5. That previous screenshot was a technical screen, not this new interface.

## Evidence boundaries

Standard public `macos-15` runner. Swift core tests execute on macOS; XCTest UI runs on iPhone Simulator. Release is compiled after UI success. Screenshots must come from XCTest attachments and be reviewed before claiming visual acceptance. Artifact retention is seven days; retain local copies for the delivery.

No notification, APNs send, real biometric hardware, physical iPhone, sound routing, Bluetooth, flashlight, silent-mode bypass or Critical Alert is tested. Physical testing is deferred because no Apple devices are available, and is not a prerequisite for this stage. Debug Simulator authentication is explicitly simulated.

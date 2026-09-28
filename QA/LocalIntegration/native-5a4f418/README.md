# Native verification evidence

Source `5a4f418b81b54ed69757d342965100ecf41e8598`. [Successful run](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36454477295).

All 25 unique UI journeys passed: integration 8, local-a 9, local-b 8; zero skips/failures. Each shard built Debug and Release and passed 45 core Swift, 19 client Swift and 13 Python tests. Repeated package tests are not counted as additional unique tests.

Passing integration and local-a evidence comes from attempt 1; local-b evidence comes from its same-source attempt 2 rerun. The original local-b runner was killed during bootstrapping before any UI test started. That infrastructure failure is retained in attempt-history.json and is not counted as a passing execution. Per-artifact attempt/job IDs are recorded in provenance.json.

The new integration UI uses an explicitly labeled mock. Actual Swift/backend evidence runs separately on Linux. No physical-device or Simulator/backend end-to-end claim is made.

The script creates and removes its own disposable Simulator. The integration suite opens native Settings, disables password AutoFill and verifies the actual switch off before manual credential entry. The fixture screenshot is retained. Tests refuse physical devices or Simulators without the disposable name prefix. AutoFill-enabled credential entry remains unproven: earlier cloud runs encountered Apple's strong-password cover view. Correct password field semantics and credential assertions remain intact.

Original summaries and environment/selection records are copied unchanged. Full build/test logs and original inspected screenshots are in the delivery package's Evidence and Screenshots directories; raw xcresult archives remain in GitHub artifacts during their retention period. See provenance.json for archive hashes and devices. Visual findings are in ../VISUAL_REVIEW.md.

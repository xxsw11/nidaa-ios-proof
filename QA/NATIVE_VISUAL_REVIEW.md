# Stabilization Simulator visual review

Executable source: `8edd1385b118f01e266ee5c1633d33c201a26be4`. [Final run](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36381069313). iPhone 16 Pro / iOS 18.5 Simulator; 1206 × 2622 original XCTest PNGs. All 31 final images listed in stabilization-results.json were actually opened. The original 22 captures from the prior delivery were available; the final run recaptures those views and adds 9 stabilization views. Original image bytes are preserved in the delivery; no generated mockups or retouching.

Reviewed Arabic shaping and RTL alignment, fictional names and matching initials, light/dark contrast, large-text navigation, scrolling, and clear differences among simulated sending, receipt, opening, human response, silence and explicit resolution. The final captures cover restored response history, eligible retry recipients, recipient addition and restoration, expiry while closed, failed-save rollback, corrupt storage, reset, and the large-text confirmation action.

Corrections established during this stage:

- The root storage-error banner now occupies its own layout space rather than overlapping the home content.
- Failed saves preserve review details, disable another authorization while storage is unavailable, and retain the prior persisted attempt count.
- A historical nonresponse event no longer displays a current alternative-recipient prompt after expiry or a human response.
- The large-text confirmation capture is scrolled to show the action; UI testing verifies it remains reachable. The large-text home action is also exercised after scrolling.

No blocking visual finding remained in the reviewed final screenshots. Long pages and Accessibility XXXL views extend beyond one viewport; partially visible content at the top or bottom of a scrolled image is not evidence that the entire page fits onscreen. Disabled-control appearance is intentional. This is a visual review plus Simulator navigation tests, not a full VoiceOver audit or physical-device verification. Quantitative color calculations are covered separately by the core tests. System notification permission was not requested by the tests.

## Previous-stage review retained as history

# Native simulator visual review

Source: `0412c2404bb4bcce3ed462504d93689264aef0a7`. Run: https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36370598960. Device: iPhone 16 Pro, iOS 18.5 Simulator, arm64. Captures: 1206 × 2622 PNG, exported from XCTest attachments. No generated mockups or edited pixels.

Reviewed 22 captures: home; selection; deliberate confirmation; outgoing; incoming; explicit response; terminal event timeline; history; trusted circle; dark appearance; terms; privacy; readiness; protected incoming; home/selection/settings/appearance at Accessibility XXXL; scrolled large-text action; persisted custom button color; light palette preview; normal settings.

Observed Arabic shaping and RTL alignment, fictional Sara with initial س, readable light/dark foregrounds, separate receipt/open/response states and protected incoming details. Long content remains vertically scrollable; a viewport image does not contain the entire page. Large-text navigation remained operable in XCTest. Color contrast calculations are separately unit-tested.

Corrections made after reviewing earlier runs: stale silence feedback after closure, transitional screenshots, oversized modal navigation titles, avatar scaling, large-text scroll content behind the home status bar, and light-preview corner clipping. The final run includes these corrections and rechecks all eight UI journeys.

These are simulator observations, not a complete VoiceOver audit or physical-device, sound, APNs or notification-delivery evidence. Permission settings were read; the test did not press the system permission request.

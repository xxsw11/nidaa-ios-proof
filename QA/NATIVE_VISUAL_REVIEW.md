# Native simulator visual review

Source: `0412c2404bb4bcce3ed462504d93689264aef0a7`. Run: https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36370598960. Device: iPhone 16 Pro, iOS 18.5 Simulator, arm64. Captures: 1206 × 2622 PNG, exported from XCTest attachments. No generated mockups or edited pixels.

Reviewed 22 captures: home; selection; deliberate confirmation; outgoing; incoming; explicit response; terminal event timeline; history; trusted circle; dark appearance; terms; privacy; readiness; protected incoming; home/selection/settings/appearance at Accessibility XXXL; scrolled large-text action; persisted custom button color; light palette preview; normal settings.

Observed Arabic shaping and RTL alignment, fictional Sara with initial س, readable light/dark foregrounds, separate receipt/open/response states and protected incoming details. Long content remains vertically scrollable; a viewport image does not contain the entire page. Large-text navigation remained operable in XCTest. Color contrast calculations are separately unit-tested.

Corrections made after reviewing earlier runs: stale silence feedback after closure, transitional screenshots, oversized modal navigation titles, avatar scaling, large-text scroll content behind the home status bar, and light-preview corner clipping. The final run includes these corrections and rechecks all eight UI journeys.

These are simulator observations, not a complete VoiceOver audit or physical-device, sound, APNs or notification-delivery evidence. Permission settings were read; the test did not press the system permission request.

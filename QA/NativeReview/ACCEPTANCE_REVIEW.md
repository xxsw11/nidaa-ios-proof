# Integration acceptance follow-up

Scope: close the three requested acceptance blockers, without new application features. PR4 depends on PR3, which depends on PR2. Preserve historical deliveries and local authoring changes. No automatic merge.

## Saved native credential selection

The previous run36525193498 top crop cannot identify the system surface below the header. It remains historical failed evidence, not proof of an unsupported Simulator.

At4bb8b1244ee580dd280620737504323dcafdf513, run36539142321, the full redacted screen and complete sanitized accessibility trees were inspected for before-tap, after-tap and selection-failure phases. Before tap the native Passwords accessory is present. Immediately after tapping, the keyboard disappears and the empty NIDAA form remains visible; the app accessibility tree collapses to14 empty ancestor nodes. By the bounded selection failure, the keyboard and Passwords accessory return. No stable saved-account chooser or personal-account/passcode requirement is observed. Extending the selector wait is not justified by these observations.

At053de1c3113a88050e57906c186e415a59d055d9, run36541295372, the fictional entry was found after terminating and relaunching Passwords. The global AutoFill switch was actually On. Provider control presence was observed, but its enabled state remained unknown. All three full redacted screens were inspected and showed the same transient behavior. Test result:0 passed,1 failed,0 skipped; Release build passed. Thus the failure is not explained by an unsaved entry or a disabled global switch. Product-vs-system ownership is still unresolved at this diagnostic checkpoint.

The system diagnostic collector exited its collection command with0 but failed before completing encryption. No plaintext log was uploaded. This is a separate diagnostic tooling failure, not evidence that the picker is unsupported. The next bounded diagnostic narrows process capture and records fixed failure stage/category and byte count. A concrete crop-helper defect was corrected: it previously stopped on the first existing provider candidate even when its image gate rejected that candidate. It now continues until a crop is emitted, uses the Settings window bounds and records numeric geometry. No provider switch is changed and no app behavior is altered on speculation.

All selection/fill/login assertions remain. Manual input, paste, and visibility tests with AutoFill enabled have separate meanings. A saved-selection skip leaves acceptance unpassed. Fresh disposable Simulators and fictional credentials are used; no personal Apple account is requested.

## Native interface with real backend

At0c12b736a623f0da700e22fa9a0cbd18b154010d, run36539307560, the changed candidate removed the explicit bind grant and was tested once with a deny-all control. For both IPv4 and IPv6, external TCP/UDP were policy denied and loopback worked, but wildcard TCP/UDP binding and explicit/implicit TCP listening succeeded. Candidate Failed; deny-all control Passed. No credentials, preparation or services were started. This demonstrates the configured policy boundary is insufficient on the measured runner, without claiming external reachability or a universal macOS limitation.

The runner reported VZVirtualMachine.isSupported=false; Docker/Colima/Podman were absent; kern.hv_support was unavailable. No working container/VM alternative was established. The known failed policy is not retried, relaxed or replaced by a flow filter. Native UI E2E and its two prepared journey/fault tests remain **Not executed due to environment**. Real Linux backend/SDK tests are independent and cannot substitute for native UI E2E. Local mail and fake notification delivery are not APNs.

The prepared runtime gate now shares the strict14-check classifier with the probe, covering external TCP/UDP denial, wildcard TCP/UDP bind denial, implicit wildcard listen denial, and TCP/UDP loopback success in each family. Missing observations, timeouts, refusal, unsupported families and non-boolean values fail closed. Six pure/mock regression tests verify this contract without network operations. The active profile remains blocked. See NATIVE_ENVIRONMENT.md for the exact continuation commands and minimum supported environment.

## Unified-source validation

Pending the final diagnostic, the full regression marker selects backend55, reference45, QA20, Swift client24 plus real SDK journey, Swift Core45, local UI9+8, MOCK UI8 and AutoFill4. Every job records its exact checkout/event SHA. The final results must name one source and retain failed/skipped/not-executed outcomes; historical successes above are not a unified acceptance result.

Private XCTest recordings/logs and generated credentials are excluded. Full transient picker screenshots are encrypted before CI upload because an accessibility snapshot and a later screenshot are not atomic. Only images actually opened and reviewed locally may enter the inspected delivery set, with hashes and provenance. Public trees contain fixed allowlisted labels and numeric geometry only.

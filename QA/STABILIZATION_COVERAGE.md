# Stabilization coverage map

This maps acceptance criteria to tests; successful execution is recorded separately in CLOUD_BUILD_STATUS.md. A listed test is not by itself a passing result.

| Requirement | Core coverage | Actual application / SwiftUI coverage |
|---|---|---|
| Preserve ID, type, direction, times, states, silence and events | Round-trip archive equality, including incoming and outgoing | Terminate/relaunch after explicit response and silence; inspect same ID and response; retry and relaunch again |
| Expire while closed; never reopen terminal | Restore expiry once; cancelled/resolved/expired with clock rollback | Relaunch with a controlled test clock, then relaunch with normal clock; resolved alert also remains terminal |
| Atomic storage, versioning, migration | Real Foundation file I/O; v1 migration write failure preserves bytes; v2 round trip | Real application repository path is used by all UI journeys |
| Corruption and I/O failure | Invalid JSON, future schema, inconsistent records, injected read/write failures, failed reset | Read failure retains saved alert; failed retry save keeps attempt count; corruption stays blocked until explicit reset |
| Reset and isolation | Independent real temporary directories; explicit reset persists clean state | Reset then terminate/relaunch; ordinary application launch cannot see UI-test history; UI-test history still exists |
| No restored auth capability | Archive excludes capability fields; fresh gate rejects execution | Terminate at confirmation and relaunch: both actions require fresh authentication |
| Fresh auth and explicit confirmation for both actions | Failure/success, single-use, mismatched action/alert/recipients | Retry and addition success; failure/cancellation; cancel review; repeat confirmation tap |
| Expiry and changed consent | 15-second boundary, clock rollback, expired alert, deletion/block/consent/name changes | Confirmation timeout; block/consent withdrawal/deletion through store while test authentication is pending |
| Background / app lock | Explicit gate invalidation | Home button during pending authentication for both actions; existing protected-incoming / app-lock journey |
| Retry excludes human responses | Responded/declined recipients excluded; ID, states and timestamps retained; empty eligible set rejected | Sara responds; retry review includes only Ahmad; attempt increments once and persists |
| Addition preserves original alert | Old recipients, deadline and attempts unchanged | New consenting recipient appears after confirmation and survives relaunch under same ID |
| Arabic, RTL, contrast, large text | Existing contrast tests | Baseline screenshots regenerated; new action review and storage/restoration captures; large-text action exercised |

Test-only authentication outcomes, faults and clock offsets are compiled only in Debug Simulator and require the explicit UI-test launch flag. The ordinary Debug Simulator supports a clearly labeled manual simulated authentication option. Release and physical devices have no simulated authentication path.

No test schedules or delivers system notifications. Biometric hardware, iOS data protection on locked physical hardware, sound, APNs, Bluetooth and silent-mode behavior remain untested.

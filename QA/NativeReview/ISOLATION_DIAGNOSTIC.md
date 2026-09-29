# Precredential isolation diagnostic

`Integration/native/isolation_diagnostic.py` is a separate measurement under the existing sandbox profile. It does not replace or modify the runtime gate. It starts no backend, reads no credentials, sends no application payload, and prints only fixed labels, status values and numeric error codes.

The diagnostic records wildcard IPv4/IPv6 socket creation, address binding and listening separately. After each listen attempt the socket is closed immediately, without accepting a connection. A successful wildcard listen is recorded as `succeeded`; it is **not** interpreted as safe or as a passed isolation check. Failure to create/bind leaves later stages `not_attempted`. Only EPERM/EACCES counts as `policy_denied`; refusal, timeout and unsupported address families remain `other_error` and do not prove enforcement.

Context checks exercise external TCP connect and an empty UDP datagram to the documentation address 192.0.2.1, plus a payload-free loopback TCP connection. These mirror the existing probe's context. Exit zero means only that the diagnostic produced its observations; there is intentionally no overall pass field. Producing this report alone does not establish isolation or justify a full runtime retry; resolve and verify the concrete boundary first within the already authorized trial scope.

Apple's [bind documentation](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/bind.2.html) describes assigning a socket address, while [listen documentation](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/listen.2.html) describes enabling incoming connections. Apple's [XNU socket system calls](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/uipc_syscalls.c) independently invoke `mac_socket_check_bind`, `mac_socket_check_listen` and `mac_socket_check_accept`; the [MAC implementations](https://github.com/apple-oss-distributions/xnu/blob/main/security/mac_socket.c) dispatch separate policy checks. Therefore bind success alone cannot establish that wildcard listening is permitted. These primary sources justify measuring the missing stage; they do not prove the runner's actual Seatbelt result.

Local validation: Python compilation only. Runtime observations belong to the standalone macOS diagnostic job and must be recorded against its actual commit/run. No macOS behavior is claimed from Windows.

## Actual standalone observation

At031ffd5f5177b41fa2717409ac15a7e50ad8b4fa, [run36516431643 attempt1](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36516431643) produced the original report preserved under `evidence/isolation-031ffd5`. Both IPv4 and IPv6 wildcard `bind` **and `listen` succeeded**. External TCP/UDP returned EPERM; loopback succeeded. The workflow success means diagnostic collection succeeded, not that isolation passed. The configured profile does not prevent wildcard listening. No accept or external-reachability claim is made. No credentials, database, backend or full setup retry occurred. The runtime remains gated; further unchanged attempts are stopped.

## Bounded stricter candidate — not yet a runtime configuration

The renewed blocker-closing scope adds `isolation_candidate.py`, `loopback-inbound-candidate.sb` and `network-deny-control.sb`. The candidate removes the explicit bind grant and retains filtered inbound/outbound permissions; the control denies all networking. This deliberately tests whether separate bind/inbound authorization behaves differently on the actual runner. It does not assume that removing a grant will preserve loopback. The primary [Bazel implementation review](https://github.com/bazelbuild/bazel/pull/30865) documents both the distinction between bind and inbound permission and the broad meaning of the `localhost` selector. Its descriptions are not a guarantee of behavior on this runner. Apple XNU's separate checks above supply the OS-level basis for measuring these operations independently.

This is one changed candidate and one negative control, without repeating the failed baseline. Literal-address syntax is not retried after the recorded parser rejection. A fixed-port allowlist would not meet the boundary if wildcard binding at those ports remained possible. Packet filtering is not substituted for bind/listen policy denial. NetworkExtension is not assumed available: Apple's [configuration requirements](https://developer.apple.com/documentation/xcode/configuring-network-extensions/) involve capabilities and signing, and its [socket filter setting](https://developer.apple.com/documentation/networkextension/nefilterproviderconfiguration/filtersockets) concerns network flows rather than promising these syscall denials.

Run on the native macOS runner, **before dependency preparation or credentials**:

```sh
python3 Integration/native/isolation_candidate.py --output artifacts/isolation-candidate/report.json
```

Exit 0 requires both the candidate and negative control to satisfy their assertions. Exit 3 records a failed/incomplete boundary; no runtime fallback occurs. Each profile runs once with a 20-second process timeout and one-second socket timeouts. Every family must prove external TCP and empty UDP policy denial, wildcard TCP and UDP bind denial, and implicit wildcard listen denial. A denied explicit bind leaves its follow-up listen unattempted; a separate unbound-socket `listen()` catches implicit binding. Both TCP and empty-datagram UDP loopback exchanges must succeed for the candidate and be policy-denied in the control. A successful wildcard bind is always failure, even if later listening is denied. Only EPERM/EACCES qualifies as policy denial; timeout, refusal, missing IPv6 and parser failure do not pass.

The report includes exact profile/probe hashes, coarse platform data and all observations. Capabilities are read independently: `kern.hv_support`, the actual [`VZVirtualMachine.isSupported`](https://developer.apple.com/documentation/virtualization/vzvirtualmachine/issupported) framework query, and presence of container commands. Command presence is explicitly not proof of a usable container runtime, and the framework boolean is not proof of nested-VM boot. No daemon, VM, privileged firewall, service or backend is started. Children receive a minimal temporary environment without inherited credentials. The active `loopback.sb`, existing probe and runtime remain unchanged until empirical evidence justifies a reviewed replacement.

Windows validation for these additions was compilation plus pure result-classifier checks. The actual macOS result below ends this candidate; independent UI/export work continues.

## Actual stricter-candidate result

At commit `0c12b736a623f0da700e22fa9a0cbd18b154010d`, [run 36539307560 attempt 1](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36539307560), job `109310637268`, the candidate **Failed** on macOS 15.7.9 arm64. The deny-all control **Passed**, including denial of loopback. The candidate produced these identical results for IPv4 and IPv6:

| Operation | Actual result |
|---|---|
| External TCP connect / empty UDP send | Policy denied, EPERM (1) |
| Wildcard TCP bind / explicit listen | Succeeded / succeeded |
| Wildcard UDP bind | Succeeded |
| Unbound-socket implicit wildcard listen | Succeeded |
| Loopback TCP / empty UDP exchange | Succeeded / succeeded |

The changed policy's filtered inbound grant still permits wildcard binding and listening on this runner. Removing the explicit bind grant did not close the boundary. Both profiles were measured once, without credentials, backend preparation or a service start. Wildcard sockets were closed immediately; the result does not claim externally accepted connections or remote reachability. No further trial of these unchanged policies is warranted.

Observed capability results: `VZVirtualMachine.isSupported` was false; `kern.hv_support` was unavailable (`null`); Docker, Colima and Podman commands were absent. This establishes no usable virtualization/container fallback in the measured environment; command absence alone does not prove all possible alternatives impossible. No VM boot or container installation was attempted. No supported, available alternative was identified that satisfies actual wildcard bind/listen denial while allowing both loopback families. Network flow filtering, a fixed-port exception, application binding configuration, or syscall interception is not treated as equivalent evidence.

The active profile remains unchanged and blocked. After this failed run, the prepared `isolation_probe.py` and `runtime.py` were strengthened to require the complete matrix through one shared 14-key contract in `isolation_candidate.py`, with a 20-second timeout. Both candidate classification and the runtime require the same policy-denial/success rules; missing keys, non-boolean values and incomplete observations fail closed. The six local `QA/test_isolation_gate.py` regressions passed without opening sockets. This closes a prepared-script gap; it is not another macOS run or evidence of a working policy. Before any future service attempt, a reviewed replacement mechanism must pass the full gate under the identical profile used by services. The minimum unresolved requirement is an available Mac runner with that verified mechanism; it is not a general inability of macOS to run Auth/PostgreSQL.

# Actual backend and Swift-client evidence

Source commit: `528b9535fbb7f1b229bb0efa0724572f7262cf6c`.
[Successful run 36434112612](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36434112612), 2026-09-28.

47 actual GoTrue/HTTP/PostgreSQL integration tests, 45 reference regressions, 13 existing Python checks and 19 Swift client unit tests passed. The official Swift Auth client then completed its live A/B/C/B2 journey over the isolated gateway and local inbox. `swift-integration.log` records each coarse stage without credentials. It is not a Simulator/backend or physical-phone test.

Original artifact ID: 10975500706. ZIP SHA-256: `699990c1bfbba7aea2c11157f8eb4785b3d4a20f2258d482071428ae58a1b763`. Logs and version/isolation files are copied unchanged. No mailbox, database dump, runtime environment or raw credential is included.

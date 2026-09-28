# NIDAA shared rules — isolated reference

This Python model simulates shared identity/consent/alert rules. It has **no network transport, production authentication, provider SDK, database, email, SMS or push sender**. Fixture sessions stand in for trusted, provider-verified sessions. Nothing here is linked into the iOS application.

From the repository root, use Python 3.12 in a disposable virtual environment:

```sh
python -m venv /tmp/nidaa-rules
/tmp/nidaa-rules/bin/python -m pip install -r SharedRules/requirements-test.txt
/tmp/nidaa-rules/bin/python -m unittest discover -s SharedRules/tests -v
python -m unittest discover -s QA -p 'test_*.py' -v
swift test --package-path ProofCore
```

On Windows use a workspace virtual environment and its `Scripts/python.exe`; Swift tests require a supported Swift environment. The test dependencies are pinned and isolated; no dependencies were added to the iOS application. Installing the test validator downloads packages, but running these tests makes no external service calls.

`build_contract.py` deterministically writes `contract.schema.json`, the canonical wire boundary. Committed output is checked for drift. JSON Schema Draft 2020-12 validates actual command inputs, receipts, alert views, errors and empty/full synchronization results. References are not used, so the validator never fetches schemas. Unknown properties, invalid formats, nulls where forbidden, duplicate recipients and undocumented enums fail closed. No generated production clients are claimed.

The rule model serializes mutations with an in-process lock and rollback snapshots. Tests establish deterministic orderings, **not database isolation, cryptographic correctness, rate-limit resistance under distributed load or communication between devices**. The two-device fixtures are two session records in one process. Time is an injected integer UTC clock; never use its initial value as a real event timestamp.

Read [design](../Docs/IdentitySync/DESIGN.md), [API](../Docs/IdentitySync/API.md), [provider comparison](../Docs/IdentitySync/PROVIDERS.md), and [stage status](../IDENTITY_SYNC_STATUS.md) before implementation. The next trial must replace fixture authentication and transactions with real local provider components behind the same contract.

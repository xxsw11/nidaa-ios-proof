# Frozen Swift integration API

Module/product `NidaaIntegration`; Swift tools 6.1. Official dependency `supabase-swift` **2.55.2**, product **Auth** only. Executable target/product `IntegrationTrialCLI`; test target `NidaaIntegrationTests`. The CLI/tests are owned separately from this library. No service/admin key is required by the isolated GoTrue gateway or included in the app.

## Construction

```swift
let environment = try TrialEnvironment(baseURL: URL(string: "http://127.0.0.1:55421")!)
let client = try NidaaClient.live(environment: environment) // Apple: Keychain
```

Apple configuration permits only literal loopback/localhost HTTP(S), without credentials, URL query, fragment or path. HTTP is an explicit isolated-local exception, not a production configuration. Linux tests can explicitly use `try TrialEnvironment.isolatedLinux(baseURL:)` for the fixed private Docker `http://gateway:8080` endpoint. Other external/LAN endpoints fail construction. Requests cannot follow redirects; official Auth requests must retain the configured origin.

For tests/CLI use `NidaaClient(environment:storage:transport:now:)`. `storage` is a `ClientStorage`; `MemoryClientStorage()` is explicitly ephemeral, never the Apple live default. `transport` defaults to `URLSessionTransport()`; `now` defaults to `Date()` and is an injectable `@Sendable () -> Date` closure. `HTTPTransport.send(_ request: URLRequest) async throws -> HTTPResult` enables controlled delayed/error responses without changing the client logic. `HTTPResult(status:body:)` uses an integer status and Data body.

`ClientStorage` has synchronous throwing `get(_ key: String) -> Data?`, `set(_ key: String, data: Data)`, `remove(_ key: String)`, `removeAll()`. Implementations are Sendable. The client scopes an underlying store to its environment, then binds pending operations to the internal account UUID. Keychain uses device-only, when-unlocked accessibility and no iCloud synchronization. Auth and pending data are never placed in UserDefaults. Do not concurrently construct multiple live clients over the same environment store; one app integration session owns it. Independent test clients use independent memory stores.

## UI/mock protocol

All members of `NidaaClientProtocol` are async (actor implementations may omit async on methods without suspension):

```swift
signup(email: String, password: String) async throws
signIn(email: String, password: String) async throws -> Account
verify(tokenHash: String, kind: VerificationKind) async throws -> Account
recover(email: String) async throws
updatePassword(_ password: String) async throws
refreshSession() async throws -> Account
restoreSession() async throws -> Account?
logout(allDevices: Bool) async -> LogoutResult
execute(_ envelope: CommandEnvelope) async throws -> Receipt
lookupOperation(_ id: UUID) async throws -> Receipt
synchronize() async throws -> ClientSnapshot
currentSnapshot() async -> ClientSnapshot
pendingOperation() async -> PendingOperation?
queryPending() async throws -> Receipt?
discardUnsent() async throws
```

`VerificationKind` is `.signup` or `.recovery`. Verification receives the token hash from the local test email, sends it through official Auth's `verifyOTP`, and never opens an arbitrary pasted URL. Password recovery uses official Auth and does not imply recent provider authentication for consent/deletion. After recovery, a deliberate password sign-in establishes a fresh provider session. Sign-in/restore validate `/v1/me`, rather than treating a locally stored token as verified authority.

The concrete actor additionally exposes `stage(_ envelope: CommandEnvelope) throws -> PendingOperation` and `alert(_ id: UUID) async throws -> SharedAlert`. Staging performs no network request and records `.neverSent`. These are integration-client methods, not required UI mock-protocol members. Direct alert lookup permits real unauthorized-access checks in the CLI.

## Typed domain values

All public model initializers are in `Models.swift`; all IDs are UUID and timestamps/cursors/versions are Int. Wire Codable keys explicitly match the existing snake_case contract. Public structs are Sendable/Equatable and mutable for fixture construction:

- `Account(userID, displayName, emailVerified=true)`.
- `Receipt(operationID, status, resourceID=nil, error=nil, serverTime, invitationToken=nil)`.
- `SharedAlert(alertID, senderID, state="active", version=1, expiresAt, closedAt=nil, recipients)`; Identifiable by alertID.
- `SharedRecipient(userID, response="none", responseVersion=0, access="active", providerAccepted=false, appAcknowledged=false, opened=false)`.
- `Invitation(invitationID, senderID, direction, state, expiresAt)`; Identifiable by invitationID.
- `ConsentGrant(senderID, recipientID, state)`.
- `Relationships(invitations=[], grants=[])`.
- `SyncSnapshot(cursor, fullSnapshot=true, alerts=[], removedIDs=[])`.
- `ClientSnapshot(account=nil, alerts=[], relationships=Relationships(), cursor=-1, generation=0, pending=nil)`.
- `PendingOperation(accountID, environmentID, envelope, state)`; state `.neverSent` or `.outcomeUnknown`.
- `LogoutResult(serverRevoked)`; false means local wipe was attempted but remote revocation is not confirmed. Storage errors must not be represented as proven local erasure.

`CommandEnvelope(operationID: UUID = UUID(), issuedAt: Int = currentEpoch, command: String, payload: [String: JSONValue])` is immutable. `JSONValue` has `.string`, `.integer`, `.bool`, `.array`, `.object`, `.null`. Domain delete is `command: "delete_account", payload: [:]`; accepted deletion invalidates the local session/cache immediately. Other commands map directly to the unchanged contract.

## Failure and concurrency rules

The UI must obtain a fresh one-use local sender authentication and explicit confirmation before invoking create/retry/add. That local result is never sent as server authentication proof. This library does not import or upload simulation data.

Only one pending command is allowed. `execute` saves `.outcomeUnknown` durably **before** the POST transport is called. It performs one explicit HTTP attempt, with no automatic reconnect queue or mutation retry. Preflight expiry/missing session/oversize before POST leaves `.neverSent`; a transport failure, malformed accepted response or ambiguous infrastructure result leaves `.outcomeUnknown(operationID)`. Call `queryPending` or `lookupOperation` to GET the **same operation ID**. A missing receipt does not clear the unknown state. `discardUnsent` rejects unknown operations. Do not allocate another ID to disguise uncertainty.

Pending envelopes survive app restart in Keychain for the matching account/environment and can be recovered after restoring the session. Logout/account switching purge prior account data. Generation checks reject delayed sign-in, command, refresh and sync results after switching/logging out. The official Auth storage adapter also becomes unwritable when invalidated, so an old SDK callback cannot repopulate the new session's Keychain data. Full snapshots replace the cache only at a strictly newer cursor; no SDK offline database queue exists.

`ClientError` cases: `invalidEnvironment`, `unauthenticated`, `staleGeneration`, `invalidResponse`, `storageUnavailable`, `server(String)` (allowlisted coarse code), `connectionFailed`, `pendingUnresolved`, `operationConflict`, `neverSent`, `outcomeUnknown(UUID)`. Do not display/log raw SDK errors, tokens, passwords, verification hashes or invitation URLs. The library has no logger and uses no administrator API.

This is a replaceable real HTTP/Auth adapter. Unit tests with injected transports remain mocks. Only the independent CLI journey against GoTrue/PostgreSQL can establish real Swift-client integration; UI tests against a mock actor do not establish native end-to-end backend operation or physical-device delivery.

SDK interfaces were checked against the official v2.55.2 source: [AuthClient](https://github.com/supabase/supabase-swift/blob/v2.55.2/Sources/Auth/AuthClient.swift), [configuration](https://github.com/supabase/supabase-swift/blob/v2.55.2/Sources/Auth/AuthClientConfiguration.swift), [AuthLocalStorage](https://github.com/supabase/supabase-swift/blob/v2.55.2/Sources/Auth/Storage/AuthLocalStorage.swift).

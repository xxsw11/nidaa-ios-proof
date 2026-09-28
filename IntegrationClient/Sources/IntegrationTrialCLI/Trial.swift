import Foundation
import NidaaIntegration
#if os(Linux)
import Glibc
#else
import Darwin
#endif

private struct Identity {
    let client: NidaaClient
    let email: String
    let password: String
    let account: Account
}

@main
struct IntegrationTrialCLI {
    static func main() async {
        do {
            try await run()
        } catch {
            // Provider errors, URL queries, passwords and session values are never printed.
            print("FAIL Swift integration trial; category=" + safeCategory(error))
            exit(1)
        }
    }

    private static func run() async throws {
        print("STAGE isolated_environment")
        let values = ProcessInfo.processInfo.environment
        guard let base = URL(string: values["NIDAA_BASE_URL"] ?? "http://gateway:8080"),
              let mail = URL(string: values["NIDAA_MAIL_URL"] ?? "http://mail:8025"),
              mail.scheme == "http", ["mail", "127.0.0.1", "localhost"].contains(mail.host ?? "") else {
            throw TrialFailure.failed("invalid isolated environment")
        }
        #if os(Linux)
        let environment = try TrialEnvironment.isolatedLinux(baseURL: base)
        #else
        let environment = try TrialEnvironment(baseURL: base)
        #endif
        print("PASS isolated environment configuration")
        let mailbox = LocalMailbox(baseURL: mail)
        let a = try await identity(environment: environment, mailbox: mailbox, label: .a)
        let b = try await identity(environment: environment, mailbox: mailbox, label: .b)
        let c = try await identity(environment: environment, mailbox: mailbox, label: .c)
        print("PASS official Auth signup, local inbox verification and password login for three isolated accounts")

        let b2 = NidaaClient(environment: environment, storage: MemoryClientStorage())
        let b2Account = try await b2.signIn(email: b.email, password: b.password)
        try requireTrial(b2Account.userID == b.account.userID, "independent second session identity")
        print("PASS two independent recipient sessions use one stable account identity")

        let invite = try await accepted(a.client, "invite", ["recipient_email": .string(b.email)])
        guard let invitationToken = invite.invitationToken else { throw TrialFailure.failed("invitation did not return a token") }
        let beforeConsent = try await a.client.execute(CommandEnvelope(command: "create_alert", payload: [
            "recipient_ids": .array([.string(b.account.userID.uuidString)]),
            "expires_at": .integer(Int(Date().timeIntervalSince1970)+600)]))
        try requireTrial(beforeConsent.status == "rejected" && beforeConsent.error == "consent_required", "invitation must not self-grant consent")
        let wrongTarget = try await c.client.execute(CommandEnvelope(command: "decide_invite", payload: [
            "token": .string(invitationToken), "decision": .string("accepted")]))
        try requireTrial(wrongTarget.status == "rejected" && wrongTarget.error == "not_found", "wrong invite target")
        _ = try await accepted(b.client, "decide_invite", ["token": .string(invitationToken), "decision": .string("accepted")])
        let reverse = try await b.client.execute(CommandEnvelope(command: "create_alert", payload: [
            "recipient_ids": .array([.string(a.account.userID.uuidString)]),
            "expires_at": .integer(Int(Date().timeIntervalSince1970)+600)]))
        try requireTrial(reverse.status == "rejected" && reverse.error == "consent_required", "one-way consent")
        print("PASS explicit target-bound consent; unauthorized invite acceptance and reverse sending denied")

        let receipt = try await accepted(a.client, "create_alert", [
            "recipient_ids": .array([.string(b.account.userID.uuidString)]),
            "expires_at": .integer(Int(Date().timeIntervalSince1970)+600)])
        guard let alertID = receipt.resourceID else { throw TrialFailure.failed("missing accepted alert") }
        let received = try await b.client.synchronize()
        let secondDevice = try await b2.synchronize()
        guard let incoming = received.alerts.first(where: { $0.alertID == alertID }) else {
            throw TrialFailure.failed("recipient shared snapshot")
        }
        try requireTrial(secondDevice.alerts.contains(where: { $0.alertID == alertID }), "second session shared state")
        let outsider = try await c.client.synchronize()
        try requireTrial(!outsider.alerts.contains(where: { $0.alertID == alertID }), "third-account read isolation")
        do {
            _ = try await c.client.alert(alertID)
            throw TrialFailure.failed("third-account direct alert read unexpectedly succeeded")
        } catch ClientError.server("not_found") {
            // Exact denial expected from the real shared API, independently of snapshot filtering.
        }
        let forged = try await c.client.execute(CommandEnvelope(command: "respond", payload: [
            "alert_id": .string(alertID.uuidString), "expected_version": .integer(incoming.version), "response": .string("responding")]))
        try requireTrial(forged.status == "rejected", "third-account response isolation")
        print("PASS shared HTTP alert retrieval on both recipient sessions; third-account access denied")

        _ = try await accepted(b.client, "acknowledge", ["alert_id": .string(alertID.uuidString),
            "event_id": .string(UUID().uuidString), "kind": .string("app_acknowledged")])
        _ = try await accepted(b2, "acknowledge", ["alert_id": .string(alertID.uuidString),
            "event_id": .string(UUID().uuidString), "kind": .string("opened")])
        _ = try await accepted(b.client, "respond", ["alert_id": .string(alertID.uuidString),
            "expected_version": .integer(incoming.version), "response": .string("responding")])
        let conflict = try await b2.execute(CommandEnvelope(command: "respond", payload: [
            "alert_id": .string(alertID.uuidString), "expected_version": .integer(incoming.version), "response": .string("declined")]))
        try requireTrial(conflict.status == "rejected" && conflict.error == "conflict", "first committed response wins")
        let observed = try await a.client.synchronize()
        guard let current = observed.alerts.first(where: { $0.alertID == alertID }),
              let participant = current.recipients.first(where: { $0.userID == b.account.userID }) else {
            throw TrialFailure.failed("sender state observation")
        }
        try requireTrial(current.state == "active" && participant.response == "responding", "response is not global resolution")
        try requireTrial(participant.appAcknowledged && participant.opened, "independent receipt and opening observations")
        print("PASS acknowledgement, opening and explicit response observed by sender; conflicting second response rejected")

        let saved = try await a.client.lookupOperation(receipt.operationID)
        try requireTrial(saved.resourceID == alertID && saved.status == "accepted", "original operation lookup")
        let refreshed = try await b2.refreshSession()
        try requireTrial(refreshed.userID == b.account.userID, "official SDK session refresh")
        print("PASS same-operation lookup and official Auth refresh retain identity")

        let logout = await b2.logout(allDevices: false)
        try requireTrial(logout.serverRevoked, "server session logout")
        let loggedOut = await b2.currentSnapshot()
        try requireTrial(loggedOut.account == nil && loggedOut.alerts.isEmpty && loggedOut.pending == nil, "logout local isolation")
        _ = try await b.client.synchronize()
        print("PASS current-session logout clears its local replica without logging out the other recipient session")
        print("Swift integration trial PASSED: real local GoTrue, HTTP and PostgreSQL; no external email or notifications")
        #if os(Linux)
        print("Linux credentials used isolated process memory. Apple Keychain and Simulator UI are separate test evidence.")
        #endif
    }

    private enum IdentityLabel: String { case a = "account_A", b = "account_B", c = "account_C" }

    private static func identity(environment: TrialEnvironment, mailbox: LocalMailbox, label: IdentityLabel) async throws -> Identity {
        let client = NidaaClient(environment: environment, storage: MemoryClientStorage())
        let email = "nidaa-swift-" + UUID().uuidString.lowercased() + "@example.invalid"
        // Pinned GoTrue v2.196.0 rejects passwords longer than 72 UTF-8 bytes.
        // One UUID produces 42 ASCII bytes including the prefix; nothing is logged.
        let password = "Nidaa!" + UUID().uuidString
        try requireTrial(password.utf8.count <= 72, "fixture password exceeds provider bound")
        print("STAGE " + label.rawValue + "_signup")
        try await client.signup(email: email, password: password)
        print("PASS " + label.rawValue + "_signup")
        print("STAGE " + label.rawValue + "_local_inbox")
        let token = try await mailbox.verificationHash(for: email)
        print("PASS " + label.rawValue + "_local_inbox")
        print("STAGE " + label.rawValue + "_sdk_email_verification")
        _ = try await client.verify(tokenHash: token, kind: .signup)
        print("PASS " + label.rawValue + "_sdk_email_verification")
        print("STAGE " + label.rawValue + "_sdk_password_login")
        let account = try await client.signIn(email: email, password: password)
        try requireTrial(account.emailVerified, "provider email verification")
        print("PASS " + label.rawValue + "_sdk_password_login")
        return Identity(client: client, email: email, password: password, account: account)
    }

    /// Only fixed, allowlisted categories can reach CI output. Never describe an
    /// arbitrary Error, request, URL, account identifier or provider response body.
    private static func safeCategory(_ error: any Error) -> String {
        if let clientError = error as? ClientError {
            switch clientError {
            case .invalidEnvironment: return "invalid_environment"
            case .unauthenticated: return "unauthenticated"
            case .staleGeneration: return "stale_generation"
            case .invalidResponse: return "invalid_response"
            case .storageUnavailable: return "storage_unavailable"
            case .connectionFailed: return "connection_failed"
            case .pendingUnresolved: return "pending_unresolved"
            case .operationConflict: return "operation_conflict"
            case .neverSent: return "never_sent"
            case .outcomeUnknown: return "outcome_unknown"
            case .server(let code):
                let allowed: Set<String> = ["authentication_failed", "invalid_request", "unauthenticated",
                    "not_found", "forbidden", "conflict", "expired", "rate_limited", "consent_required",
                    "terminal", "limit_reached", "reauthentication_required"]
                return allowed.contains(code) ? code : "server_error"
            }
        }
        if let network = error as? URLError {
            switch network.code {
            case .timedOut: return "transport_timeout"
            case .cannotFindHost, .dnsLookupFailed: return "transport_host_unavailable"
            case .cannotConnectToHost: return "transport_connection_refused"
            case .notConnectedToInternet, .networkConnectionLost: return "transport_disconnected"
            default: return "transport_error"
            }
        }
        if error is DecodingError { return "response_decode" }
        if error is TrialFailure { return "trial_assertion" }
        return "unexpected_error"
    }

    private static func accepted(_ client: any NidaaClientProtocol, _ command: String,
                                 _ payload: [String: JSONValue]) async throws -> Receipt {
        let receipt = try await client.execute(CommandEnvelope(command: command, payload: payload))
        try requireTrial(receipt.status == "accepted", "expected accepted command")
        return receipt
    }
}

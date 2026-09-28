#if DEBUG
import SwiftUI
import NidaaIntegration

struct TrialPerson: Identifiable, Equatable {
    var id: String { sender.uuidString + ":" + recipient.uuidString }
    let sender: UUID
    let recipient: UUID
    let accepted: Bool
}
struct TrialInvite: Identifiable {
    let id: UUID
    let sender: UUID
    let incoming: Bool
    let state: String
}
struct TrialRecipient: Identifiable {
    let id: UUID
    var response: String
    var responseVersion: Int
    var provider: Bool
    var acknowledged: Bool
    var opened: Bool
}
struct TrialAlert: Identifiable {
    let id: UUID
    let sender: UUID
    var state: String
    var version: Int
    var recipients: [TrialRecipient]
}
struct TrialConfirmation {
    let command: String
    let payload: [String: JSONValue]
    let title: String
    let deadline: Date
    let generation: Int
}

/// UI drafts are memory-only. The replaceable client owns account/environment-scoped
/// snapshots and Keychain session/uncertain-operation storage; no credentials in defaults.
@MainActor final class IntegrationStore: ObservableObject {
    @Published var accountID: UUID?
    @Published var accountName = ""
    @Published var invitations: [TrialInvite] = []
    @Published var people: [TrialPerson] = []
    @Published var alerts: [TrialAlert] = []
    @Published var selected: Set<UUID> = [] { didSet { if selected != oldValue { cancelAuthorization() } } }
    @Published var message = ""
    @Published var busy = false
    @Published var verifying = false
    @Published var pending = false
    @Published var neverSent = false
    @Published var invitationToken = ""
    @Published var confirmation: TrialConfirmation?
    @Published var mockAuthenticationPrompt = false
    let isMock: Bool
    private var client: (any NidaaClientProtocol)?
    private var generation = 0
    private let authentication = LocalAuthenticationService()
    private var mockContinuation: CheckedContinuation<Bool, Never>?
    private var pendingMockCommand: String?
    private var pendingMockPayload: [String: JSONValue] = [:]
    private static let fictionalA = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    private static let fictionalB = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    private static let fictionalC = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!

    init(injectedClient: (any NidaaClientProtocol)? = nil) {
        #if targetEnvironment(simulator)
        isMock = ProcessInfo.processInfo.arguments.contains("-nidaa-integration-mock")
        #else
        isMock = false
        #endif
        if !isMock {
            do { client = try injectedClient ?? NidaaClient.live(environment: TrialEnvironment(baseURL: URL(string: "http://127.0.0.1:55421")!)) }
            catch { message = "تعذر تجهيز الاتصال المحلي الآمن." }
        }
    }
    var eligible: [UUID] { people.filter { $0.sender == accountID && $0.accepted }.map(\.recipient) }
    var canMutate: Bool { accountID != nil && !busy && !pending }
    func label(_ id: UUID) -> String {
        if isMock {
            if id == Self.fictionalA { return "سارة · حساب خيالي" }
            if id == Self.fictionalB { return "سامي · حساب خيالي" }
            if id == Self.fictionalC { return "نور · حساب خيالي" }
        }
        if id == accountID { return "حسابي" }
        return "حساب \(id.uuidString.prefix(8))"
    }
    func restore() async {
        guard !isMock, let client else { return }
        await run {
            if try await client.restoreSession() != nil { try await self.reload() }
        }
    }
    func signUp(email: String, password: String) async {
        await run {
            if !self.isMock { try await self.requireClient().signup(email: email, password: password) }
            self.verifying = true
            self.message = "راجع صندوق البريد المحلي Mailpit، ثم أدخل رمز التحقق من الرابط. لم تُفعّل الجلسة بعد."
        }
    }
    func signIn(email: String, password: String) async {
        guard !busy else { return }
        clearView()
        await run {
            if self.isMock { self.seedMock() }
            else { _ = try await self.requireClient().signIn(email: email, password: password); try await self.reload() }
            self.verifying = false
            self.message = "تم الدخول. تحقق الجهاز مستقل عن هوية الحساب."
        }
    }
    func verify(token: String, recovery: Bool) async {
        guard !busy else { return }
        clearView()
        await run {
            if self.isMock { self.seedMock() }
            else {
                _ = try await self.requireClient().verify(tokenHash: token, kind: recovery ? .recovery : .signup)
                try await self.reload()
            }
            self.verifying = false
            self.message = recovery ? "تم التحقق من الاستعادة. عيّن كلمة مرور جديدة ثم سجّل الدخول مجددًا للإجراءات الحساسة." : "تم التحقق من البريد المحلي."
        }
    }
    func recover(email: String) async {
        await run {
            if !self.isMock { try await self.requireClient().recover(email: email) }
            self.verifying = true
            self.message = "إن كان البريد مسجّلًا، ستجد رابط الاستعادة في Mailpit المحلي."
        }
    }
    func updatePassword(_ password: String) async {
        await run {
            if !self.isMock { try await self.requireClient().updatePassword(password) }
            self.message = "تم تحديث كلمة المرور. سجّل الدخول مجددًا قبل قبول دعوة أو حذف الحساب."
        }
    }
    func refresh() async { await run { if !self.isMock { try await self.reload() }; self.message = "تم تحديث الحالة؛ التحديث لا يعيد إرسال أي عملية." } }
    func refreshSession() async {
        await run {
            if !self.isMock { _ = try await self.requireClient().refreshSession(); try await self.reload() }
            self.message = "جُدّدت الجلسة؛ هذا لا يُعد تسجيل دخول حديثًا."
        }
    }
    func logout(allDevices: Bool) async {
        cancelAuthorization()
        await run {
            var revoked = true
            if !self.isMock { revoked = try await self.requireClient().logout(allDevices: allDevices).serverRevoked }
            self.clearView()
            self.message = revoked ? "انتهت الجلسة وأُزيلت بيانات العرض." : "انتهى عرض الجلسة؛ تعذر تأكيد محو بياناتها أو إلغائها على الخادم."
        }
    }
    private func requireClient() throws -> any NidaaClientProtocol {
        guard let client else { throw TrialUIError.unavailable }; return client
    }
    private func reload() async throws {
        let epoch = generation
        let snapshot = try await requireClient().synchronize()
        guard epoch == generation else { return }
        if accountID != snapshot.account?.userID {
            cancelAuthorization()
            invitationToken = ""
        }
        accountID = snapshot.account?.userID
        accountName = snapshot.account?.displayName ?? ""
        invitations = snapshot.relationships.invitations.map { TrialInvite(id: $0.invitationID, sender: $0.senderID, incoming: $0.direction == "incoming", state: $0.state) }
        people = snapshot.relationships.grants.map { g in TrialPerson(sender: g.senderID, recipient: g.recipientID, accepted: g.state == "accepted") }
        alerts = snapshot.alerts.map { a in TrialAlert(id: a.alertID, sender: a.senderID, state: a.state, version: a.version, recipients: a.recipients.map { TrialRecipient(id: $0.userID, response: $0.response, responseVersion: $0.responseVersion, provider: $0.providerAccepted, acknowledged: $0.appAcknowledged, opened: $0.opened) }) }
        pending = snapshot.pending != nil
        neverSent = snapshot.pending?.state == .neverSent
        selected.formIntersection(eligible)
    }
    func command(_ name: String, payload: [String: JSONValue]) async {
        guard canMutate else { return }
        await run {
            if self.isMock {
                if ProcessInfo.processInfo.arguments.contains("-nidaa-integration-unknown") && name == "create_alert" {
                    self.pending = true; self.pendingMockCommand = name; self.pendingMockPayload = payload
                    self.message = "نتيجة العملية غير معروفة. استعلم عن العملية نفسها؛ لن يُعاد الإرسال تلقائيًا."
                    return
                }
                self.applyMock(name, payload: payload)
            } else {
                let receipt = try await self.requireClient().execute(CommandEnvelope(command: name, payload: payload))
                self.invitationToken = receipt.invitationToken ?? ""
                if receipt.status == "rejected" { self.message = Self.explain(receipt.error ?? "invalid_request") }
                else { self.message = "اعتمد الخادم العملية؛ لا يعني ذلك وصول إشعار أو استجابة شخص." }
                if name == "delete_account", receipt.status == "accepted" { self.clearView(); return }
                try await self.reload()
            }
        }
    }
    func lookupPending() async {
        await run {
            if self.isMock {
                if let name = self.pendingMockCommand { self.applyMock(name, payload: self.pendingMockPayload) }
                self.pendingMockCommand = nil; self.pendingMockPayload = [:]; self.pending = false
            } else {
                let receipt = try await self.requireClient().queryPending()
                guard let receipt else { self.message = "لم تظهر نتيجة مؤكدة بعد. أبقِ العملية معلّقة ولا تنشئ بديلًا."; return }
                self.invitationToken = receipt.invitationToken ?? ""
                try await self.reload()
            }
            self.message = "عُرفت نتيجة العملية الأصلية دون إعادة إرسال."
        }
    }
    func discardUnsent() async {
        guard neverSent else { return }
        await run {
            try await self.requireClient().discardUnsent()
            self.pending = false; self.neverSent = false
            self.message = "أُلغيت المسودة التي لم تُرسل. لا توجد إعادة إرسال تلقائية."
        }
    }
    func prepare(_ name: String, payload: [String: JSONValue], title: String) async {
        guard canMutate else { return }
        cancelAuthorization()
        let epoch = generation
        busy = true
        let success: Bool
        if isMock {
            success = await withCheckedContinuation { mockContinuation = $0; mockAuthenticationPrompt = true }
        } else {
            switch await authentication.authenticate(reason: "تحقق جديد لتأكيد إجراء نداء") {
            case .success: success = true
            case .cancelled, .failed: success = false
            }
        }
        busy = false
        guard generation == epoch, success else { message = "أُلغي التحقق أو لم ينجح؛ لم يُرسل الإجراء."; return }
        confirmation = TrialConfirmation(command: name, payload: payload, title: title, deadline: Date().addingTimeInterval(60), generation: epoch)
    }
    func answerMockAuthentication(_ success: Bool) {
        mockAuthenticationPrompt = false; mockContinuation?.resume(returning: success); mockContinuation = nil
    }
    func confirm() async {
        guard let item = confirmation, item.generation == generation, Date() < item.deadline else {
            cancelAuthorization(); message = "انتهت مهلة التأكيد. أعد التحقق صراحةً."; return
        }
        confirmation = nil
        await command(item.command, payload: item.payload)
    }
    func cancelAuthorization() {
        generation += 1; confirmation = nil; authentication.cancel(); answerMockAuthentication(false)
    }
    func backgrounded() { cancelAuthorization(); invitationToken = "" }
    func close() { cancelAuthorization(); invitationToken = "" }
    private func clearView() {
        cancelAuthorization()
        accountID = nil; accountName = ""; invitations = []; people = []; alerts = []
        selected = []; pending = false; neverSent = false; invitationToken = ""; confirmation = nil
        pendingMockCommand = nil; pendingMockPayload = [:]
    }
    private func run(_ work: () async throws -> Void) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do { try await work() }
        catch {
            if let client { let operation = await client.pendingOperation(); pending = operation != nil; neverSent = operation?.state == .neverSent }
            // Only whitelisted error codes reach the screen, never provider URLs, tokens or bodies.
            if let error = error as? ClientError { handle(error) }
            else { message = pending ? "نتيجة العملية غير معروفة. استعلم عنها دون إعادة الإرسال." : "تعذر الاتصال بالبيئة المحلية. تحقق من تشغيلها ثم حدّث يدويًا." }
        }
    }
    private func handle(_ error: ClientError) {
        switch error {
        case .unauthenticated, .server("unauthenticated"):
            clearView()
            message = "انتهت الجلسة. سجّل الدخول مجددًا؛ أُخفيت بيانات الحساب السابق."
        case .server(let code): message = Self.explain(code)
        case .neverSent: message = "لم تُرسل العملية. بقيت محفوظة بأمان؛ ألغها صراحةً قبل محاولة جديدة."
        case .staleGeneration: return
        default: message = "تعذر الاتصال بالبيئة المحلية. تحقق من تشغيلها ثم حدّث يدويًا."
        }
        if pending { message = "هناك عملية محفوظة تحتاج مراجعة. استعلم عن نتيجتها دون إعادة الإرسال." }
    }
    static func explain(_ value: String) -> String {
        switch value {
        case "reauthentication_required", "unauthenticated": return "يلزم تسجيل دخول حديث للحساب. تحقق الجهاز وحده لا يكفي."
        case "consent_required", "forbidden": return "لا توجد موافقة سارية لهذا الاتجاه."
        case "conflict": return "تغيّرت الحالة. حدّثها قبل اتخاذ قرار جديد."
        case "rate_limited", "limit_reached": return "بلغت الحد المسموح. انتظر ثم راجع الحالة يدويًا."
        case "expired", "terminal": return "انتهت صلاحية الإجراء أو الحالة."
        default: return "لم يُعتمد الطلب. راجع البيانات والحالة."
        }
    }
    private func seedMock() {
        accountID = Self.fictionalA; accountName = "سارة"
        people = [TrialPerson(sender: Self.fictionalA, recipient: Self.fictionalB, accepted: true)]
        invitations = [TrialInvite(id: UUID(), sender: Self.fictionalC, incoming: true, state: "pending")]
        if ProcessInfo.processInfo.arguments.contains("-nidaa-integration-incoming") {
            alerts = [TrialAlert(id: UUID(), sender: Self.fictionalB, state: "active", version: 1, recipients: [TrialRecipient(id: Self.fictionalA, response: "none", responseVersion: 0, provider: true, acknowledged: false, opened: false)])]
        }
    }
    private func applyMock(_ name: String, payload: [String: JSONValue]) {
        func string(_ key: String) -> String {
            guard let value = payload[key], case let .string(text) = value else { return "" }; return text
        }
        let alertID = UUID(uuidString: string("alert_id"))
        switch name {
        case "create_alert":
            alerts.append(TrialAlert(id: UUID(), sender: accountID!, state: "active", version: 1, recipients: selected.sorted { $0.uuidString < $1.uuidString }.map { TrialRecipient(id: $0, response: "none", responseVersion: 0, provider: false, acknowledged: false, opened: false) }))
        case "invite": invitations.append(TrialInvite(id: UUID(), sender: accountID!, incoming: false, state: "pending")); invitationToken = "MOCK-ONLY-FICTIONAL-INVITATION-TOKEN"
        case "decide_invite": invitations = []; message = "موافقة محاكية باتجاه واحد."
        case "delete_account": clearView()
        case "withdraw", "block": people = []
        case "close_alert": if let index = alerts.firstIndex(where: { $0.id == alertID }) { alerts[index].state = string("state") }
        case "respond": if let i = alerts.firstIndex(where: { $0.id == alertID }), let j = alerts[i].recipients.firstIndex(where: { $0.id == accountID }) { alerts[i].recipients[j].response = string("response"); alerts[i].recipients[j].responseVersion += 1 }
        case "acknowledge": if let i = alerts.firstIndex(where: { $0.id == alertID }), let j = alerts[i].recipients.firstIndex(where: { $0.id == accountID }) { alerts[i].recipients[j].acknowledged = true; if string("kind") == "opened" { alerts[i].recipients[j].opened = true } }
        default: break
        }
        message = "تمت محاكاة العملية داخل الواجهة؛ لا يوجد اتصال بالخادم في هذا الاختبار."
    }
}
private enum TrialUIError: Error { case unavailable }
#endif

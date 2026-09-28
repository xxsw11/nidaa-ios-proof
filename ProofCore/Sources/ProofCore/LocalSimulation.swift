import Foundation

public enum InvitationState: String, Codable, CaseIterable, Sendable {
    case pending, accepted, declined, blocked
    public var title: String {
        switch self { case .pending: return "دعوة معلّقة"; case .accepted: return "مقبول"
        case .declined: return "دعوة مرفوضة"; case .blocked: return "محظور" }
    }
}
public struct TrustedContact: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var state: InvitationState
    public var allowsOutgoing: Bool
    public var allowsIncoming: Bool
    public var canSend: Bool { state == .accepted && allowsOutgoing }
    public var canReceive: Bool { state == .accepted && allowsIncoming }
    public init(id: UUID = UUID(), name: String, state: InvitationState = .pending,
                allowsOutgoing: Bool = false, allowsIncoming: Bool = false) {
        self.id = id; self.name = name; self.state = state
        self.allowsOutgoing = allowsOutgoing; self.allowsIncoming = allowsIncoming
    }
    public static var samples: [Self] {
        [Self(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, name: "سارة", state: .accepted, allowsOutgoing: true, allowsIncoming: true),
         Self(id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!, name: "أحمد", state: .accepted, allowsOutgoing: true, allowsIncoming: true),
         Self(id: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!, name: "خالد")]
    }
}
public enum AssistanceKind: String, Codable, CaseIterable, Sendable {
    case urgent, call, checkIn
    public var title: String { switch self { case .urgent: return "مساعدة عاجلة"; case .call: return "أحتاج تواصلًا"; case .checkIn: return "اطمئن عليّ" } }
}
public enum RecipientStage: String, Codable, Sendable {
    case sent, received, opened, responding, declined
    public var title: String { switch self { case .sent: return "إرسال محاكى · الوصول غير مؤكد"
    case .received: return "استلام محاكى · دون قبول"; case .opened: return "فُتح في المحاكاة · دون قبول"
    case .responding: return "سأتولى الاستجابة"; case .declined: return "لا يستطيع الاستجابة" } }
    public var symbol: String { switch self { case .sent: return "paperplane"; case .received: return "checkmark.circle"
    case .opened: return "eye"; case .responding: return "person.fill.checkmark"; case .declined: return "person.fill.xmark" } }
}
public struct RecipientProgress: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID { contactID }
    public let contactID: UUID
    public let name: String
    public var stage: RecipientStage = .sent
    public var receivedAt: Date?
    public var openedAt: Date?
    public var respondedAt: Date?
    public init(contact: TrustedContact) { contactID = contact.id; name = contact.name }
}
public enum LocalAlertState: String, Codable, Sendable {
    case active, resolved, cancelled, expired
    public var title: String { switch self { case .active: return "نداء محاكى نشط"; case .resolved: return "انتهت الحالة بتأكيد صريح"
    case .cancelled: return "أُلغي النداء · لا يثبت السلامة"; case .expired: return "انتهت صلاحية النداء" } }
}
public struct SimulationEvent: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let at: Date
    public let text: String
    public init(at: Date, text: String) { id = UUID(); self.at = at; self.text = text }
}
public struct LocalAlert: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let incoming: Bool
    public let kind: AssistanceKind
    public let createdAt: Date
    public let expiresAt: Date
    public var state: LocalAlertState = .active
    public var recipients: [RecipientProgress]
    public var silenced = false
    public var dismissed = false
    public var nonresponse = false
    public var attempts = 1
    public var events: [SimulationEvent]
    public var isActive: Bool { state == .active }
    public init(id: UUID = UUID(), incoming: Bool = false, kind: AssistanceKind, contacts: [TrustedContact], at: Date) {
        self.id = id; self.incoming = incoming; self.kind = kind; createdAt = at
        expiresAt = at.addingTimeInterval(300); recipients = contacts.map(RecipientProgress.init)
        events = [.init(at: at, text: "إنشاء سجل محلي · لا طلب حقيقي"), .init(at: at, text: "إرسال محاكى فقط · لا مزود أو جهاز متصل")]
    }
}
public enum SimulationError: Error, Equatable {
    case noConsent, noRecipients, authenticationRequired, invalidTransition, missingAlert, invalidContact
}
public struct SendGate: Sendable {
    private var recipientIDs: Set<UUID> = []
    private var kind: AssistanceKind?
    private var until: Date?
    public init() {}
    public mutating func authorize(success: Bool, recipients: Set<UUID>, kind: AssistanceKind, at now: Date) {
        invalidate(); guard success else { return }
        recipientIDs = recipients; self.kind = kind; until = now.addingTimeInterval(15)
    }
    public func permits(_ ids: Set<UUID>, kind: AssistanceKind, at now: Date) -> Bool {
        guard let until = until else { return false }
        return now < until && ids == recipientIDs && self.kind == kind && !ids.isEmpty
    }
    public mutating func consume(_ ids: Set<UUID>, kind: AssistanceKind, at now: Date) throws {
        guard permits(ids, kind: kind, at: now) else { invalidate(); throw SimulationError.authenticationRequired }
        invalidate()
    }
    public mutating func invalidate() { until = nil; kind = nil; recipientIDs = [] }
}

public struct LocalSimulation: Sendable {
    public private(set) var contacts: [TrustedContact]
    public private(set) var alerts: [LocalAlert] = []
    public init(contacts: [TrustedContact] = TrustedContact.samples) { self.contacts = contacts }
    public var hasActive: Bool { alerts.contains(where: \.isActive) }
    public mutating func saveContact(_ contact: TrustedContact) throws {
        let name = contact.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 40 else { throw SimulationError.invalidContact }
        var edited = contact; edited.name = name
        if edited.state != .accepted { edited.allowsOutgoing = false; edited.allowsIncoming = false }
        if let n = contacts.firstIndex(where: { $0.id == edited.id }) { contacts[n] = edited } else { contacts.append(edited) }
    }
    public mutating func deleteContact(_ id: UUID) { contacts.removeAll { $0.id == id } }
    public mutating func create(recipients: Set<UUID>, kind: AssistanceKind, gate: inout SendGate, at now: Date) throws -> UUID {
        tick(at: now)
        guard !recipients.isEmpty else { throw SimulationError.noRecipients }
        let chosen = contacts.filter { recipients.contains($0.id) }
        guard chosen.count == recipients.count, chosen.allSatisfy(\.canSend) else { gate.invalidate(); throw SimulationError.noConsent }
        try gate.consume(recipients, kind: kind, at: now)
        if let existing = alerts.first(where: { $0.isActive && !$0.incoming }) { return existing.id }
        let alert = LocalAlert(kind: kind, contacts: chosen, at: now); alerts.insert(alert, at: 0); return alert.id
    }
    public mutating func incoming(from id: UUID, at now: Date) throws -> UUID {
        tick(at: now)
        guard let contact = contacts.first(where: { $0.id == id && $0.canReceive }) else { throw SimulationError.noConsent }
        if let existing = alerts.first(where: { $0.incoming && $0.isActive && $0.recipients.first?.id == id }) { return existing.id }
        var alert = LocalAlert(incoming: true, kind: .urgent, contacts: [contact], at: now)
        alert.recipients[0].stage = .received; alert.recipients[0].receivedAt = now
        alert.events.append(.init(at: now, text: "وارد محلي من شخصية خيالية؛ لا إشعار نظام"));alerts.insert(alert, at: 0);return alert.id
    }
    public mutating func transition(_ alertID: UUID, recipient id: UUID, to next: RecipientStage, at now: Date) throws {
        tick(at: now)
        guard let n = alerts.firstIndex(where: { $0.id == alertID }), alerts[n].isActive,
              let p = alerts[n].recipients.firstIndex(where: { $0.id == id }) else { throw SimulationError.invalidTransition }
        let incoming = alerts[n].incoming
        guard contacts.contains(where: { $0.id == id && (incoming ? $0.canReceive : $0.canSend) }) else { throw SimulationError.noConsent }
        let before = alerts[n].recipients[p].stage
        let allowed: Bool
        switch next {
        case .sent: allowed = false
        case .received: allowed = before == .sent
        case .opened: allowed = before == .received
        case .responding, .declined: allowed = before == .received || before == .opened
        }
        guard allowed else { throw SimulationError.invalidTransition }
        alerts[n].recipients[p].stage = next
        if next == .received { alerts[n].recipients[p].receivedAt = now }
        if next == .opened { alerts[n].recipients[p].openedAt = now }
        if next == .responding || next == .declined { alerts[n].recipients[p].respondedAt = now }
        alerts[n].events.append(.init(at: now, text: "\(alerts[n].recipients[p].name): \(next.title)"))
        if next == .declined { alerts[n].events.append(.init(at: now, text: "الرفض لا يغلق الحالة؛ جرّب مستجيبًا آخر بإذن ساري")) }
    }
    public mutating func silence(_ id: UUID, dismiss: Bool = false, at now: Date) {
        guard let n = alerts.firstIndex(where: { $0.id == id }), alerts[n].isActive else { return }
        alerts[n].silenced = true; alerts[n].dismissed = dismiss
        alerts[n].events.append(.init(at: now, text: "إسكات/إخفاء محاكى فقط؛ لا قبول ولا حل للحالة"))
    }
    public mutating func retry(_ id: UUID, at now: Date) throws {
        tick(at: now)
        guard let n = alerts.firstIndex(where: { $0.id == id }), alerts[n].isActive, !alerts[n].incoming else { throw SimulationError.invalidTransition }
        guard alerts[n].recipients.contains(where: { recipient in contacts.contains { $0.id == recipient.id && $0.canSend } }) else { throw SimulationError.noConsent }
        alerts[n].attempts += 1;alerts[n].events.append(.init(at: now, text: "إعادة محاولة محاكاة بنفس المعرّف؛ حالات الاستجابة محفوظة"))
    }
    public mutating func addAlternative(_ id: UUID, contactID: UUID, at now: Date) throws {
        tick(at: now)
        guard let n = alerts.firstIndex(where: { $0.id == id }), alerts[n].isActive, !alerts[n].incoming,
              !alerts[n].recipients.contains(where: { $0.id == contactID }) else { throw SimulationError.invalidTransition }
        guard let c = contacts.first(where: { $0.id == contactID && $0.canSend }) else { throw SimulationError.noConsent }
        alerts[n].recipients.append(RecipientProgress(contact: c))
        alerts[n].events.append(.init(at: now, text: "إضافة بديل بإذن ساري في المحاكاة: \(c.name)"))
    }
    public mutating func close(_ id: UUID, state: LocalAlertState, at now: Date) throws {
        tick(at: now)
        guard let n = alerts.firstIndex(where: { $0.id == id }), alerts[n].isActive,
              state == .resolved || (state == .cancelled && !alerts[n].incoming) else { throw SimulationError.invalidTransition }
        alerts[n].state = state;alerts[n].events.append(.init(at: now, text: state.title))
    }
    public mutating func tick(at now: Date) {
        for n in alerts.indices where alerts[n].isActive {
            if now >= alerts[n].expiresAt {
                alerts[n].state = .expired;alerts[n].events.append(.init(at: now, text: LocalAlertState.expired.title))
            } else if !alerts[n].nonresponse && now.timeIntervalSince(alerts[n].createdAt) >= 25 && !alerts[n].recipients.contains(where: { $0.stage == .responding }) {
                alerts[n].nonresponse = true;alerts[n].events.append(.init(at: now, text: "لم يقبل أحد خلال المهلة؛ المساعدة غير مؤكدة"))
            }
        }
    }
}

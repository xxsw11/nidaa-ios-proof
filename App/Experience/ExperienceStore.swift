import Foundation
import Combine
import SwiftUI
import ProofCore

enum AppTab: String { case home, contacts, history, settings }
enum AppScreen: Equatable { case compose, alert(UUID), incoming(UUID), editContact(UUID?), readiness, appearance, terms, privacy, technical }

@MainActor final class ExperienceStore: ObservableObject {
    @Published var simulation: LocalSimulation
    @Published var appearance: AppearancePreferences
    @Published var screen: AppScreen?
    @Published var tab: AppTab = .home
    @Published var selected: Set<UUID> = []
    @Published var assistance: AssistanceKind = .urgent
    @Published var confirmationReady = false
    @Published var busy = false
    @Published var message = ""
    @Published var locked = false
    @Published var lockEnabled: Bool
    @Published var authLabel = "تحقق جديد لكل نداء"
    @Published var incomingID: UUID?
    @Published var previewRecipient: UUID?
    @Published var frozenPalette: Palette?
    @Published var systemDark = true
    @Published var simulationAuthentication = false
    @Published var authChoicePending = false
    @Published var now = Date()
    private var authContinuation: CheckedContinuation<Bool, Never>?
    private let preferences: DemoPreferences
    private let authentication = LocalAuthenticationService()
    private var gate = SendGate()
    private var generation = 0
    private var clockOffset: TimeInterval = 0
    private var testOutcome: String?
    var palette: Palette { frozenPalette ?? appearance.palette(systemDark: systemDark) }
    var eligible: [TrustedContact] { simulation.contacts.filter(\.canSend) }
    var isDebugSimulator: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    init() {
        let prefs: DemoPreferences
        var useTestAuthentication = false
        var configuredOutcome: String?
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-nidaa-ui-testing") {
            let defaults = UserDefaults(suiteName: "nidaa.ui.tests")!
            prefs = DemoPreferences(defaults: defaults)
            if ProcessInfo.processInfo.arguments.contains("-reset-demo") { prefs.reset() }
            useTestAuthentication = true
            configuredOutcome = ProcessInfo.processInfo.environment["NIDAA_TEST_AUTH"] ?? "success"
        } else { prefs = DemoPreferences() }
        #else
        prefs = DemoPreferences()
        #endif
        preferences = prefs; appearance = prefs.loadAppearance()
        simulation = LocalSimulation(contacts: prefs.loadContacts());lockEnabled = prefs.appLock;locked = prefs.appLock
        simulationAuthentication = useTestAuthentication;testOutcome = configuredOutcome
    }
    func startCompose() {
        guard !locked else { message = "افتح القفل أولًا"; return }
        gate.invalidate();confirmationReady = false
        selected = Set(eligible.map(\.id));assistance = .urgent;screen = .compose;message = ""
    }
    func selectionChanged() { gate.invalidate(); confirmationReady = false }
    func prepareSend() async {
        guard !busy, !locked, !selected.isEmpty else { return }
        busy = true;defer { busy = false }
        gate.invalidate();confirmationReady = false
        let ids = selected, kind = assistance, epoch = generation
        let succeeded = await authenticate("تحقق قبل إنشاء نداء محاكى؛ لا يرسل أي إشعار حقيقي.")
        guard epoch == generation, ids == selected, kind == assistance, !locked else { return }
        gate.authorize(success: succeeded, recipients: ids, kind: kind, at: now)
        confirmationReady = succeeded
        if !succeeded { message = "لم ينجح التحقق أو أُلغي؛ لم يُنشأ نداء." }
    }
    func confirmSend() {
        guard !locked, confirmationReady else { return }
        defer { confirmationReady = false }
        run {
            let id = try simulation.create(recipients: selected, kind: assistance, gate: &gate, at: now)
            freezeIfNeeded();screen = .alert(id);message = "إنشاء وإرسال محاكيان فقط؛ لا إشعار أو اتصال."
        }
    }
    func cancelCompose() { generation += 1;gate.invalidate();confirmationReady = false;authentication.cancel();answerAuthentication(false);screen = nil }
    func simulateIncoming() {
        run {
            guard let person = simulation.contacts.first(where: \.canReceive) else { throw SimulationError.noConsent }
            let id = try simulation.incoming(from: person.id, at: now)
            incomingID = id;previewRecipient = person.id;freezeIfNeeded();screen = .incoming(id)
        }
    }
    func openIncoming(_ id: UUID) { screen = .incoming(id) }
    func transition(_ id: UUID, recipient: UUID, to state: RecipientStage) {
        guard !locked else { message = "افتح القفل للوصول إلى تفاصيل النداء أو الاستجابة.";return }
        run { try simulation.transition(id, recipient: recipient, to: state, at: now) }
    }
    func silence(_ id: UUID, dismiss: Bool = false) {
        simulation.silence(id, dismiss: dismiss, at: now)
        if dismiss { screen = nil }
        message = "إسكات محاكى؛ الحالة لم تنتهِ ولا يوجد صوت فعلي."
    }
    func closeAlert(_ id: UUID, state: LocalAlertState) {
        guard !locked else { return }
        run { try simulation.close(id, state: state, at: now);releaseIfFinished() }
    }
    func retry(_ id: UUID) { guard !locked else { return };run { try simulation.retry(id, at: now) } }
    func alternative(_ id: UUID, contact: UUID) { guard !locked else { return };run { try simulation.addAlternative(id, contactID: contact, at: now) } }
    func saveContact(_ value: TrustedContact) {
        guard !locked else { return }
        run { try simulation.saveContact(value);try preferences.saveContacts(simulation.contacts);screen = nil }
    }
    func deleteContact(_ id: UUID) {
        guard !locked else { return }
        simulation.deleteContact(id);run { try preferences.saveContacts(simulation.contacts) };selected.remove(id);selectionChanged();screen = nil
    }
    func saveAppearance(_ value: AppearancePreferences) {
        guard !locked else { return }
        run {
            try preferences.saveAppearance(value);appearance = value
            message = simulation.hasActive ? "حُفظت الألوان؛ يتأجل تطبيقها حتى انتهاء النداءات النشطة." : "حُفظ المظهر على هذا الجهاز."
            screen = nil
        }
    }
    func setAppLock(_ enabled: Bool) async {
        guard !busy else { return };busy = true;defer { busy = false };let epoch = generation
        guard await authenticate(enabled ? "تفعيل قفل التطبيق بوسيلة النظام." : "تعطيل قفل التطبيق بوسيلة النظام."), epoch == generation else { return }
        preferences.appLock = enabled;lockEnabled = enabled
    }
    func unlock() async {
        guard !busy else { return };busy = true;defer { busy = false };let epoch = generation
        if await authenticate("فتح تفاصيل التطبيق؛ لا يسمح هذا بإنشاء نداء دون تحقق جديد."), epoch == generation { locked = false }
    }
    func lockNow() { generation += 1;gate.invalidate();confirmationReady = false;locked = true;screen = nil;authentication.cancel();answerAuthentication(false) }
    func backgrounded() {
        generation += 1;gate.invalidate();confirmationReady = false;authentication.cancel();answerAuthentication(false)
        if screen == .compose { screen = nil }
        if lockEnabled { locked = true;if case .some(.incoming(_)) = screen {} else { screen = nil } }
        authLabel = "التحقق السابق لا يسمح بإنشاء نداء جديد"
    }
    func tick() {
        now = Date().addingTimeInterval(clockOffset);simulation.tick(at: now);releaseIfFinished()
        if confirmationReady && !gate.permits(selected, kind: assistance, at: now) { confirmationReady = false;message = "انتهت مهلة التأكيد؛ تحقق مجددًا." }
    }
    func advance(_ seconds: TimeInterval) { clockOffset += seconds;tick() }
    func resetDemo() {
        guard !locked else { return }
        generation += 1;authentication.cancel();answerAuthentication(false);gate.invalidate();preferences.reset()
        simulation = LocalSimulation();appearance = .init();lockEnabled = false;locked = false
        screen = nil;incomingID = nil;frozenPalette = nil;selected = [];confirmationReady = false;clockOffset = 0;now = Date()
        message = "أُعيدت البيانات الخيالية والمظهر؛ مُسح السجل المحلي لهذه الجلسة."
    }
    func answerAuthentication(_ success: Bool) { authChoicePending = false;authContinuation?.resume(returning: success);authContinuation = nil }
    private func authenticate(_ reason: String) async -> Bool {
        #if DEBUG && targetEnvironment(simulator)
        if simulationAuthentication {
            authLabel = "مصادقة محاكية · Debug Simulator فقط"
            if let outcome = testOutcome {
                if outcome == "delayed" { try? await Task.sleep(nanoseconds: 4_000_000_000) }
                return outcome == "success" || outcome == "delayed"
            }
            return await withCheckedContinuation { continuation in authContinuation = continuation;authChoicePending = true }
        }
        #endif
        let result = await authentication.authenticate(reason: reason)
        authLabel = authentication.lastMethod
        switch result { case .success: return true;case .cancelled: message = "أُلغي التحقق";return false
        case .failed(let error): message = error;return false }
    }
    private func run(_ action: () throws -> Void) {
        do { try action() } catch {
            switch error as? SimulationError {
            case .noConsent: message = "لا إذن ساري؛ لا إرسال أو استجابة إلى شخص محظور أو غير موافق."
            case .noRecipients: message = "اختر شخصًا واحدًا على الأقل."
            case .authenticationRequired: message = "يلزم تحقق جديد؛ التأكيد السابق غير صالح."
            case .invalidContact: message = "اكتب اسمًا خياليًا من ١ إلى ٤٠ حرفًا."
            default: message = "الإجراء غير متاح في هذه الحالة؛ راجع الصلاحية والاستجابة."
            }
        }
    }
    private func freezeIfNeeded() { if simulation.hasActive && frozenPalette == nil { frozenPalette = appearance.palette(systemDark: systemDark) } }
    private func releaseIfFinished() { if !simulation.hasActive { frozenPalette = nil } }
}

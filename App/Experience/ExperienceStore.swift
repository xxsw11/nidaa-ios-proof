import Foundation
import Combine
import SwiftUI
import ProofCore

enum AppTab: String { case home, contacts, history, settings }
enum AppScreen: Equatable { case compose, action, alert(UUID), incoming(UUID), editContact(UUID?), readiness, appearance, terms, privacy, technical, integration }

@MainActor final class ExperienceStore: ObservableObject {
    #if DEBUG
    // One live client owns this environment for the entire app lifetime, including
    // sheet dismissal/reopening while a network operation is in flight.
    lazy var integrationStore = IntegrationStore()
    #endif
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
    @Published var actionDetails: AlertActionDetails?
    @Published var actionReady = false
    @Published var storageIssue = ""
    private let repository: AlertRepository
    private var actionGate = AlertActionGate()
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
        var storageName = "NIDAA-Local"
        var useTestAuthentication = false
        var configuredOutcome: String?
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-nidaa-ui-testing") {
            storageName = "NIDAA-UI-Tests"
            let defaults = UserDefaults(suiteName: "nidaa.ui.tests")!
            prefs = DemoPreferences(defaults: defaults)
            if ProcessInfo.processInfo.arguments.contains("-reset-demo") { prefs.reset() }
            useTestAuthentication = true
            configuredOutcome = ProcessInfo.processInfo.environment["NIDAA_TEST_AUTH"] ?? "success"
        } else { prefs = DemoPreferences() }
        #else
        prefs = DemoPreferences()
        #endif
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(storageName)
        let fileIO = FileArchiveIO(directory: directory)
        let archiveIO: any ArchiveIO
        #if DEBUG && targetEnvironment(simulator)
        archiveIO = useTestAuthentication ? UITestArchiveIO(base: fileIO) : fileIO
        #else
        archiveIO = fileIO
        #endif
        let repo = AlertRepository(io: archiveIO)
        repository = repo
        preferences = prefs; appearance = prefs.loadAppearance()
        simulation = LocalSimulation(contacts: prefs.loadContacts());lockEnabled = prefs.appLock;locked = prefs.appLock
        simulationAuthentication = useTestAuthentication;testOutcome = configuredOutcome
        do {
            #if DEBUG && targetEnvironment(simulator)
            if useTestAuthentication {
                if ProcessInfo.processInfo.arguments.contains("-reset-demo") { _ = try repo.reset() }
                if ProcessInfo.processInfo.arguments.contains("-corrupt-archive") { try fileIO.replace(with: Data("corrupt fixture".utf8)) }
                clockOffset = Double(ProcessInfo.processInfo.environment["NIDAA_TEST_CLOCK"] ?? "0") ?? 0
            }
            #endif
            now = Date().addingTimeInterval(clockOffset)
            simulation = try repo.load(legacyContacts: prefs.loadContacts(), at: now)
            incomingID = simulation.alerts.first(where: { $0.incoming && $0.isActive })?.id
            freezeIfNeeded()
        } catch { storageIssue = "تعذرت قراءة أو حفظ السجل المحلي. لم تُستبدل البيانات؛ أعد المحاولة أو اضبط بيانات العرض صراحةً." }
        // All authorization gates are new empty values on every process launch.
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-nidaa-integration-mock") { screen = .integration }
        #endif
    }
    func startCompose() {
        guard !locked else { message = "افتح القفل أولًا"; return }
        gate.invalidate();confirmationReady = false
        selected = Set(eligible.map(\.id));assistance = .urgent;screen = .compose;message = ""
    }
    func selectionChanged() { invalidateAuthorization() }
    private func invalidateAuthorization() {
        generation += 1;gate.invalidate();actionGate.invalidate();confirmationReady = false;actionReady = false
        authentication.cancel();answerAuthentication(false)
    }
    func prepareSend() async {
        guard !busy, !locked, !selected.isEmpty else { return }
        busy = true;defer { busy = false }
        gate.invalidate();confirmationReady = false
        tick()
        let ids = selected, kind = assistance, epoch = generation
        let succeeded = await authenticate("تحقق قبل إنشاء نداء محاكى؛ لا يرسل أي إشعار حقيقي.")
        guard epoch == generation, ids == selected, kind == assistance, !locked else { return }
        tick()
        gate.authorize(success: succeeded, recipients: ids, kind: kind, at: now)
        confirmationReady = succeeded
        if !succeeded { message = "لم ينجح التحقق أو أُلغي؛ لم يُنشأ نداء." }
    }
    func confirmSend() {
        tick()
        guard !locked, confirmationReady else { return }
        defer { confirmationReady = false }
        run {
            let id = try simulation.create(recipients: selected, kind: assistance, gate: &gate, at: now)
            freezeIfNeeded();screen = .alert(id);message = "إنشاء وإرسال محاكيان فقط؛ لا إشعار أو اتصال."
        }
    }
    func cancelCompose() { invalidateAuthorization();actionDetails = nil;screen = nil }
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
        run {
            simulation.silence(id, dismiss: dismiss, at: now)
            if dismiss { screen = nil }
            message = "الإسكات وحده لا يعني قبول الاستجابة أو إنهاء الحالة؛ لا صوت فعلي."
        }
    }
    func closeAlert(_ id: UUID, state: LocalAlertState) {
        guard !locked else { return }
        run { try simulation.close(id, state: state, at: now);message = state.title;releaseIfFinished() }
    }
    func selectAction(_ id: UUID, action: AlertAction) {
        guard !locked, !busy, storageIssue.isEmpty else { return }
        invalidateAuthorization();tick()
        run { actionDetails = try simulation.actionDetails(id, action: action, at: now);screen = .action;message = "" }
    }
    func prepareAction() async {
        guard !busy, !locked, storageIssue.isEmpty, let details = actionDetails else { return }
        invalidateAuthorization();busy = true;defer { busy = false };let epoch = generation
        let success = await authenticate("تحقق جديد لإعادة المحاولة أو إضافة مستقبِل في المحاكاة.")
        tick()
        guard epoch == generation, !locked, actionDetails == details,
              (try? simulation.actionDetails(details.alertID, action: details.action, at: now)) == details else {
            actionGate.invalidate();actionReady = false;message = "تغير الإجراء أو انتهت صلاحيته؛ اختره وتحقق مجددًا.";return
        }
        actionGate.authorize(success: success, details: details, at: now);actionReady = success
        if !success { message = "فشل التحقق أو أُلغي؛ لم تُنفذ المحاولة أو الإضافة." }
    }
    func confirmAction() {
        tick()
        guard !locked, !busy, actionReady, let details = actionDetails else { return }
        actionReady = false
        defer { actionGate.invalidate() }
        run {
            try simulation.perform(details, gate: &actionGate, at: now)
            screen = .alert(details.alertID);actionDetails = nil
            message = "نُفذ الإجراء مرة واحدة في المحاكاة وحُفظ محليًا؛ لا إشعار حقيقي."
        }
    }
    func cancelAction() {
        let id = actionDetails?.alertID;invalidateAuthorization();actionDetails = nil
        screen = id.map(AppScreen.alert)
    }
    func saveContact(_ value: TrustedContact) {
        guard !locked else { return }
        invalidateAuthorization()
        run { try simulation.saveContact(value);screen = nil }
    }
    func deleteContact(_ id: UUID) {
        guard !locked else { return }
        invalidateAuthorization()
        run { simulation.deleteContact(id);selected.remove(id);screen = nil }
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
    func lockNow() { invalidateAuthorization();locked = true;screen = nil }
    func backgrounded() {
        invalidateAuthorization()
        if screen == .compose || screen == .action { screen = nil };actionDetails = nil
        if lockEnabled { locked = true;if case .some(.incoming(_)) = screen {} else { screen = nil } }
        authLabel = "التحقق السابق لا يسمح بإنشاء نداء جديد"
    }
    func tick() {
        now = Date().addingTimeInterval(clockOffset)
        if storageIssue.isEmpty {
            let before = simulation.alerts
            simulation.tick(at: now)
            if before != simulation.alerts {
                do { try repository.save(simulation) }
                catch { storageIssue = "تعذر حفظ انتهاء المهلة. لا إجراء جديد حتى استعادة التخزين.";invalidateAuthorization() }
            }
        }
        releaseIfFinished()
        if actionReady, let details = actionDetails,
           !actionGate.permits(details, at: now) || (try? simulation.actionDetails(details.alertID, action: details.action, at: now)) != details {
            actionGate.invalidate();actionReady = false;message = "انتهى تفويض الإجراء أو تغير المستقبِلون؛ تحقق مجددًا."
        }
        if confirmationReady && !gate.permits(selected, kind: assistance, at: now) { confirmationReady = false;message = "انتهت مهلة التأكيد؛ تحقق مجددًا." }
    }
    func advance(_ seconds: TimeInterval) { clockOffset += seconds;tick() }
    func reloadStorage() {
        invalidateAuthorization()
        do {
            simulation = try repository.load(legacyContacts: preferences.loadContacts(), at: Date().addingTimeInterval(clockOffset))
            storageIssue = "";freezeIfNeeded();message = "استُعيد السجل دون إرسال أو إعادة محاولة."
        } catch { storageIssue = "تعذر استعادة السجل؛ بقيت البيانات السابقة دون استبدال." }
    }
    func resetDemo() {
        guard !locked else { return }
        invalidateAuthorization()
        do { simulation = try repository.reset() }
        catch { storageIssue = "فشلت إعادة الضبط؛ لم يُؤكد حذف السجل. أعد المحاولة عند توفر التخزين.";return }
        preferences.reset();storageIssue = "";appearance = .init();lockEnabled = false;locked = false
        screen = nil;incomingID = nil;frozenPalette = nil;selected = [];actionDetails = nil;clockOffset = 0;now = Date()
        message = "أُعيدت البيانات الخيالية والمظهر؛ مُسح السجل المحفوظ محليًا."
    }
    func answerAuthentication(_ success: Bool) { authChoicePending = false;authContinuation?.resume(returning: success);authContinuation = nil }
    private func authenticate(_ reason: String) async -> Bool {
        #if DEBUG && targetEnvironment(simulator)
        if simulationAuthentication {
            authLabel = "مصادقة محاكية · Debug Simulator فقط"
            if let initialOutcome = testOutcome {
                let isAction = reason.contains("إعادة المحاولة")
                let outcome = isAction ? (ProcessInfo.processInfo.environment["NIDAA_TEST_ACTION_AUTH"] ?? initialOutcome) : initialOutcome
                if isAction, let change = ProcessInfo.processInfo.environment["NIDAA_TEST_CHANGE"], let details = actionDetails,
                   let first = details.recipients.first {
                    if change == "delete" { deleteContact(first.id) }
                    else { var c = first;if change == "block" { c.state = .blocked } else { c.allowsOutgoing = false };saveContact(c) }
                }
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
        guard storageIssue.isEmpty else { message = "التخزين غير جاهز؛ لم يُنفذ الإجراء.";return }
        let before = simulation, oldScreen = screen
        let oldPalette = frozenPalette, oldIncoming = incomingID, oldPreview = previewRecipient, oldDetails = actionDetails
        do {
            try action()
            if before.alerts != simulation.alerts || before.contacts != simulation.contacts { try repository.save(simulation) }
        } catch {
            simulation = before;screen = oldScreen
            frozenPalette = oldPalette;incomingID = oldIncoming;previewRecipient = oldPreview;actionDetails = oldDetails
            if error is ArchiveError {
                invalidateAuthorization();storageIssue = "فشل حفظ الإجراء؛ لم يُعتمد التغيير ولم تُستبدل النسخة السابقة. أعد محاولة الاستعادة."
                message = storageIssue;return
            }
            switch error as? SimulationError {
            case .noConsent: message = "لا إذن ساري؛ لا إرسال أو استجابة إلى شخص محظور أو غير موافق."
            case .noRecipients: message = "لا مستقبِل مؤهل. اختر شخصًا موافقًا؛ من استجاب أو رفض مستبعد من إعادة المحاولة."
            case .authenticationRequired: message = "يلزم تحقق جديد؛ التأكيد السابق غير صالح."
            case .invalidContact: message = "اكتب اسمًا خياليًا من ١ إلى ٤٠ حرفًا."
            default: message = "الإجراء غير متاح في هذه الحالة؛ راجع الصلاحية والاستجابة."
            }
        }
    }
    private func freezeIfNeeded() { if simulation.hasActive && frozenPalette == nil { frozenPalette = appearance.palette(systemDark: systemDark) } }
    private func releaseIfFinished() { if !simulation.hasActive { frozenPalette = nil } }
}

#if DEBUG && targetEnvironment(simulator)
private final class UITestArchiveIO: ArchiveIO {
    let base: FileArchiveIO
    init(base: FileArchiveIO) { self.base = base }
    func read() throws -> Data? {
        if ProcessInfo.processInfo.arguments.contains("-fail-read") { throw ArchiveError.unreadable }
        return try base.read()
    }
    func replace(with data: Data) throws {
        // Fail the intended retry transaction, not an unrelated nonresponse timer save.
        if ProcessInfo.processInfo.arguments.contains("-fail-write"),
           let archive = try? JSONDecoder().decode(AlertArchive.self, from: data),
           archive.alerts.contains(where: { $0.attempts > 1 }) { throw ArchiveError.writeFailed }
        try base.replace(with: data)
    }
}
#endif

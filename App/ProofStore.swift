import Foundation
import Combine
import UIKit
import ProofCore

@MainActor final class ProofStore: ObservableObject {
    static let shared = ProofStore()
    let authentication = LocalAuthenticationService()
    let notifications = NotificationService()
    let remote = RemoteRegistrationService()
    @Published var permissions = PermissionSnapshot.unknown
    @Published var window: TestWindow?
    @Published var busy = false
    @Published var message = "إثبات تقني غير مختبر على iPhone بعد. لا إرسال تلقائي."
    @Published var authStatus = "لم يُجرَ تحقق"
    @Published var remoteStatus = "Not enabled — لم يُفعّل APNs"
    @Published var deviceToken: String?
    @Published var incidents: [IncidentEvidence] = []
    @Published var log: [String] = []
    private var generation = 0
    private init() {
        notifications.delegate.onObservation = { [weak self] envelope, source in self?.observe(envelope, source) }
        notifications.delegate.mayPresent = { [weak self] envelope in
            guard let self = self else { return false }
            return self.window?.allows(at: Date()) == true && envelope.expiresAt > Date() &&
                !self.incidents.contains(where: { $0.id == envelope.id && $0.cancelledAt != nil })
        }
        if RemoteRegistrationService.compiledIn { remoteStatus = "APNs build — غير مسجّل؛ لا مزود متصل" }
    }
    func refresh() async { permissions = await notifications.settings() }
    func requestPermission() async {
        guard !busy else { return };busy = true;defer { busy = false }
        do { try await notifications.requestPermission(); message = "قُرئت نتيجة إذن النظام؛ ليست إثبات وصول." }
        catch { message = "تعذّر طلب إذن الإشعارات. أعد المحاولة يدويًا أو راجع الإعدادات." }
        await refresh()
    }
    func confirmWindow(alias: String, end: Date, confirmed: Bool) {
        guard !busy else { return }
        let candidate = TestWindow(deviceAlias: alias, startsAt: Date(), endsAt: end)
        guard confirmed, candidate.allows(at: Date()) else { message = "يلزم جهاز محدد ونافذة مستقبلية لا تزيد على ساعتين وتأكيد صريح.";return }
        window = candidate;record("سُجل نطاق الاختبار على الجهاز الحالي؛ لا إشعار حتى الضغط المقصود.")
    }
    func stopWindow() {
        generation += 1;authentication.cancel();window = nil
        notifications.clearThisProof();remote.stop();deviceToken = nil
        for n in incidents.indices { incidents[n].cancel(at: Date()) }
        remoteStatus = "متوقف؛ لا مزود متصل"
        record("أُلغي الاختبار المحلي المعلّق. أوقف المرسل الخارجي أيضًا؛ قد يصل APNs أُرسل سابقًا.")
    }
    func backgrounded() { generation += 1;authentication.cancel();authStatus = "يلزم تحقق جديد لكل إجراء" }
    private func authenticate(_ reason: String) async -> Bool {
        let ticket = generation
        let result = await authentication.authenticate(reason: reason)
        guard ticket == generation else { authStatus = "أُلغي الإجراء أثناء التحقق";return false }
        switch result {
        case .success: authStatus = "نجح تحقق النظام لهذا الإجراء فقط";return true
        case .cancelled: authStatus = "أُلغي التحقق؛ لا إجراء";return false
        case .failed(let error): authStatus = error;return false
        }
    }
    func testAuthentication() async {
        guard !busy else { return };busy = true;defer { busy = false }
        _ = await authenticate("فحص Face ID أو Touch ID أو رمز الجهاز دون إرسال إشعار.")
    }
    func scheduleLocalTest() async {
        guard !busy else { return };busy = true;defer { busy = false }
        let ticket = generation
        guard window?.allows(at: Date(), scheduledFor: Date().addingTimeInterval(20)) == true else {
            message = "أكد الجهاز ونافذة الاختبار أولًا، مع أكثر من ٢٠ ثانية متبقية.";return
        }
        guard await authenticate("السماح بإشعار اختبار محلي واحد بعد ١٥ ثانية.") else { return }
        await refresh()
        guard ticket == generation, permissions.permitsScheduling,
              let w = window, w.allows(at: Date(), scheduledFor: Date().addingTimeInterval(20)) else {
            message = "لم تُجدول الرسالة: الإذن أو نافذة الاختبار أو صلاحية الإجراء لم تعد متاحة.";return
        }
        let envelope = ProofEnvelope(id: UUID(), kind: .local, expiresAt: w.endsAt)
        var evidence = IncidentEvidence(id: envelope.id, kind: .local, expiresAt: envelope.expiresAt)
        do {
            try await notifications.schedule(envelope, after: 15)
            guard ticket == generation, window?.allows(at: Date()) == true else {
                notifications.cancel(envelope.id);message = "أُلغي الطلب بعد تغير نطاق الاختبار.";return
            }
            evidence.recordLocalScheduling(at: Date());incidents.insert(evidence, at: 0)
            record("قُبلت الجدولة المحلية فقط. راقب العرض والصوت؛ هذا ليس وصول APNs.")
        } catch { record("فشلت الجدولة المحلية؛ لم يثبت وصول أي إشعار.") }
    }
    func registerRemote() async {
        guard !busy, RemoteRegistrationService.compiledIn else { return }
        busy = true;defer { busy = false };let ticket = generation
        guard window?.allows(at: Date()) == true else { message = "يلزم تأكيد جهاز ونافذة الاختبار.";return }
        guard await authenticate("إتاحة تسجيل جهاز الاختبار لدى APNs دون إرسال أي تنبيه.") else { return }
        guard ticket == generation, window?.allows(at: Date()) == true else { return }
        deviceToken = nil;remoteStatus = "جارٍ التسجيل لدى APNs؛ ليس طلب إرسال";remote.register()
    }
    func registered(_ token: Data) {
        guard window?.allows(at: Date()) == true else { remote.stop();return }
        deviceToken = token.map { String(format: "%02x", $0) }.joined()
        remoteStatus = "سُجّل الجهاز؛ إرسال APNs وإقرار الخادم Not enabled"
        record("وصل رمز الجهاز من APNs؛ محفوظ في الذاكرة فقط ولا يُرسل إلى خادم.")
    }
    func registrationFailed() { deviceToken = nil;remoteStatus = "فشل تسجيل APNs؛ راجع الاتصال والتوقيع. لا إعادة تلقائية." }
    func inspectDelivered() async {
        for envelope in await notifications.delivered() { observe(envelope, .notificationCenterInventory) }
        record("فُحص مركز الإشعارات. وقت الرصد الحالي لا يثبت وقت الوصول أو تشغيل الصوت.")
    }
    private func observe(_ envelope: ProofEnvelope, _ source: Observation) {
        if let index = incidents.firstIndex(where: { $0.id == envelope.id }) {
            incidents[index].observe(source, at: Date())
        } else {
            var evidence = IncidentEvidence(id: envelope.id, kind: envelope.kind, expiresAt: envelope.expiresAt)
            evidence.observe(source, at: Date());incidents.insert(evidence, at: 0)
        }
        // No server acknowledgement and no implicit human response.
    }
    func respond(to id: UUID) async {
        guard !busy else { return };busy = true;defer { busy = false }
        guard window?.allows(at: Date()) == true else { message = "نافذة الاختبار غير متاحة.";return }
        guard await authenticate("تسجيل استجابة بشرية لهذا الاختبار فقط، دون إرسالها إلى شخص آخر.") else { return }
        guard window?.allows(at: Date()) == true, let n = incidents.firstIndex(where: { $0.id == id }) else { return }
        if incidents[n].respond(at: Date(), authenticated: true) {
            record("سُجلت استجابة صريحة محليًا فقط؛ لا مزود أو شخص آخر متصل.")
        } else { message = "لا استجابة: الاختبار غير مرصود أو منتهٍ أو ملغى أو سبق الرد عليه." }
    }
    func cancel(_ id: UUID) {
        notifications.cancel(id)
        if let n = incidents.firstIndex(where: { $0.id == id }) { incidents[n].cancel(at: Date()) }
        record("أُلغي السجل المحلي. لا سحب عن بُعد ولا ضمان إيقاف صوت بدأه النظام.")
    }
    private func record(_ text: String) {
        message = text;log.insert(Date().formatted(date: .omitted, time: .standard) + " — " + text, at: 0)
        if log.count > 50 { log.removeLast() }
    }
}

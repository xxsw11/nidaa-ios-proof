import SwiftUI
import UIKit
import ProofCore

@MainActor struct ProofView: View {
    @ObservedObject var store: ProofStore
    @State private var alias = ""
    @State private var end = Date().addingTimeInterval(1800)
    @State private var scopeConfirmed = false
    @State private var showToken = false
    private let yellow = Color(red: 1, green: 220.0/255, blue: 56.0/255)
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("نداء — NIDAA").font(.largeTitle.bold()).foregroundStyle(yellow)
                    Text("إثبات iPhone · اختبار عرض وصوت فقط").font(.headline)
                    Text("\(UIDevice.current.model) · iOS \(UIDevice.current.systemVersion)").font(.caption)
                    Text("لا خدمة طوارئ أو مستجيب متصل. الوظائف الأصلية مكتوبة، ونتائج الجهاز لم تُسجل بعد. واجهات v06 محفوظة منفصلة.")
                    Text(store.message).accessibilityIdentifier("proof-status")
                }
                Section("إذن الإشعارات — قراءة فعلية من النظام") {
                    status("الإذن", store.permissions.authorization)
                    status("التنبيهات", store.permissions.alerts)
                    status("الصوت", store.permissions.sounds)
                    status("شاشة القفل", store.permissions.lockScreen)
                    status("مركز الإشعارات", store.permissions.center)
                    status("التلخيص المجدول", store.permissions.scheduledDelivery)
                    status("إعداد Critical Alerts", store.permissions.critical)
                    action("طلب إذن الإشعارات") { await store.requestPermission() }
                    action("تحديث الحالة") { await store.refresh() }
                    Button("فتح إعدادات التطبيق") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }.frame(minHeight: 44)
                    Text("الإذن لا يثبت العرض أو تشغيل الصوت، ولا يكشف مفتاح الصامت أو كل إعدادات Focus.").font(.footnote)
                }
                Section("التحقق الأصلي") {
                    Text(store.authStatus)
                    action("فحص Face ID / Touch ID أو رمز الجهاز") { await store.testAuthentication() }
                    Text("وسيلة النظام فقط؛ لا حقل رمز داخل التطبيق. النجاح لا يفتح جلسة إرسال دائمة.").font(.footnote)
                }
                Section("نطاق اختبار مؤكد على هذا الجهاز") {
                    TextField("اسم مستعار للجهاز، دون اسم شخص", text: $alias)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    DatePicker("نهاية النافذة", selection: $end, displayedComponents: [.date, .hourAndMinute])
                    Toggle("أؤكد هذا الجهاز وهذه النافذة وأسمح بصوت الاختبار", isOn: $scopeConfirmed)
                    Button("تسجيل النطاق — دون إرسال") { store.confirmWindow(alias: alias, end: end, confirmed: scopeConfirmed) }
                        .disabled(store.busy || !scopeConfirmed).frame(minHeight: 44)
                    if let window = store.window {
                        Text("الجهاز: \(window.deviceAlias)")
                        Text("النهاية: \(window.endsAt.formatted())")
                    } else { Text("Not enabled — لا نطاق اختبار مؤكد") }
                    Text("التأكيد هنا يسجل موافقة مشغّل الاختبار. عند تشغيل وكيل يلزم تأكيد المستخدم للجهاز والنافذة أولًا. الحد ساعتان، ولا يحفظ النطاق بعد إغلاق التطبيق.").font(.footnote)
                }
                Section("اختبار محلي منفصل") {
                    action("تحقق ثم جدولة اختبار واحد بعد ١٥ ثانية") { await store.scheduleLocalTest() }
                    Text("الإشعار يستخدم صوت النظام العادي. لا إثبات لتجاوز الصامت، ولا دليل على نجاح APNs.").font(.footnote)
                    action("رصد إشعارات مركز الإشعارات") { await store.inspectDelivered() }
                }
                Section("اختبار APNs البعيد") {
                    Text(store.remoteStatus)
                    if RemoteRegistrationService.compiledIn {
                        action("تحقق ثم سجّل هذا الجهاز لدى APNs") { await store.registerRemote() }
                        if let token = store.deviceToken {
                            Toggle("إظهار رمز الجهاز للنقل الآمن إلى بيئة الاختبار", isOn: $showToken)
                            if showToken { Text(token).font(.caption.monospaced()).textSelection(.enabled).privacySensitive().environment(\.layoutDirection, .leftToRight) }
                        }
                    } else { Text("افتح مسار APNs فقط بعد إعداد التوقيع المصرح به. لا entitlement للدفع في المسار المحلي.").font(.footnote) }
                    Text("قبول خدمة الإرسال: Not enabled — يُسجل من دليل المزود خارجيًا. إقرار خادمي من الجهاز: Not enabled. الرصد المحلي والاستجابة البشرية حقائق منفصلة.").font(.footnote)
                    Text("Critical Alerts: Awaiting approval — لم يُقدّم طلب Apple؛ لا entitlement أو طلب إذن حرج في هذه الحزمة.").font(.footnote)
                }
                Section("سجلات الاختبار — في ذاكرة الجلسة") {
                    if store.incidents.isEmpty { Text("لا نتائج وصول أو استجابة بعد") }
                    ForEach(store.incidents) { incident in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(incident.kind == .local ? "اختبار محلي" : "اختبار APNs").font(.headline)
                            Text(incident.id.uuidString).font(.caption.monospaced()).textSelection(.enabled)
                            status("قبول جدولة محلية", stamp(incident.locallyScheduledAt))
                            status("قبول مزود APNs", "غير متصل؛ راجع دليل المزود")
                            status("رصد على الجهاز", stamp(incident.observedAt))
                            status("مصدر الرصد", observation(incident.observation))
                            status("استجابة بشرية صريحة", stamp(incident.humanRespondedAt))
                            if incident.cancelledAt != nil { Text("أُلغي الاختبار محليًا") }
                            Text("الصلاحية حتى: \(incident.expiresAt.formatted())").font(.footnote)
                            action("تحقق وسجّل استجابتي لهذا الاختبار") { await store.respond(to: incident.id) }
                            Button("إلغاء الاختبار المحلي", role: .destructive) { store.cancel(incident.id) }.frame(minHeight: 44)
                        }.padding(.vertical, 8)
                    }
                }
                Section("سجل الإجراءات") { ForEach(Array(store.log.enumerated()), id: \.offset) { entry in Text(entry.element).font(.footnote) } }
            }
            .tint(yellow)
            .navigationTitle("إثبات نداء")
            .safeAreaInset(edge: .bottom) {
                Button("إيقاف الاختبارات وإلغاء المحلي المعلّق", role: .destructive) { store.stopWindow(); scopeConfirmed = false;showToken = false }
                    .frame(maxWidth: .infinity, minHeight: 48).padding(.horizontal).background(.regularMaterial)
            }
        }
    }
    private func status(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(title).font(.caption); Text(value) }
    }
    private func action(_ title: String, perform: @escaping () async -> Void) -> some View {
        Button(title) { Task { await perform() } }.disabled(store.busy).frame(minHeight: 44)
    }
    private func stamp(_ date: Date?) -> String { date?.formatted() ?? "لم يُسجّل" }
    private func observation(_ value: Observation?) -> String {
        switch value {
        case .foregroundCallback: return "رد اتصال أثناء الواجهة الأمامية؛ لا يثبت سماع الصوت"
        case .notificationOpened: return "فتح الإشعار؛ ليس قبولًا بشريًا للمساعدة"
        case .notificationCenterInventory: return "رصد لاحق بمركز الإشعارات؛ وقت الوصول غير مقاس"
        case nil: return "لا رصد بعد"
        }
    }
}

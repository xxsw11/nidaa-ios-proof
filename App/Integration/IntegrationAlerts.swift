#if DEBUG
import SwiftUI
import NidaaIntegration

@MainActor struct IntegrationAlertsView: View {
    @ObservedObject var store: IntegrationStore
    var body: some View {
        NidaaCard {
            Text("نداء مشترك في البيئة المحلية").font(.title2.bold())
            Text("اختر حسابًا وافق على الاستقبال منك. تُحفظ الحالة على الخادم المحلي؛ لا تُرسل إشعارات نظام.")
            if store.eligible.isEmpty { Text("لا يوجد مستقبِل بموافقة سارية. أنشئ دعوة وأكمل قبولها أولًا.") }
            ForEach(store.eligible, id: \.self) { id in
                Toggle(store.label(id), isOn: Binding(get: { store.selected.contains(id) }, set: { if $0 { store.selected.insert(id) } else { store.selected.remove(id) } }))
                    .accessibilityIdentifier("integrationSelect-" + id.uuidString.lowercased())
                    .disabled(store.busy || store.pending)
            }
            Text("صلاحية النداء: ١٠ دقائق. إنشاء النداء وإعادة المحاولة وإضافة مستقبِل تحتاج تحقق جهاز جديدًا ثم تأكيدًا مستقلًا.").font(.footnote)
            NidaaButton(title: "تحقق لإنشاء النداء", icon: "faceid", id: "integrationPrepareCreate") {
                Task {
                    await store.prepare("create_alert", payload: ["recipient_ids": .array(store.selected.sorted { $0.uuidString < $1.uuidString }.map { .string($0.uuidString) }), "expires_at": .integer(Int(Date().timeIntervalSince1970) + 600)], title: "إنشاء نداء تجريبي إلى \(store.selected.count) مستقبِل؟")
                }
            }.disabled(store.selected.isEmpty || !store.canMutate)
        }
        if store.alerts.isEmpty { Text("لا توجد نداءات مشتركة ظاهرة لهذا الحساب.").accessibilityIdentifier("integrationEmptyAlerts") }
        ForEach(store.alerts) { alert in IntegrationAlertCard(store: store, alert: alert) }
    }
}

@MainActor struct IntegrationAlertCard: View {
    @ObservedObject var store: IntegrationStore
    let alert: TrialAlert
    @State private var closeConfirmation = false
    private var mine: Bool { alert.sender == store.accountID }
    private var ownResponse: TrialRecipient? { alert.recipients.first { $0.id == store.accountID } }
    private var base: [String: JSONValue] { ["alert_id": .string(alert.id.uuidString), "expected_version": .integer(alert.version)] }
    var body: some View {
        NidaaCard {
            Label(mine ? "نداء صادر" : "نداء وارد", systemImage: mine ? "arrow.up.circle" : "arrow.down.circle").font(.headline)
            Text(IntegrationLabels.state(alert.state)).font(.title3.bold()).accessibilityIdentifier("integrationAlertState")
            Text("المرسل: \(store.label(alert.sender))").font(.footnote)
            ForEach(alert.recipients) { recipient in
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.label(recipient.id)).font(.headline)
                    Label(recipient.provider ? "قبله محوّل الإرسال المزيف" : "لم يسجل المحوّل المزيف قبولًا", systemImage: "shippingbox")
                    Label(recipient.acknowledged ? "سجّل التطبيق الاستلام" : "لم يسجل التطبيق الاستلام", systemImage: "iphone")
                    Label(recipient.opened ? "فُتحت التفاصيل" : "لم تُفتح التفاصيل", systemImage: "eye")
                    Label(IntegrationLabels.state(recipient.response), systemImage: "person.crop.circle")
                        .accessibilityIdentifier("integrationHumanResponse")
                }.font(.footnote).accessibilityElement(children: .contain)
            }
            Text("قبول المحوّل ليس إقرار الجهاز. إقرار التطبيق وفتح التفاصيل ليسا استجابة بشرية.").font(.caption)
            if alert.state == "active" {
                if mine { senderActions }
                else { recipientActions }
            }
        }
        .alert("إنهاء هذه الحالة؟", isPresented: $closeConfirmation) {
            Button("إنهاء الحالة") { var payload = base; payload["state"] = .string("resolved"); Task { await store.command("close_alert", payload: payload) } }
            Button("إلغاء النداء", role: .destructive) { var payload = base; payload["state"] = .string("cancelled"); Task { await store.command("close_alert", payload: payload) } }
            Button("رجوع", role: .cancel) {}
        } message: { Text("لا تُغلق الحالة تلقائيًا باستلام التطبيق أو باستجابة شخص. هذا تأكيد صريح من المرسل.") }
    }
    @ViewBuilder private var senderActions: some View {
        NidaaButton(title: "تحقق لإعادة المحاولة", icon: "arrow.clockwise", secondary: true, id: "integrationPrepareRetry") {
            Task { await store.prepare("retry", payload: base, title: "إعادة المحاولة لمن لم يستجب أو يرفض فقط؟ يراجع الخادم حد المحاولتين وفترة الانتظار.") }
        }.disabled(!store.canMutate)
        if !store.selected.subtracting(Set(alert.recipients.map(\.id))).isEmpty {
            NidaaButton(title: "تحقق لإضافة الاختيار الجديد", icon: "person.badge.plus", secondary: true, id: "integrationPrepareAdd") {
                var payload = base
                payload["recipient_ids"] = .array(store.selected.subtracting(Set(alert.recipients.map(\.id))).sorted { $0.uuidString < $1.uuidString }.map { .string($0.uuidString) })
                Task { await store.prepare("add_recipients", payload: payload, title: "إضافة الحسابات المختارة التي لم تكن ضمن هذا النداء؟") }
            }.disabled(!store.canMutate)
        }
        NidaaButton(title: "إنهاء الحالة صراحةً", icon: "checkmark.circle", secondary: true, id: "integrationCloseAlert") { closeConfirmation = true }.disabled(!store.canMutate)
    }
    @ViewBuilder private var recipientActions: some View {
        NidaaButton(title: "تسجيل استلام التطبيق", icon: "iphone", secondary: true, id: "integrationAcknowledge") { acknowledge("app_acknowledged") }.disabled(!store.canMutate)
        NidaaButton(title: "فتح التفاصيل وتسجيل الفتح", icon: "eye", secondary: true, id: "integrationOpenAlert") { acknowledge("opened") }.disabled(!store.canMutate)
        if ownResponse?.response == "none" {
            NidaaButton(title: "سأتولى المساعدة", icon: "hand.raised", id: "integrationRespond") { respond("responding") }.disabled(!store.canMutate)
            NidaaButton(title: "لا أستطيع المساعدة", icon: "xmark", secondary: true, id: "integrationDeclineResponse") { respond("declined") }.disabled(!store.canMutate)
        }
    }
    private func acknowledge(_ kind: String) {
        Task { await store.command("acknowledge", payload: ["alert_id": .string(alert.id.uuidString), "event_id": .string(UUID().uuidString), "kind": .string(kind)]) }
    }
    private func respond(_ value: String) {
        var payload = base; payload["response"] = .string(value)
        Task { await store.command("respond", payload: payload) }
    }
}
#endif

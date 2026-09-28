import SwiftUI
import ProofCore

@MainActor struct ComposeView: View {
    @ObservedObject var store: ExperienceStore
    var body: some View {
        ScreenBody {
            SimulationNotice(authSimulation: store.simulationAuthentication)
            Text(store.confirmationReady ? "راجع ثم أكّد" : "من تحتاج الآن؟").font(.largeTitle.bold())
            if store.confirmationReady {
                NidaaCard {
                    Label("تحقق ناجح لهذا الإجراء فقط", systemImage: "checkmark.shield")
                    Text(store.authLabel).font(.footnote)
                    Text(store.simulation.contacts.filter { store.selected.contains($0.id) }.map(\.name).joined(separator: "، "))
                    Text(store.assistance.title)
                    Text("صلاحية التأكيد ١٥ ثانية. التأكيد ينشئ محاكاة فقط دون أي إرسال حقيقي.").font(.footnote)
                }
                NidaaButton(title: "أؤكد إنشاء النداء المحاكى", icon: "checkmark", id: "confirmAlert") { store.confirmSend() }
                NidaaButton(title: "إلغاء دون إنشاء", icon: "xmark", secondary: true, id: "cancelCompose") { store.cancelCompose() }
            } else {
                Text("الموافقة السارية لازمة لكل شخص. لا حاجة إلى كتابة معلومات شخصية.")
                ForEach(store.simulation.contacts) { c in
                    Toggle(isOn: Binding(get: { store.selected.contains(c.id) }, set: { value in
                        if value { store.selected.insert(c.id) } else { store.selected.remove(c.id) };store.selectionChanged()
                    })) {
                        VStack(alignment: .leading) { Text(c.name).font(.headline);Text(c.canSend ? "إذن ساري" : c.state.title + " · غير متاح للإرسال").font(.footnote) }
                    }.disabled(!c.canSend || store.busy).accessibilityIdentifier("select-\(c.id.uuidString)")
                }
                Picker("نوع المساعدة", selection: $store.assistance) { ForEach(AssistanceKind.allCases,id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.menu)
                    .onChange(of: store.assistance) { _ in store.selectionChanged() }
                NidaaButton(title: store.busy ? "جارٍ التحقق…" : "التحقق قبل التأكيد", icon: "faceid", id: "authenticateSend") { Task { await store.prepareSend() } }
                    .disabled(store.busy || store.selected.isEmpty)
                Text("فتح قفل التطبيق سابقًا لا يكفي لإنشاء النداء.").font(.footnote)
            }
            if !store.message.isEmpty { Text(store.message).accessibilityIdentifier("sendMessage") }
        }.navigationTitle("طلب مساعدة محاكى")
    }
}
@MainActor struct AlertDetailView: View {
    @ObservedObject var store: ExperienceStore
    let id: UUID
    @State private var closeState: LocalAlertState?
    private var alert: LocalAlert? { store.simulation.alerts.first { $0.id == id } }
    var body: some View {
        ScreenBody {
            SimulationNotice(authSimulation: store.simulationAuthentication)
            if let a = alert {
                Text(a.state.title).font(.title.bold()).accessibilityIdentifier("alertState")
                Text(a.kind.title).font(.headline)
                Text(a.id.uuidString).font(.caption.monospaced()).textSelection(.enabled).accessibilityIdentifier("alertIdentifier")
                Text("عدد المحاولات: \(a.attempts)").accessibilityIdentifier("attemptCount").accessibilityValue(String(a.attempts))
                Text("الإنشاء: \(a.createdAt.formatted())").font(.footnote)
                Text("الصلاحية: \(a.expiresAt.formatted())").font(.footnote)
                Text("قبول خدمة إرسال حقيقية: غير مفعّل").font(.footnote)
                if a.nonresponse { NidaaCard { Label("لا استجابة مؤكدة خلال المهلة", systemImage: "exclamationmark.triangle");Text("يمكن تجربة بديل موافق. لا تنتظر هذه المحاكاة للحصول على مساعدة حقيقية.").font(.footnote) } }
                ForEach(a.recipients) { recipient in
                    NidaaCard {
                        HStack { Avatar(name: recipient.name);Text(recipient.name).font(.title2.bold());Spacer() }
                        Label(recipient.stage.title, systemImage: recipient.stage.symbol)
                        if let t = recipient.receivedAt { Text("استلام محاكى: \(t.formatted())").font(.caption) }
                        if let t = recipient.openedAt { Text("فتح: \(t.formatted())").font(.caption) }
                        if let t = recipient.respondedAt { Text("رد صريح: \(t.formatted())").font(.caption) }
                        if a.isActive {
                            if recipient.stage == .sent {
                                NidaaButton(title: "محاكاة وصول إلى \(recipient.name)", icon: "checkmark.circle", secondary: true, id: "receipt-\(recipient.id.uuidString)") { store.transition(id, recipient: recipient.id, to: .received) }
                            }
                            NidaaButton(title: "فتح معاينة المستقبِل", icon: "eye", secondary: true, id: "openRecipient-\(recipient.id.uuidString)") { store.previewRecipient = recipient.id;store.openIncoming(id) }
                        }
                    }
                }
                if a.isActive { alertActions(a) }
                else { Text("حالة نهائية؛ لا إعادة إرسال أو قبول متأخر لهذا النداء.").font(.footnote) }
                if !store.message.isEmpty { Text(store.message).font(.footnote).accessibilityIdentifier("detailMessage") }
                Text("تسلسل الحالة").font(.title2.bold())
                ForEach(a.events) { event in
                    VStack(alignment: .leading,spacing: 5) { Label(event.text, systemImage: "circle.fill");Text(event.at.formatted()).font(.caption) }.padding(.vertical,4)
                }
            }
        }.navigationTitle("متابعة النداء")
        .confirmationDialog("تأكيد الإجراء", isPresented: Binding(get: { closeState != nil },set: { if !$0 { closeState = nil } }),titleVisibility: .visible) {
            Button(closeState == .resolved ? "أؤكد انتهاء الحالة" : "أؤكد إلغاء النداء", role: .destructive) { if let state = closeState { store.closeAlert(id, state: state) };closeState = nil }.accessibilityIdentifier("confirmCloseAlert")
            Button("تراجع",role: .cancel) { closeState = nil }
        } message: { Text("إجراء محلي صريح. الإلغاء ليس إثباتًا للسلامة.") }
    }
    @ViewBuilder private func alertActions(_ a: LocalAlert) -> some View {
        NidaaButton(title: a.silenced ? "أُسكت في المحاكاة · الحالة نشطة" : "إسكات محاكى دون قبول", icon: "speaker.slash", secondary: true, id: "silenceAlert") { store.silence(id) }
        NidaaButton(title: "إنهاء الحالة بتأكيد صريح", icon: "checkmark.seal", id: "resolveAlert") { closeState = .resolved }
        if !a.incoming {
            NidaaButton(title: "إلغاء النداء", icon: "xmark.circle", secondary: true, id: "cancelAlert") { closeState = .cancelled }
            NidaaButton(title: "محاكاة إعادة المحاولة بنفس المعرّف", icon: "arrow.clockwise", secondary: true, id: "retryAlert") { store.selectAction(id, action: .retry) }
            ForEach(store.eligible.filter { c in !a.recipients.contains(where: { $0.id == c.id }) }) { c in
                NidaaButton(title: "استخدام \(c.name) كبديل محاكى", icon: "person.badge.plus", secondary: true, id: "alternative-\(c.id.uuidString)") { store.selectAction(id, action: .addRecipient(c.id)) }
            }
        }
        DisclosureGroup("أدوات وقت المحاكاة") {
            NidaaButton(title: "محاكاة مرور ٢٦ ثانية دون رد", icon: "clock", secondary: true, id: "advanceNoResponse") { store.advance(26) }
            NidaaButton(title: "محاكاة انتهاء الصلاحية", icon: "clock.badge.xmark", secondary: true, id: "expireAlert") { store.advance(301) }
        }
    }
}
@MainActor struct IncomingView: View {
    @ObservedObject var store: ExperienceStore
    let id: UUID
    private var alert: LocalAlert? { store.simulation.alerts.first { $0.id == id } }
    private var recipient: RecipientProgress? { alert?.recipients.first { $0.id == store.previewRecipient } ?? alert?.recipients.first }
    var body: some View {
        ScreenBody {
            SimulationNotice(authSimulation: store.simulationAuthentication)
            Text("نداء وارد").font(.largeTitle.bold())
            Text("محاكاة على هذا الجهاز · دون صوت أو إشعار نظام").font(.footnote)
            if let a = alert {
                Text(a.state.title).font(.headline).accessibilityIdentifier("incomingState")
                if store.locked {
                    NidaaCard { Label("تفاصيل محمية",systemImage: "lock.shield");Text("يوجد نداء محاكى. افتح القفل لرؤية الاسم والتفاصيل والاستجابة.") }
                    NidaaButton(title: "فتح القفل للاستجابة", icon: "faceid", id: "unlockIncoming") { Task { await store.unlock() } }.disabled(store.busy)
                } else if let recipient = recipient {
                    HStack { Avatar(name: recipient.name);Text(a.incoming ? "\(recipient.name) تحتاج المساعدة" : "معاينة \(recipient.name)").font(.title2.bold()) }
                    Label(recipient.stage.title,systemImage: recipient.stage.symbol).accessibilityIdentifier("recipientState")
                    Text("فتح هذه الشاشة لا يعني قبول مسؤولية المساعدة.").font(.footnote)
                    if a.isActive && (recipient.stage == .received || recipient.stage == .opened) {
                        NidaaButton(title: "سأستجيب", icon: "person.fill.checkmark", id: "acceptResponse") { store.transition(id,recipient: recipient.id,to: .responding) }
                        NidaaButton(title: "لا أستطيع الاستجابة", icon: "person.fill.xmark", secondary: true, id: "declineResponse") { store.transition(id,recipient: recipient.id,to: .declined) }
                    }
                    if recipient.stage == .declined { Text("أُبلغ المرسل بالرفض في المحاكاة؛ الحالة مستمرة ويمكن اختيار بديل.") }
                    if recipient.stage == .responding { Text("قبولك لا يغلق الحالة. أكمل المتابعة ثم أنهِ الحالة صراحةً.") }
                    if recipient.stage == .sent { Text("لم تُحاكَ مرحلة الاستلام بعد؛ عُد للمتابعة أولًا.") }
                    NidaaButton(title: "متابعة وتفاصيل الحالة",icon: "list.bullet",secondary: true,id: "incomingDetails") { store.screen = .alert(id) }
                }
                if a.isActive {
                    NidaaButton(title: "إسكات محاكى دون قبول", icon: "speaker.slash", secondary: true, id: "incomingSilence") { store.silence(id) }
                    NidaaButton(title: "إخفاء المعاينة دون إنهاء الحالة",icon: "eye.slash",secondary: true,id: "dismissIncoming") { store.silence(id,dismiss: true) }
                }
                if !store.message.isEmpty { Text(store.message).font(.footnote) }
            }
        }.navigationTitle("الوارد المحاكى")
        .onAppear { markOpened() }.onChange(of: store.locked) { _ in markOpened() }
    }
    private func markOpened() {
        if !store.locked, let p = recipient, p.stage == .received { store.transition(id,recipient: p.id,to: .opened) }
    }
}

@MainActor struct AlertActionView: View {
    @ObservedObject var store: ExperienceStore
    var body: some View {
        ScreenBody {
            SimulationNotice(authSimulation: store.simulationAuthentication)
            if let details = store.actionDetails {
                Text(details.action == .retry ? "إعادة محاولة محاكية" : "إضافة مستقبِل محاكى").font(.title.bold())
                Text(details.alertID.uuidString).font(.caption.monospaced()).accessibilityIdentifier("actionIdentifier")
                NidaaCard {
                    Text("المستقبِلون المؤهلون لهذا الإجراء").font(.headline)
                    ForEach(details.recipients) { person in Text(person.name).accessibilityIdentifier("actionRecipient-\(person.id.uuidString)") }
                    Text("لا تُعاد المحاولة لمن استجاب أو رفض. المعرّف والردود والمهلة الأصلية لا تتغير.").font(.footnote)
                    Text("الصلاحية الأصلية: \(details.expiresAt.formatted())").font(.footnote)
                }
                if store.actionReady {
                    Label("تحقق جديد ناجح · راجع ثم أكّد خلال ١٥ ثانية", systemImage: "checkmark.shield")
                    Text(store.authLabel).font(.footnote)
                    NidaaButton(title: "أؤكد تنفيذ هذا الإجراء مرة واحدة", icon: "checkmark", id: "confirmAction") { store.confirmAction() }
                } else {
                    NidaaButton(title: store.busy ? "جارٍ التحقق…" : "تحقق جديد لهذا الإجراء", icon: "faceid", id: "authenticateAction") { Task { await store.prepareAction() } }.disabled(store.busy)
                }
                NidaaButton(title: "تراجع دون تنفيذ", icon: "xmark", secondary: true, id: "cancelAction") { store.cancelAction() }
            }
            if !store.message.isEmpty { Text(store.message).accessibilityIdentifier("actionMessage") }
        }.navigationTitle("مراجعة الإجراء")
    }
}

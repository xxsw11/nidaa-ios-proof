import SwiftUI
import ProofCore

@MainActor struct HomeView: View {
    @ObservedObject var store: ExperienceStore
    @Environment(\.nidaaPalette) private var palette
    var body: some View {
        GeometryReader { geometry in
        ScreenBody {
            SimulationNotice(authSimulation: store.simulationAuthentication)
            HStack { Text("نداء  NIDAA").font(.title.bold()).foregroundStyle(palette.accentInk.color);Spacer()
                Button { store.lockNow() } label: { Image(systemName: "lock").font(.title2).frame(width: 48,height: 48) }.accessibilityLabel("قفل التطبيق").accessibilityIdentifier("lockApp") }
            Text("دائرتك قريبة.\nحين تحتاجها.").font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
            NidaaCard {
                Label("الجاهزية المادية غير مختبرة", systemImage: "shield.lefthalf.filled").font(.headline)
                Text("الإذن أو نجاح المحاكاة لا يثبتان وصول المساعدة.").font(.footnote)
                NidaaButton(title: "فحص الجاهزية", icon: "checklist", secondary: true, id: "readiness") { store.screen = .readiness }
            }
            VStack(spacing: 14) {
                Button { store.startCompose() } label: {
                    VStack(spacing: 12) { Image(systemName: "bell").font(.largeTitle);Text("طلب مساعدة").font(.title.bold()).multilineTextAlignment(.center) }
                        .foregroundStyle(palette.buttonInk.color).padding(38).frame(minWidth: 220,minHeight: 220)
                        .background(Color(hex: palette.button)).clipShape(Circle())
                        .overlay(Circle().stroke(palette.ink.color, lineWidth: 2))
                }.buttonStyle(.plain).accessibilityIdentifier("startAlert").accessibilityHint("بدء محاكاة؛ يلزم اختيار وتحقق وتأكيد مستقل")
                Text("محاكاة فقط · تحقق مستقل قبل كل إنشاء").font(.footnote)
            }.frame(maxWidth: .infinity).padding(.vertical, 12)
            Text("دائرة النجدة").font(.title2.bold())
            ForEach(store.simulation.contacts.prefix(3)) { c in
                HStack { Avatar(name: c.name);VStack(alignment: .leading) { Text(c.name).font(.headline);Text(c.state.title).font(.caption) };Spacer() }
            }
            if let last = store.simulation.alerts.first {
                NidaaCard { Text("آخر نداء").font(.headline);Text(last.state.title);Text(last.createdAt.formatted()).font(.footnote)
                    NidaaButton(title: "متابعة النداء", icon: "arrow.up.left", id: "latestAlert") { store.screen = .alert(last.id) } }
            }
            NidaaButton(title: "معاينة نداء وارد", icon: "bell.badge", secondary: true, id: "previewIncoming") { store.simulateIncoming() }
            if !store.message.isEmpty { Text(store.message).font(.footnote).accessibilityIdentifier("statusMessage") }
        }.overlay(alignment: .top) {
            // Keep scrolled content out of the status-bar reading area.
            Color(hex: palette.background).frame(height: geometry.safeAreaInsets.top)
                .offset(y: -geometry.safeAreaInsets.top).allowsHitTesting(false).accessibilityHidden(true)
        }
        }.navigationBarHidden(true)
    }
}
@MainActor struct ContactsView: View {
    @ObservedObject var store: ExperienceStore
    var body: some View {
        ScreenBody {
            SimulationNotice(authSimulation: store.simulationAuthentication)
            Text("شخصيات خيالية فقط. لا رفع لدفتر العناوين أو دعوة حقيقية.").font(.footnote)
            NidaaButton(title: "إضافة شخص خيالي", icon: "person.badge.plus", id: "addContact") { store.screen = .editContact(nil) }
            ForEach(store.simulation.contacts) { c in
                NidaaCard {
                    HStack { Avatar(name: c.name);VStack(alignment: .leading, spacing: 6) { Text(c.name).font(.title2.bold());Label(c.state.title, systemImage: c.canSend ? "checkmark.shield" : "person.crop.circle.badge.questionmark") };Spacer() }
                    Text("يسمح بتنبيهه: \(c.canSend ? "نعم" : "لا") · يسمح بتنبيهي: \(c.canReceive ? "نعم" : "لا")").font(.footnote)
                    NidaaButton(title: "إدارة \(c.name)", icon: "pencil", secondary: true, id: "edit-\(c.id.uuidString)") { store.screen = .editContact(c.id) }
                }
            }
        }.navigationTitle("دائرة النجدة")
    }
}
@MainActor struct ContactEditor: View {
    @ObservedObject var store: ExperienceStore
    @State var contact: TrustedContact
    @State private var showDelete = false
    var body: some View {
        ScreenBody {
            Text("دعوة وموافقة محاكيتان؛ لا تُرسل رسالة لأي شخص.").font(.footnote)
            TextField("الاسم الخيالي", text: $contact.name).textFieldStyle(.roundedBorder).accessibilityIdentifier("contactName")
            Picker("حالة الدعوة", selection: $contact.state) { ForEach(InvitationState.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.menu).accessibilityIdentifier("invitationState")
            if contact.state == .accepted {
                Toggle("محاكاة: وافق هذا الشخص على استقبال ندائي", isOn: $contact.allowsOutgoing).accessibilityIdentifier("outgoingConsent")
                Toggle("أسمح لهذا الشخص بتنبيهي في المحاكاة", isOn: $contact.allowsIncoming).accessibilityIdentifier("incomingConsent")
            }
            Text("كل اتجاه له إذن مستقل. المعلّق والمرفوض والمحظور لا يتلقون طلبًا. الحظر يسحب الإذنين؛ القبول مجددًا يحتاج تحديدهما من جديد.").font(.footnote)
            NidaaButton(title: "حفظ الشخص", icon: "checkmark", id: "saveContact") { store.saveContact(contact) }
            if store.simulation.contacts.contains(where: { $0.id == contact.id }) {
                NidaaButton(title: "سحب الموافقة وحظر", icon: "hand.raised", secondary: true, id: "blockContact") { contact.state = .blocked;contact.allowsOutgoing = false;contact.allowsIncoming = false;store.saveContact(contact) }
                NidaaButton(title: "حذف الشخص", icon: "trash", secondary: true, id: "deleteContact") { showDelete = true }
            }
            Text(store.message).font(.footnote)
            Button("شروط الاستخدام") { store.screen = .terms }.frame(minHeight: 44)
        }
        .onChange(of: contact.state) { if $0 != .accepted { contact.allowsOutgoing = false;contact.allowsIncoming = false } }
        .navigationTitle("إدارة الشخص")
        .alert("حذف الشخص من الدائرة؟", isPresented: $showDelete) {
            Button("حذف", role: .destructive) { store.deleteContact(contact.id) }.accessibilityIdentifier("confirmDelete")
            Button("إلغاء", role: .cancel) {}
        } message: { Text("لن يمكن تنبيهه مجددًا. قد تبقى لقطة اسمه في السجل المحلي حتى إعادة ضبط البيانات.") }
    }
}
@MainActor struct HistoryView: View {
    @ObservedObject var store: ExperienceStore
    var body: some View {
        ScreenBody {
            SimulationNotice(authSimulation: store.simulationAuthentication)
            Text("يُحفظ السجل على هذا الجهاز ويُستعاد بعد إعادة التشغيل دون إرسال تلقائي.").font(.footnote)
            if store.simulation.alerts.isEmpty { Label("لا نداءات محفوظة", systemImage: "clock").accessibilityIdentifier("emptyHistory") }
            ForEach(store.simulation.alerts) { a in
                NidaaCard { Label(a.incoming ? "وارد محاكى" : "صادر محاكى", systemImage: a.incoming ? "arrow.down.left" : "arrow.up.right").font(.headline)
                    Text(a.state.title);Text(a.createdAt.formatted()).font(.footnote)
                    NidaaButton(title: "تفاصيل النداء", icon: "list.bullet", secondary: true, id: "history-\(a.id.uuidString)") { store.screen = .alert(a.id) } }
            }
        }.navigationTitle("سجل النداءات")
    }
}

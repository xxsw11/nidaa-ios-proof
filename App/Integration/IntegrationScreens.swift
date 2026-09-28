#if DEBUG
import SwiftUI
import UIKit
import NidaaIntegration

@MainActor struct IntegrationRoot: View {
    @ObservedObject var store: IntegrationStore
    @Environment(\.scenePhase) private var phase
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var page = "account"
    var body: some View {
        ScrollViewReader { reader in
        ScreenBody {
            Text("تجربة الربط المحلي").font(.largeTitle.bold())
            NidaaCard {
                Label(store.isMock ? "MOCK · محاكاة واجهة فقط" : "وضع الربط المحلي", systemImage: "testtube.2")
                    .font(.headline).accessibilityIdentifier("integrationMode")
                Text(store.isMock ? "الحسابات والنتائج التالية خيالية داخل الواجهة. لا يثبت هذا اختبارًا من المحاكي إلى الخادم." : "Supabase Auth وPostgreSQL على هذا المضيف فقط. شغّل البيئة المحلية أولًا؛ لا يوجد اتصال بخدمة مستضافة.")
                    .font(.footnote)
                Text("الإرسال مزيف للاختبار · APNs غير مفعّل · لا إشعار أو صوت على هاتف.").font(.footnote)
            }
            if !store.message.isEmpty {
                Text(store.message).font(.callout).accessibilityIdentifier("integrationMessage")
            }
            if store.pending { unknownCard.id("integration-pending-step") }
            if store.busy { ProgressView("جارٍ تنفيذ الطلب…").accessibilityIdentifier("integrationBusy") }
            if store.accountID != nil {
                Picker("قسم تجربة الربط", selection: $page) {
                    Text("الحساب").tag("account")
                    Text("الموافقات").tag("contacts")
                    Text("النداءات المشتركة").tag("alerts")
                }.pickerStyle(.menu).accessibilityIdentifier("integrationSection")
                navigationLayout {
                    Button("الحساب") { page = "account" }.accessibilityIdentifier("integrationAccountTab")
                    Button("الموافقات") { page = "contacts" }.accessibilityIdentifier("integrationContactsTab")
                    Button("النداءات") { page = "alerts" }.accessibilityIdentifier("integrationAlertsTab")
                }.font(.footnote).buttonStyle(.bordered).fixedSize(horizontal: false, vertical: true)
                if page == "contacts" { IntegrationConsentView(store: store) }
                else if page == "alerts" { IntegrationAlertsView(store: store) }
                else { IntegrationAccountView(store: store) }
                NidaaButton(title: "تحديث من الخادم", icon: "arrow.clockwise", secondary: true, id: "integrationRefresh") { Task { await store.refresh() } }.disabled(store.busy)
            } else { IntegrationAuthView(store: store) }
            if let confirmation = store.confirmation {
                NidaaCard {
                    Label("تأكيد مستقل بعد التحقق", systemImage: "checkmark.shield").font(.headline)
                    Text(confirmation.title)
                    Text("التأكيد صالح لمدة دقيقة لهذه العملية فقط. الانتقال للخلفية أو تغيير الاختيار يُبطله.").font(.footnote)
                    NidaaButton(title: "تأكيد الإجراء الآن", icon: "checkmark", id: "integrationConfirm") { Task { await store.confirm() } }
                    NidaaButton(title: "إلغاء التأكيد", icon: "xmark", secondary: true, id: "integrationCancelConfirm") { store.cancelAuthorization() }
                }.id("integration-confirmation-step")
            }
        }
        .onChange(of: store.confirmation?.deadline) { deadline in
            if deadline != nil {
                withAnimation(.easeInOut(duration: 0.2)) { reader.scrollTo("integration-confirmation-step", anchor: .top) }
            }
        }
        .onChange(of: store.verifying) { verifying in
            if verifying {
                withAnimation(.easeInOut(duration: 0.2)) { reader.scrollTo("integration-verification-step", anchor: .top) }
            }
        }
        .onChange(of: store.pending) { pending in
            if pending {
                withAnimation(.easeInOut(duration: 0.2)) { reader.scrollTo("integration-pending-step", anchor: .top) }
            }
        }
        }
        .navigationTitle("الربط المحلي · تجريبي")
        .interactiveDismissDisabled()
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("تم") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }.accessibilityIdentifier("integrationKeyboardDone")
            }
        }
        .task { await store.restore() }
        .onChange(of: page) { _ in store.cancelAuthorization() }
        .onChange(of: phase) { if $0 == .background { store.backgrounded() } }
        .onDisappear { store.close() }
        .alert("تحقق جهاز محاكى للاختبار", isPresented: $store.mockAuthenticationPrompt) {
            Button("محاكاة النجاح") { store.answerMockAuthentication(true) }.accessibilityIdentifier("integrationMockAuthSuccess")
            Button("محاكاة الفشل") { store.answerMockAuthentication(false) }.accessibilityIdentifier("integrationMockAuthFailure")
            Button("إلغاء", role: .cancel) { store.answerMockAuthentication(false) }
        } message: { Text("Debug Simulator فقط. هذا ليس تسجيل دخول للحساب ولا إثبات Face ID على جهاز فعلي.") }
    }
    private var navigationLayout: AnyLayout {
        textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
    }
    private var unknownCard: some View {
        NidaaCard {
            Label(store.neverSent ? "عملية لم تُرسل" : "نتيجة غير معروفة", systemImage: "questionmark.circle").font(.headline)
            Text(store.neverSent ? "هذه مسودة محفوظة لم تُرسل إلى الخادم. يمكنك إلغاء المسودة، ثم بدء إجراء جديد بتحقق وتأكيد جديدين." : "قد يكون الخادم اعتمد العملية قبل انقطاع الرد. لا توجد إعادة إرسال تلقائية، وتبقى العمليات الجديدة متوقفة حتى تتضح النتيجة.")
            if store.neverSent {
                NidaaButton(title: "إلغاء المسودة غير المرسلة", icon: "xmark", id: "integrationDiscardUnsent") { Task { await store.discardUnsent() } }.disabled(store.busy)
            } else {
                NidaaButton(title: "استعلام عن العملية نفسها", icon: "magnifyingglass", id: "integrationLookup") { Task { await store.lookupPending() } }.disabled(store.busy)
            }
        }
    }
}

@MainActor struct IntegrationAuthView: View {
    @ObservedObject var store: IntegrationStore
    @State private var email = ""
    @State private var password = ""
    @State private var token = ""
    @State private var recovery = false
    private var emailValid: Bool { email.lowercased().hasSuffix(".invalid") && email.contains("@") }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
        NidaaCard {
            Text("حساب خيالي مستقل").font(.title2.bold())
            Text("استخدم بريدًا ينتهي بـ ‎.invalid. التحقق يصل إلى صندوق محلي معزول؛ لا تستخدم بيانات شخصية.").font(.footnote)
            TextField("البريد الخيالي", text: $email).textContentType(.username).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                .textFieldStyle(.roundedBorder).environment(\.layoutDirection, .leftToRight).accessibilityIdentifier("integrationEmail")
            SecureField("كلمة المرور", text: $password).textContentType(.password).keyboardType(.asciiCapable).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder).environment(\.layoutDirection, .leftToRight).accessibilityIdentifier("integrationPassword")
            NidaaButton(title: "تسجيل الدخول", icon: "person.crop.circle", id: "integrationLogin") {
                let value = password; password = ""; Task { await store.signIn(email: email, password: value) }
            }.disabled(!emailValid || password.isEmpty || store.busy)
            NidaaButton(title: "إنشاء حساب تجريبي", icon: "person.badge.plus", secondary: true, id: "integrationSignup") {
                let value = password; password = ""; Task { await store.signUp(email: email, password: value) }
            }.disabled(!emailValid || password.count < 8 || store.busy)
            NidaaButton(title: "طلب استعادة كلمة المرور", icon: "key", secondary: true, id: "integrationRecover") {
                password = ""; recovery = true; Task { await store.recover(email: email) }
            }.disabled(!emailValid || store.busy)
        }
        NidaaCard {
            Text("التحقق من البريد المحلي").font(.headline)
            if store.verifying { Text("بانتظار تحقق البريد؛ لم نفترض وصول رسالة أو نجاح تفعيل.").accessibilityIdentifier("integrationAwaitingVerification") }
            Text("افتح Mailpit على المضيف عبر ‎127.0.0.1:55424، وانسخ قيمة token من رابط التحقق المحلي. لا تُشارك الرمز أو صورته.").font(.footnote)
            Toggle("هذا رمز استعادة كلمة المرور", isOn: $recovery).accessibilityIdentifier("integrationRecoveryKind")
            SecureField("رمز التحقق المحلي", text: $token).textContentType(.oneTimeCode).keyboardType(.asciiCapable).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder).environment(\.layoutDirection, .leftToRight).accessibilityIdentifier("integrationVerificationToken")
            NidaaButton(title: "التحقق من البريد", icon: "checkmark.seal", secondary: true, id: "integrationVerify") {
                let value = token; token = ""; Task { await store.verify(token: value, recovery: recovery) }
            }.disabled(token.isEmpty || store.busy)
        }
        .id("integration-verification-step")
        }
        .onDisappear { password = ""; token = "" }
    }
}

@MainActor struct IntegrationAccountView: View {
    @ObservedObject var store: IntegrationStore
    @State private var password = ""
    @State private var deletion = false
    var body: some View {
        NidaaCard {
            Label("جلسة حساب متحقق من بريده", systemImage: "person.crop.circle.badge.checkmark").font(.headline)
            Text(store.accountName.isEmpty ? "حساب اختبار محلي" : store.accountName)
            Text("هوية الحساب من خدمة المصادقة. Face ID أو رمز الجهاز يحمي تنفيذ الإجراء على هذا الجهاز، ولا يحل محل الحساب.").font(.footnote)
            NidaaButton(title: "تجديد الجلسة", icon: "arrow.clockwise", secondary: true, id: "integrationRefreshSession") { Task { await store.refreshSession() } }.disabled(store.busy)
            SecureField("كلمة مرور جديدة بعد الاستعادة", text: $password).textContentType(.newPassword).keyboardType(.asciiCapable).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder).environment(\.layoutDirection, .leftToRight).accessibilityIdentifier("integrationNewPassword")
            NidaaButton(title: "حفظ كلمة المرور الجديدة", icon: "key", secondary: true, id: "integrationUpdatePassword") {
                let value = password; password = ""; Task { await store.updatePassword(value) }
            }.disabled(password.count < 8 || store.busy)
            NidaaButton(title: "إنهاء هذه الجلسة", icon: "rectangle.portrait.and.arrow.right", secondary: true, id: "integrationLogout") { Task { await store.logout(allDevices: false) } }.disabled(store.busy)
            NidaaButton(title: "إلغاء جميع جلسات الحساب", icon: "lock.slash", secondary: true, id: "integrationRevokeAll") { Task { await store.logout(allDevices: true) } }.disabled(store.busy)
            Text("إلغاء كل الجلسات وحذف الحساب يحتاجان تسجيل دخول حديثًا. تجديد الرمز لا يجدد هذا التحقق.").font(.footnote)
            NidaaButton(title: "حذف الحساب التجريبي", icon: "trash", secondary: true, id: "integrationDeleteAccount") { deletion = true }.disabled(!store.canMutate)
        }.onDisappear { password = "" }
        .alert("حذف هذا الحساب التجريبي؟", isPresented: $deletion) {
            Button("حذف الحساب", role: .destructive) { Task { await store.command("delete_account", payload: [:]) } }
            Button("إلغاء", role: .cancel) {}
        } message: { Text("تُلغى الجلسات والموافقات. الحذف يخص هذه البيئة المحلية فقط.") }
    }
}

@MainActor struct IntegrationConsentView: View {
    @ObservedObject var store: IntegrationStore
    @State private var email = ""
    @State private var token = ""
    @State private var consent = false
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
        NidaaCard {
            Text("دعوة بموافقة واضحة").font(.title2.bold())
            Text("قبول الدعوة يسمح لصاحبها بإرسال نداء إليك فقط. الاتجاه الآخر يحتاج دعوة وقبولًا مستقلين.")
            TextField("بريد المستقبِل الخيالي", text: $email).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress).textFieldStyle(.roundedBorder).environment(\.layoutDirection, .leftToRight).accessibilityIdentifier("integrationInviteEmail")
            NidaaButton(title: "إنشاء دعوة", icon: "person.badge.plus", id: "integrationCreateInvite") { Task { await store.command("invite", payload: ["recipient_email": .string(email)]) } }
                .disabled(!email.lowercased().hasSuffix(".invalid") || !email.contains("@") || !store.canMutate)
            if !store.invitationToken.isEmpty {
                Text("رمز الدعوة جاهز. يُنسخ محليًا لمدة دقيقة ولا يظهر في الشاشة.").font(.footnote)
                NidaaButton(title: "نسخ رمز الدعوة محليًا", icon: "doc.on.doc", secondary: true, id: "integrationCopyInvite") {
                    UIPasteboard.general.setItems([["public.utf8-plain-text": store.invitationToken]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60)])
                    store.invitationToken = ""
                }
            }
        }
        NidaaCard {
            Text("قبول دعوة واردة").font(.headline)
            SecureField("رمز الدعوة", text: $token).keyboardType(.asciiCapable).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder).environment(\.layoutDirection, .leftToRight).accessibilityIdentifier("integrationInviteToken")
            Toggle("أوافق على استقبال نداءات صاحب هذه الدعوة", isOn: $consent).accessibilityIdentifier("integrationConsentToggle")
            NidaaButton(title: "قبول هذا الاتجاه فقط", icon: "checkmark", id: "integrationAcceptInvite") {
                let value = token; token = ""; consent = false; Task { await store.command("decide_invite", payload: ["token": .string(value), "decision": .string("accepted")]) }
            }.disabled(!consent || token.isEmpty || !store.canMutate)
            NidaaButton(title: "رفض الدعوة", icon: "xmark", secondary: true, id: "integrationDeclineInvite") {
                let value = token; token = ""; consent = false; Task { await store.command("decide_invite", payload: ["token": .string(value), "decision": .string("declined")]) }
            }.disabled(token.isEmpty || !store.canMutate)
        }
        ForEach(store.invitations) { invitation in
            NidaaCard {
                Label(invitation.incoming ? "دعوة واردة" : "دعوة صادرة", systemImage: "envelope")
                Text(IntegrationLabels.state(invitation.state))
                if !invitation.incoming && invitation.state == "pending" {
                    NidaaButton(title: "إلغاء الدعوة", icon: "xmark", secondary: true, id: "integrationCancelInvite") { Task { await store.command("cancel_invite", payload: ["invitation_id": .string(invitation.id.uuidString)]) } }.disabled(!store.canMutate)
                }
            }
        }
        ForEach(store.people) { person in
            NidaaCard {
                Text(store.label(person.sender == store.accountID ? person.recipient : person.sender)).font(.headline)
                Text(person.sender == store.accountID ? "يمكنني الإرسال إليه · موافقة في اتجاه واحد" : "يمكنه إرسال نداء إليّ · موافقة في اتجاه واحد")
                Text(person.accepted ? "الموافقة سارية" : "الموافقة غير متاحة").font(.footnote)
                if person.recipient == store.accountID && person.accepted {
                    NidaaButton(title: "سحب موافقتي", icon: "hand.raised", secondary: true, id: "integrationWithdraw") { Task { await store.command("withdraw", payload: ["sender_id": .string(person.sender.uuidString)]) } }.disabled(!store.canMutate)
                }
                NidaaButton(title: "حظر الحساب", icon: "nosign", secondary: true, id: "integrationBlock") { Task { await store.command("block", payload: ["user_id": .string((person.sender == store.accountID ? person.recipient : person.sender).uuidString)]) } }.disabled(!store.canMutate)
                if !person.accepted {
                    NidaaButton(title: "إلغاء الحظر فقط", icon: "person.crop.circle", secondary: true, id: "integrationUnblock") { Task { await store.command("unblock", payload: ["user_id": .string((person.sender == store.accountID ? person.recipient : person.sender).uuidString)]) } }.disabled(!store.canMutate)
                }
            }
        }
        NidaaCard {
            Text("إلغاء الحظر لا يعيد الموافقة").font(.headline)
            Text("بعد سحب الموافقة أو الحظر، يلزم قبول دعوة جديدة لإتاحة الإرسال مجددًا. لا يكشف التطبيق أسباب عدم إتاحة حساب آخر.").font(.footnote)
        }
        }.onDisappear { token = ""; consent = false; store.invitationToken = "" }
    }
}

enum IntegrationLabels {
    static func state(_ value: String) -> String {
        switch value {
        case "active": return "نداء نشط"
        case "accepted": return "مقبولة"
        case "pending": return "بانتظار الموافقة"
        case "responding": return "استجاب الشخص: سأتولى المساعدة"
        case "declined": return "اعتذر الشخص عن المساعدة"
        case "cancelled": return "أُلغيت"
        case "resolved": return "انتهت بتأكيد صريح"
        case "expired": return "انتهت الصلاحية"
        case "none": return "لا توجد استجابة بشرية"
        default: return "غير متاحة"
        }
    }
}
#endif

import SwiftUI
import UIKit
import ProofCore

@MainActor struct SettingsView: View {
    @ObservedObject var store: ExperienceStore
    @State private var resetConfirmation = false
    var body: some View {
        ScreenBody {
            SimulationNotice(authSimulation: store.simulationAuthentication)
            NidaaButton(title: "المظهر والألوان",icon: "paintpalette",secondary: true,id: "appearanceSettings") { store.screen = .appearance }
            NidaaCard {
                Toggle("قفل التطبيق بوسيلة النظام",isOn: Binding(get: { store.lockEnabled },set: { enabled in Task { await store.setAppLock(enabled) } })).disabled(store.busy).accessibilityIdentifier("appLockSetting")
                Text("قفل اختياري عند العودة من الخلفية. لا يمنع ظهور وارد عام دون تفاصيل. إنشاء نداء يتطلب دائمًا تحققًا جديدًا.").font(.footnote)
                Text(store.authLabel).font(.footnote)
            }
            NidaaButton(title: "الجاهزية والأذونات",icon: "shield",secondary: true,id: "settingsReadiness") { store.screen = .readiness }
            NidaaButton(title: "شروط الاستخدام",icon: "doc.text",secondary: true,id: "terms") { store.screen = .terms }
            NidaaButton(title: "الخصوصية والبيانات المحلية",icon: "hand.raised",secondary: true,id: "privacy") { store.screen = .privacy }
            if store.isDebugSimulator {
                NidaaCard {
                    Toggle("مصادقة محاكية على Simulator",isOn: $store.simulationAuthentication).accessibilityIdentifier("debugAuthSetting")
                    Text("Debug Simulator فقط؛ غير موجودة على جهاز فعلي أو Release. كل إنشاء يحتاج نتيجة تحقق جديدة حتى في المحاكاة.").font(.footnote)
                }
            }
            NidaaButton(title: "أدوات الإثبات التقنية المنفصلة",icon: "wrench.and.screwdriver",secondary: true,id: "technicalTools") { store.screen = .technical }
            Text("أدوات الإشعار الحقيقي وAPNs معطلة في هذه المرحلة. لا صوت أو كشاف أو اتصال تلقائي.").font(.footnote)
            NidaaButton(title: "إعادة ضبط البيانات التجريبية",icon: "arrow.counterclockwise",secondary: true,id: "resetDemo") { resetConfirmation = true }
            Text("تحذف جهات العرض المحفوظة والألوان والقفل، وتمسح سجل الجلسة، ثم تعيد شخصيات خيالية افتراضية.").font(.footnote)
            if !store.message.isEmpty { Text(store.message).font(.footnote).accessibilityIdentifier("settingsMessage") }
        }.navigationTitle("الإعدادات")
        .alert("إعادة ضبط النموذج المحلي؟",isPresented: $resetConfirmation) {
            Button("إعادة الضبط",role: .destructive) { store.resetDemo() }.accessibilityIdentifier("confirmReset")
            Button("إلغاء",role: .cancel) {}
        } message: { Text("لن تُحذف بيانات من حساب خارجي؛ لا يوجد خادم أو حساب في هذه المرحلة.") }
    }
}
@MainActor struct ReadinessView: View {
    @ObservedObject private var proof = ProofStore.shared
    var body: some View {
        ScreenBody {
            Text("الجاهزية ليست ضمان وصول").font(.largeTitle.bold())
            NidaaCard {
                Label("محاكاة النداءات المحلية متاحة",systemImage: "checkmark.circle").font(.headline)
                Text("لا تحتاج إذن إشعار لتجربة الدائرة والتدفق المحلي. لا تُرسل المحاكاة إشعار نظام.").font(.footnote)
            }
            NidaaCard {
                Text("حالة فعلية مقروءة من النظام").font(.headline)
                permission("الإذن", proof.permissions.authorization)
                permission("العرض", proof.permissions.alerts)
                permission("الصوت", proof.permissions.sounds)
                permission("شاشة القفل", proof.permissions.lockScreen)
                permission("Critical Alerts", proof.permissions.critical)
                if proof.permissions.authorization == "لم يُطلب" {
                    NidaaButton(title: "طلب إذن الإشعارات مسبقًا",icon: "bell.badge",id: "requestPermission") { Task { await proof.requestPermission() } }
                } else {
                    NidaaButton(title: "فتح إعدادات التطبيق",icon: "gearshape",secondary: true) { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                }
                NidaaButton(title: "تحديث حالة الأذونات",icon: "arrow.clockwise",secondary: true,id: "refreshReadiness") { Task { await proof.refresh() } }
            }
            Text("لم يُختبر استقبال أو صوت على iPhone فعلي؛ لا تتوفر أجهزة Apple. الاختبار المادي مؤجل ولا يمنع تطوير هذه المحاكاة.")
            Text("APNs غير متصل. التنبيه الحرج يحتاج موافقة Apple وentitlement مناسبًا وإذن المستخدم واختبارًا فعليًا. لا وعد بتغيير وضع الصامت أو تشغيل الصوت عبر كل السماعات. الميكروفون مدخل للصوت وليس مخرجًا.").font(.footnote)
            Text("لا نطلب ميكروفونًا أو موقعًا أو دفتر عناوين أو كاميرا. عند رفض الإشعارات نعرض إعدادات النظام بدل تكرار الطلب.").font(.footnote)
        }.navigationTitle("الجاهزية والأذونات").task { await proof.refresh() }
    }
    private func permission(_ name: String,_ value: String) -> some View { VStack(alignment: .leading) { Text(name).font(.caption);Text(value) } }
}
@MainActor struct AppearanceEditor: View {
    @ObservedObject var store: ExperienceStore
    @State private var draft: AppearancePreferences
    @State private var editingDark = true
    init(store: ExperienceStore) { self.store = store;_draft = State(initialValue: store.appearance) }
    private var editing: Palette { editingDark ? draft.dark : draft.light }
    private var preview: Palette { editing.valid ? editing : (editingDark ? .dark : .light) }
    var body: some View {
        ScreenBody {
            Text("المظهر والألوان").font(.largeTitle.bold())
            Text("المعاينة فورية ومعزولة؛ لا تطلق نداء. احفظ لتطبيق اختيارك، أو ألغِ للاحتفاظ بالمظهر السابق.").font(.footnote)
            Picker("مظهر التطبيق",selection: $draft.mode) { ForEach(AppearanceMode.allCases,id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.menu).accessibilityIdentifier("appearanceMode")
            Picker("تعديل لوحة",selection: $editingDark) { Text("داكن").tag(true);Text("فاتح").tag(false) }.pickerStyle(.segmented)
            VStack(alignment: .leading,spacing: 16) {
                Text("نداء — معاينة فقط").font(.headline).foregroundStyle(preview.accentInk.color)
                Text("دائرتك قريبة.").font(.largeTitle.bold()).foregroundStyle(preview.ink.color)
                NidaaButton(title: "طلب مساعدة · معاينة",icon: "bell",id: "previewButton") {}.allowsHitTesting(false)
                Label("الحالة تُشرح بالنص والرمز",systemImage: "checkmark.circle").foregroundStyle(preview.ink.color)
            }.padding(20).frame(maxWidth: .infinity,alignment: .leading).background(Color(hex: preview.background))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(preview.ink.color)).environment(\.nidaaPalette,preview)
                .accessibilityIdentifier("appearancePreview")
            colorField("لون الواجهة الأساسي",field: "primary",id: "primaryHex")
            colorField("لون الأزرار",field: "button",id: "buttonHex")
            colorField("الخلفية",field: "background",id: "backgroundHex")
            Text("يُختار لون النص والأيقونات تلقائيًا من الأسود والأبيض للتباين. لون العناوين الأساسي يُصحح للقراءة عند الحاجة؛ الحالات لا تعتمد على اللون وحده.").font(.footnote)
            if !draft.valid { Text("يلزم HEX صحيح من ست خانات يبدأ بـ# في اللوحتين.").accessibilityIdentifier("invalidColor") }
            NidaaButton(title: "حفظ التغييرات",icon: "checkmark",id: "saveAppearance") { store.saveAppearance(draft) }.disabled(!draft.valid)
            NidaaButton(title: "إلغاء التغييرات",icon: "xmark",secondary: true,id: "cancelAppearance") { store.screen = nil }
            NidaaButton(title: "استعادة الأصفر والأسود للمعاينة",icon: "arrow.counterclockwise",secondary: true,id: "restoreAppearance") { draft = .init();editingDark = true }
            if store.simulation.hasActive { Text("يتأجل تطبيق التغييرات حتى تنتهي جميع النداءات النشطة؛ لا يتبدل مظهر النداء فجأة.").font(.footnote) }
        }.navigationTitle("تخصيص المظهر")
    }
    private func binding(_ field: String) -> Binding<String> {
        Binding(get: { field == "primary" ? editing.primary : field == "button" ? editing.button : editing.background },set: { value in
            var p = editing
            switch field { case "primary": p.primary = value;case "button": p.button = value;default:p.background = value }
            if editingDark { draft.dark = p } else { draft.light = p }
        })
    }
    @ViewBuilder private func colorField(_ title: String,field: String,id: String) -> some View {
        VStack(alignment: .leading,spacing: 8) {
            ColorPicker(title,selection: Binding(get: { Color(hex: binding(field).wrappedValue) },set: { color in
                var r: CGFloat = 0,g: CGFloat = 0,b: CGFloat = 0,a: CGFloat = 0
                if UIColor(color).getRed(&r,green: &g,blue: &b,alpha: &a) { binding(field).wrappedValue = String(format: "#%02X%02X%02X",Int((r*255).rounded()),Int((g*255).rounded()),Int((b*255).rounded())) }
            }),supportsOpacity: false)
            TextField("#RRGGBB",text: binding(field)).font(.body.monospaced()).textInputAutocapitalization(.characters).autocorrectionDisabled()
                .textFieldStyle(.roundedBorder).environment(\.layoutDirection,.leftToRight).accessibilityLabel("\(title) HEX").accessibilityIdentifier(id)
        }
    }
}
struct PolicyView: View {
    let privacy: Bool
    var body: some View {
        ScreenBody {
            Text(privacy ? "الخصوصية والبيانات المحلية" : "شروط الاستخدام").font(.largeTitle.bold())
            Text("مسودة أولية للمرحلة الحالية · ليست مراجعة قانونية نهائية").font(.footnote)
            if privacy {
                section("ما يُحفظ ولماذا", "تُحفظ الأسماء الخيالية وحالات الدعوة وأذوناتها، وألوان المظهر وخيار قفل التطبيق محليًا داخل مساحة التطبيق لتستمر تجربتك بعد إعادة التشغيل. لا تُجمع أرقام أو مواقع أو دفتر عناوين. السجل والنداءات ونتائج التحقق في ذاكرة الجلسة فقط وتختفي عند إغلاق العملية.")
                section("المصادقة", "ينفذ نظام Apple التحقق الحيوي أو وسيلته البديلة. لا نستقبل صورة الوجه أو البصمة أو رمز الجهاز ولا نخزنها. المصادقة المحاكية متاحة فقط في Debug على Simulator، ويظهر تمييزها؛ ليست تحققًا حقيقيًا.")
                section("الحذف والتحكم", "يمكن حذف شخص أو سحب إذنه أو حظره. قد تبقى لقطة اسمه ضمن سجل الجلسة حتى إعادة التشغيل أو إعادة الضبط. إعادة ضبط البيانات من الإعدادات تحذف تفضيلات العرض وجهات العرض والقفل وتعيد الشخصيات الخيالية؛ لا يوجد حساب خادمي يحتاج حذفًا.")
                section("المشاركة والخدمات", "هذه المرحلة لا ترسل نداءات أو إشعارات ولا تتصل بخادم نداء أو مزود APNs. قراءة إذن الإشعارات وطلبه يستعملان إعدادات Apple. لا توجد تحليلات أو إعلانات مدمجة. ملفات نتائج الاختبار السحابي تعرض بيانات خيالية فقط.")
                section("خدمة مستقبلية", "أي مزامنة أو خدمة إرسال أو حسابات حقيقية ستحتاج وصفًا جديدًا للبيانات والمستلمين والاستضافة والاحتفاظ وحقوق المستخدم قبل إطلاقها. لم تُحدد جهة قانونية أو قناة دعم؛ لا نخترعها ولا ندعي امتثالًا نهائيًا.")
            } else {
                section("الغرض والحدود", "نداء وسيلة تواصل مساندة مصممة لدائرة موثوقة. النسخة الحالية محاكاة محلية لا ترسل طلب مساعدة حقيقيًا، ولا تحل محل الجهات الرسمية ولا تضمن الوصول أو استجابة إنسان. في خطر حقيقي استخدم وسيلة الاتصال المناسبة بالجهات المختصة.")
                section("الجدية ومنع الإساءة", "التصميم مخصص للحاجة الجدية ولا يجوز استخدامه للمضايقة أو التخويف أو الادعاءات الكاذبة. لا تستخدم أسماء الأسرة أو معلومات أشخاص حقيقيين في بيانات العرض. هذه الواجهات لا تُنشئ خدمة بلاغات رسمية.")
                section("الموافقة والسحب والحظر", "لكل اتجاه إذن مستقل في الدائرة. الدعوة المعلّقة أو المرفوضة أو المحظورة لا تجيز الإرسال. يمكن سحب الإذن أو حظر الشخص أو حذفه. كل موافقة ودعوة هنا محاكية يضبطها مستخدم النموذج ولا تُرسل إلى شخص آخر.")
                section("معاني الحالة", "إنشاء النداء وإرساله المحاكى واستلامه وفتحه والاستجابة له حالات منفصلة. فتح الوارد أو إسكات العرض لا يعني قبول المسؤولية أو انتهاء الخطر. الرفض يتيح تجربة بديل؛ الإلغاء ليس إثبات السلامة؛ إنهاء الحالة إجراء صريح.")
                section("قواعد المنصة", "لا وعد بتغيير وضع الصامت أو تجاوز Focus أو تشغيل كل السماعات. التنبيهات الحرجة تحتاج موافقة Apple وصلاحية مناسبة وإذن المستخدم وإثبات جهاز. لم تُختبر هذه القدرات المادية، ولم يُقدم طلب رسمي أو تسجيل ملكية فكرية.")
            }
        }.navigationTitle(privacy ? "الخصوصية" : "الشروط").accessibilityIdentifier(privacy ? "privacyPage" : "termsPage")
    }
    private func section(_ title: String,_ body: String) -> some View { VStack(alignment: .leading,spacing: 10) { Text(title).font(.title2.bold());Text(body).fixedSize(horizontal: false,vertical: true) } }
}

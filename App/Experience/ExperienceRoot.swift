import SwiftUI
import ProofCore

@MainActor struct ExperienceRoot: View {
    @StateObject private var store = ExperienceStore()
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.scenePhase) private var phase
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        rootContent
            .safeAreaInset(edge: .top) {
                if !store.storageIssue.isEmpty {
                    VStack(alignment: .leading) {
                        Text(store.storageIssue).font(.footnote).accessibilityIdentifier("storageIssue")
                        Button("إعادة محاولة الاستعادة") { store.reloadStorage() }.accessibilityIdentifier("reloadStorage")
                    }.padding().background(.regularMaterial)
                }
            }
            .environment(\.nidaaPalette, store.palette)
            .environment(\.layoutDirection, .rightToLeft)
            .tint(store.palette.accentInk.color)
            .preferredColorScheme(store.appearance.mode == .system && store.frozenPalette == nil ? nil : (store.palette.ink.value == "#FFFFFF" ? .dark : .light))
            .sheet(isPresented: Binding(get: { store.screen != nil }, set: { if !$0 { store.cancelCompose() } })) {
                NavigationStack {
                    RoutedScreen(store: store)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { store.cancelCompose() }.accessibilityIdentifier("closeScreen") } }
                }
                .environment(\.nidaaPalette, store.palette).environment(\.layoutDirection, .rightToLeft)
                .tint(store.palette.accentInk.color)
                .preferredColorScheme(store.appearance.mode == .system && store.frozenPalette == nil ? nil : (store.palette.ink.value == "#FFFFFF" ? .dark : .light))
                .alert("مصادقة محاكية للاختبار", isPresented: $store.authChoicePending) {
                    Button("محاكاة النجاح") { store.answerAuthentication(true) }
                    Button("محاكاة الفشل") { store.answerAuthentication(false) }
                    Button("إلغاء", role: .cancel) { store.answerAuthentication(false) }
                } message: { Text("متاحة في Debug على Simulator فقط. لا يثبت هذا تحقق Face ID فعليًا.") }
            }
            .alert("مصادقة محاكية للاختبار", isPresented: Binding(get: { store.screen == nil && store.authChoicePending }, set: { if !$0 { store.answerAuthentication(false) } })) {
                Button("محاكاة النجاح") { store.answerAuthentication(true) }
                Button("محاكاة الفشل") { store.answerAuthentication(false) }
                Button("إلغاء", role: .cancel) { store.answerAuthentication(false) }
            }
            .onReceive(timer) { _ in store.tick() }
            .onChange(of: phase) { value in if value == .background { store.backgrounded() };if value == .active { store.tick() } }
            .onChange(of: systemScheme) { store.systemDark = $0 == .dark }
            .onAppear { store.systemDark = systemScheme == .dark }
    }
    @ViewBuilder private var rootContent: some View {
        if store.locked { NavigationStack { LockedView(store: store) } }
        else {
            TabView(selection: $store.tab) {
                NavigationStack { HomeView(store: store) }.tabItem { Label("الرئيسية", systemImage: "house") }.tag(AppTab.home)
                NavigationStack { ContactsView(store: store) }.tabItem { Label("دائرتي", systemImage: "person.2") }.tag(AppTab.contacts)
                NavigationStack { HistoryView(store: store) }.tabItem { Label("السجل", systemImage: "clock.arrow.circlepath") }.tag(AppTab.history)
                NavigationStack { SettingsView(store: store) }.tabItem { Label("الإعدادات", systemImage: "slider.horizontal.3") }.tag(AppTab.settings)
            }
        }
    }
}
@MainActor struct RoutedScreen: View {
    @ObservedObject var store: ExperienceStore
    @ViewBuilder var body: some View {
        switch store.screen {
        case .action: AlertActionView(store: store)
        case .compose: ComposeView(store: store)
        case .alert(let id): AlertDetailView(store: store, id: id)
        case .incoming(let id): IncomingView(store: store, id: id)
        case .editContact(let id): ContactEditor(store: store, contact: store.simulation.contacts.first { $0.id == id } ?? TrustedContact(name: ""))
        case .readiness: ReadinessView()
        case .appearance: AppearanceEditor(store: store)
        case .terms: PolicyView(privacy: false)
        case .privacy: PolicyView(privacy: true)
        case .technical: ProofView(store: ProofStore.shared).safeAreaInset(edge: .top) { Text("أدوات منفصلة · إرسال إشعارات النظام وAPNs معطّل في هذه المرحلة").font(.footnote).padding().background(.regularMaterial) }
        case nil: EmptyView()
        }
    }
}
@MainActor struct LockedView: View {
    @ObservedObject var store: ExperienceStore
    var body: some View {
        ScreenBody {
            SimulationNotice(authSimulation: store.simulationAuthentication)
            Image(systemName: "lock.shield").font(.system(size: 56)).accessibilityHidden(true)
            Text("نداء مقفل").font(.largeTitle.bold())
            Text("تبقى معاينة النداء الوارد متاحة دون كشف الاسم أو التفاصيل.")
            Text(store.authLabel).font(.footnote)
            if !store.message.isEmpty { Text(store.message).font(.footnote) }
            NidaaButton(title: "فتح القفل", icon: "faceid", id: "unlockApp") { Task { await store.unlock() } }.disabled(store.busy)
            NidaaButton(title: "محاكاة نداء وارد أثناء القفل", icon: "bell", secondary: true, id: "lockedIncoming") { store.simulateIncoming() }
            if let id = store.incomingID, store.simulation.alerts.contains(where: { $0.id == id && $0.isActive }) {
                NidaaButton(title: "عرض النداء الوارد", icon: "bell.badge", secondary: true) { store.openIncoming(id) }
            }
        }.navigationTitle("التحقق")
    }
}

import SwiftUI
import UIKit

@MainActor final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        ProofStore.shared.notifications.installDelegate()
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        ProofStore.shared.registered(deviceToken)
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        ProofStore.shared.registrationFailed()
    }
}

@main @MainActor struct NidaaProofApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = ProofStore.shared
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            ProofView(store: store)
                .environment(\.layoutDirection, .rightToLeft)
                .preferredColorScheme(.dark)
                .task { await store.refresh() }
                .onChange(of: scenePhase) { phase in
                    if phase == .active { Task { await store.refresh() } }
                    if phase == .background { store.backgrounded() }
                }
        }
    }
}

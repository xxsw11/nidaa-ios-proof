import Foundation
import UIKit
import UserNotifications
import ProofCore

struct PermissionSnapshot {
    let authorization: String
    let alerts: String
    let sounds: String
    let lockScreen: String
    let center: String
    let critical: String
    let scheduledDelivery: String
    let permitsScheduling: Bool
    static let unknown = PermissionSnapshot(authorization: "لم يُقرأ بعد", alerts: "—", sounds: "—", lockScreen: "—", center: "—", critical: "—", scheduledDelivery: "—", permitsScheduling: false)
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    @MainActor var onObservation: ((ProofEnvelope, Observation) -> Void)?
    @MainActor var mayPresent: ((ProofEnvelope) -> Bool)?
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        guard ExecutionScope.allowsSystemNotifications, let envelope = Self.envelope(notification) else { completionHandler([]); return }
        Task { @MainActor in
            self.onObservation?(envelope, .foregroundCallback)
            completionHandler(self.mayPresent?(envelope) == true ? [.banner, .list, .sound] : [])
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void) {
        guard response.actionIdentifier != UNNotificationDismissActionIdentifier,
              let envelope = Self.envelope(response.notification) else { completionHandler(); return }
        Task { @MainActor in
            self.onObservation?(envelope, .notificationOpened)
            completionHandler()
        }
    }
    static func envelope(_ notification: UNNotification) -> ProofEnvelope? {
        let kind: NotificationKind = notification.request.trigger is UNPushNotificationTrigger ? .remote : .local
        return ProofEnvelope.decode(notification.request.content.userInfo, kind: kind)
    }
}

@MainActor final class NotificationService {
    let delegate = NotificationDelegate()
    private let center = UNUserNotificationCenter.current()
    func installDelegate() { center.delegate = delegate }
    func requestPermission() async throws {
        let current = await center.notificationSettings()
        guard current.authorizationStatus == .notDetermined else { return }
        _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }
    func settings() async -> PermissionSnapshot {
        let s = await center.notificationSettings()
        let authorization: String
        switch s.authorizationStatus {
        case .notDetermined: authorization = "لم يُطلب"
        case .denied: authorization = "مرفوض"
        case .authorized: authorization = "مسموح"
        case .provisional: authorization = "مؤقت / تقديم هادئ"
        case .ephemeral: authorization = "مؤقت قصير"
        @unknown default: authorization = "حالة غير معروفة"
        }
        return PermissionSnapshot(authorization: authorization, alerts: label(s.alertSetting),
            sounds: label(s.soundSetting), lockScreen: label(s.lockScreenSetting),
            center: label(s.notificationCenterSetting), critical: label(s.criticalAlertSetting),
            scheduledDelivery: label(s.scheduledDeliverySetting),
            permitsScheduling: [.authorized, .provisional, .ephemeral].contains(s.authorizationStatus))
    }
    private func label(_ value: UNNotificationSetting) -> String {
        switch value { case .enabled: return "مفعّل"; case .disabled: return "معطّل"
        case .notSupported: return "غير مدعوم"; @unknown default: return "غير معروف" }
    }
    func schedule(_ envelope: ProofEnvelope, after delay: TimeInterval) async throws {
        guard ExecutionScope.allowsSystemNotifications else { throw NSError(domain: "NIDAA.LocalSimulationOnly", code: 1) }
        let content = UNMutableNotificationContent()
        content.title = "نداء — اختبار محلي فقط"
        content.body = "اختبار عرض وصوت على هذا الجهاز؛ لا طلب مساعدة حقيقي."
        content.sound = .default
        content.interruptionLevel = .active
        content.userInfo = envelope.userInfo
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        try await center.add(UNNotificationRequest(identifier: envelope.id.uuidString, content: content, trigger: trigger))
    }
    func delivered() async -> [ProofEnvelope] {
        let items = await center.deliveredNotifications()
        return items.compactMap(NotificationDelegate.envelope)
    }
    func cancel(_ id: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        center.removeDeliveredNotifications(withIdentifiers: [id.uuidString])
    }
    func clearThisProof() {
        // This bundle is dedicated to the proof; this does not affect any other app.
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
}

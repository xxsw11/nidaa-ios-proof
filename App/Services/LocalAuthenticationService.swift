import Foundation
import LocalAuthentication

enum AuthenticationOutcome { case success, cancelled, failed(String) }

@MainActor final class LocalAuthenticationService {
    private var current: LAContext?
    func authenticate(reason: String) async -> AuthenticationOutcome {
        cancel()
        let context = LAContext()
        context.localizedCancelTitle = "إلغاء"
        context.localizedFallbackTitle = "استخدام رمز الجهاز"
        context.touchIDAuthenticationAllowableReuseDuration = 0
        current = context
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            current = nil
            return .failed(Self.explain(error))
        }
        let result: AuthenticationOutcome = await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                if success { continuation.resume(returning: .success) }
                else if let e = error as? LAError, [.userCancel, .appCancel, .systemCancel].contains(e.code) {
                    continuation.resume(returning: .cancelled)
                } else { continuation.resume(returning: .failed(Self.explain(error))) }
            }
        }
        if current === context { current = nil }
        context.invalidate()
        return result
    }
    func cancel() { current?.invalidate(); current = nil }
    nonisolated private static func explain(_ error: Error?) -> String {
        guard let e = error as? LAError else { return "تعذّر التحقق؛ لم يُسمح بالإجراء." }
        switch e.code {
        case .passcodeNotSet: return "يلزم تفعيل رمز الجهاز في إعدادات iPhone."
        case .biometryNotAvailable: return "الحيوية غير متاحة؛ استخدم وسيلة النظام المتاحة."
        case .biometryNotEnrolled: return "لم تُسجّل حيوية؛ يتيح النظام رمز الجهاز عند توفره."
        case .biometryLockout: return "الحيوية مقفلة؛ افتح الجهاز برمز النظام ثم أعد المحاولة."
        case .authenticationFailed: return "لم ينجح التحقق. لم يُنفّذ الإجراء."
        case .notInteractive: return "التحقق يتطلب ظهور التطبيق."
        default: return "تعذّر التحقق أو أبطله النظام. أعد المحاولة يدويًا."
        }
    }
}

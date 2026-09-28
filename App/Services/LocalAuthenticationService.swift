import Foundation
import LocalAuthentication

enum AuthenticationOutcome { case success, cancelled, failed(String) }

@MainActor final class LocalAuthenticationService {
    private var current: LAContext?
    private(set) var lastMethod = "لم يُجرَ تحقق"
    func authenticate(reason: String) async -> AuthenticationOutcome {
        cancel()
        lastMethod = "جارٍ التحقق بوسيلة النظام"
        let context = LAContext();current = context
        context.localizedCancelTitle = "إلغاء"
        context.localizedFallbackTitle = "وسيلة النظام البديلة"
        context.touchIDAuthenticationAllowableReuseDuration = 0
        defer { if current === context { current = nil };context.invalidate() }
        var availability: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &availability) {
            let (success, error) = await evaluate(context, .deviceOwnerAuthenticationWithBiometrics, reason)
            guard current === context else { return .cancelled }
            if success {
                lastMethod = context.biometryType == .faceID ? "نجح Face ID" : "نجحت المصادقة الحيوية"
                return .success
            }
            let code = (error as? LAError)?.code
            if code != .userFallback && code != .biometryLockout { return outcome(error) }
        }
        guard current === context else { return .cancelled }
        var fallbackError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &fallbackError) else {
            lastMethod = "لا تتوفر وسيلة تحقق للنظام"
            return .failed(Self.explain(fallbackError))
        }
        // iOS owns this fallback and may choose the available system method. No app PIN field.
        lastMethod = "وسيلة النظام البديلة؛ قد تشمل رمز الجهاز"
        let (success, error) = await evaluate(context, .deviceOwnerAuthentication, reason)
        guard current === context else { return .cancelled }
        return success ? .success : outcome(error)
    }
    private func evaluate(_ context: LAContext, _ policy: LAPolicy, _ reason: String) async -> (Bool, Error?) {
        await withCheckedContinuation { continuation in
            context.evaluatePolicy(policy, localizedReason: reason) { success, error in continuation.resume(returning: (success,error)) }
        }
    }
    private func outcome(_ error: Error?) -> AuthenticationOutcome {
        if let error = error as? LAError, [.userCancel,.appCancel,.systemCancel].contains(error.code) { lastMethod = "أُلغي التحقق";return .cancelled }
        lastMethod = "لم ينجح التحقق";return .failed(Self.explain(error))
    }
    func cancel() { current?.invalidate();current = nil }
    nonisolated private static func explain(_ error: Error?) -> String {
        guard let e = error as? LAError else { return "تعذّر التحقق؛ لم يُسمح بالإجراء." }
        switch e.code {
        case .passcodeNotSet: return "يلزم رمز جهاز من إعدادات iPhone. لا يوجد رمز داخل التطبيق."
        case .biometryLockout: return "الحيوية مقفلة؛ استخدم وسيلة النظام المتاحة."
        case .authenticationFailed: return "فشل التحقق. لم يُنشأ نداء."
        default: return "التحقق غير متاح أو أبطله النظام؛ أعد المحاولة يدويًا."
        }
    }
}

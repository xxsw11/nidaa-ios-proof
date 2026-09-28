import Foundation
import UIKit

@MainActor final class RemoteRegistrationService {
    static var compiledIn: Bool {
        #if APNS_ENABLED
        return true
        #else
        return false
        #endif
    }
    func register() {
        guard ExecutionScope.allowsSystemNotifications else { return }
        #if APNS_ENABLED
        UIApplication.shared.registerForRemoteNotifications()
        #endif
    }
    func stop() { UIApplication.shared.unregisterForRemoteNotifications() }
    // No provider or acknowledgment endpoint is configured in this proof.
}

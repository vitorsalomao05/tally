import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp` for the "Launch at login" toggle.
///
/// It reports the *real* registration status rather than a wishful boolean, so
/// the UI can show what the system actually believes. With an **ad-hoc** signed
/// build, `register()` may fail (the OS distrusts an unsigned login item) or land
/// in `.requiresApproval`; we surface the error instead of crashing. Signed with
/// a Developer ID certificate this works without any user friction.
@MainActor
final class LaunchAtLogin: ObservableObject {
    @Published private(set) var status: SMAppService.Status
    /// Last `register()`/`unregister()` error, if any (cleared on success).
    @Published private(set) var lastError: String?

    var isEnabled: Bool { status == .enabled }

    init() {
        status = SMAppService.mainApp.status
    }

    /// Re-read the live status from the system (login items can change out of band).
    func refresh() {
        status = SMAppService.mainApp.status
    }

    /// Register or unregister the app as a login item, reporting the outcome.
    /// Returns `true` on a clean call (no thrown error), `false` otherwise.
    @discardableResult
    func setEnabled(_ enable: Bool) -> Bool {
        do {
            if enable {
                // `register()` throws if already enabled; guard to keep it idempotent.
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
            refresh()
            return true
        } catch {
            let ns = error as NSError
            lastError = "\(ns.localizedDescription) (\(ns.domain) \(ns.code))"
            refresh()
            return false
        }
    }

    /// Human-readable status for the Settings panel.
    var statusText: String {
        switch status {
        case .notRegistered:    return "Not registered — toggle to enable"
        case .enabled:          return "Enabled — starts at login"
        case .requiresApproval: return "Needs approval — System Settings ▸ General ▸ Login Items"
        case .notFound:         return "Not registered yet — toggle to enable"
        @unknown default:       return "Unknown"
        }
    }
}

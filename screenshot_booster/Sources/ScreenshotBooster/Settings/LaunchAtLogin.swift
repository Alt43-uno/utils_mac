import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService` so the settings UI does not need to know
/// about the service registration details.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Whether macOS is currently blocking the login item (the user disabled it
    /// in System Settings › General › Login Items).
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        do {
            if enabled {
                guard SMAppService.mainApp.status != .enabled else { return }
                try SMAppService.mainApp.register()
            } else {
                guard SMAppService.mainApp.status == .enabled else { return }
                try SMAppService.mainApp.unregister()
            }
            Log.app.info("Launch at login set to \(enabled, privacy: .public)")
        } catch {
            throw AppError.launchAtLoginFailed(error.localizedDescription)
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
